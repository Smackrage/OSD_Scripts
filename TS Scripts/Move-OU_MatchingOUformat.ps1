<#
.SYNOPSIS
Retrieves the current computer's Active Directory Organisational Unit (OU), modifies it if necessary,
sets the modified OU as a task sequence variable, and moves the computer to that OU.

.DESCRIPTION
This script queries Active Directory for the computer's OU, replaces "Windows10 20H2" with "Windows11" if found,
sets the modified OU as a task sequence variable, and moves the computer account to the modified OU.

.NOTES
Author: Martin Smith (Data#3)
Date: 29 January 2025
Version: 1.5
Compatibility: Windows PowerShell 5.1 and above
#>

# Define the log file location
$LogFile = "C:\Windows\CCM\Logs\OUDetectionAndMove.log"

# Function to write log entries
function Write-Log {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "$Timestamp [$Level] $Message"
    Add-Content -Path $LogFile -Value $LogEntry
    Write-Host $LogEntry
}

# Define the task sequence variable name
$TaskSequenceVariableName = "ModifiedMachineOU"

try {
    # Get the current computer's name
    $ComputerName = $env:COMPUTERNAME
    Write-Log "Computer Name: $ComputerName"

    # Define the LDAP query to find the computer account
    $Domain = ([ADSI]"").distinguishedName
    $Searcher = New-Object DirectoryServices.DirectorySearcher
    $Searcher.Filter = "(&(objectClass=computer)(name=$ComputerName))"
    $Searcher.SearchRoot = "LDAP://$Domain"
    $Searcher.PropertiesToLoad.Add("distinguishedName") | Out-Null

    # Perform the search
    $SearchResult = $Searcher.FindOne()
    if (-not $SearchResult) {
        Write-Log "Computer account not found in Active Directory." -Level "ERROR"
        Exit 1
    }

    # Get the distinguished name of the computer account
    $CurrentDN = $SearchResult.Properties["distinguishedName"][0]
    Write-Log "Computer Distinguished Name: $CurrentDN"

    # Extract the OU portion of the DN (everything except CN)
    $OU = ($CurrentDN -split ',')[1..($CurrentDN.Length)] -join ','
    Write-Log "Organisational Unit before modification: $OU"

    # Check if "Windows10 20H2" is in the OU path and replace it with "Windows11"
    if ($OU -match "Windows10 20H2") {
        $OU = $OU -replace "Windows10 20H2", "Windows11"
        Write-Log "Organisational Unit modified to: $OU"
    } else {
        Write-Log "No changes made to OU, proceeding with existing OU."
        exit 0
    }

    # Set the modified OU as a task sequence variable
    $TSEnvironment = New-Object -COMObject Microsoft.SMS.TSEnvironment
    $TSEnvironment.Value($TaskSequenceVariableName) = $OU
    Write-Log "Task sequence variable '$TaskSequenceVariableName' set to: $OU"

    # Move the computer account to the modified OU
    Write-Log "Attempting to move computer '$ComputerName' to new OU: $OU"
    $ADSI = [ADSI]"LDAP://$CurrentDN"
    $ADSI.MoveTo([ADSI]"LDAP://$OU")
    Write-Log "Successfully moved computer account '$ComputerName' to '$OU'."
    Exit 0
}
catch {
    Write-Log "An error occurred: $_" -Level "ERROR"
    Exit 1
}
