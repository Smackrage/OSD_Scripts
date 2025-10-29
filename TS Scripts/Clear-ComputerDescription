<#
.SYNOPSIS
Updates the description attribute of a computer object in Active Directory.
 
.DESCRIPTION
This script searches for a specified computer object in Active Directory and updates its description attribute.
 
.NOTES
Author: Martin Smith (Data #3)
Date: 12/03/2025
Version: 1.2
#>
 
#Requires -RunAsAdministrator
 
# Define Computer Name and New Description
$ComputerName = $env:COMPUTERNAME
$NewDescription = ""
 
# Define Log Path
$LogPath = "C:\windows\ccm\logs\Update-ADComputerDescription.log"
 
# Logging Function (CMTrace-Compatible)
function Write-Log {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "<![LOG[$Message]LOG]!><time=""$Timestamp"" date=""$(Get-Date -Format 'yyyy-MM-dd')"" component=""Update-ADComputerDescription"" context="" "" type=""$Level"" thread="" "" file="""" />"
    Add-Content -Path $LogPath -Value $LogMessage
    Write-Output $Message
}
 
try {
    # Bind to RootDSE to obtain the default naming context
    $RootDSE = [ADSI]"LDAP://RootDSE"
    $DefaultNC = $RootDSE.defaultNamingContext
    Write-Log "Retrieved default naming context: $DefaultNC"
 
    # Create DirectorySearcher to find the computer object
    $Searcher = New-Object System.DirectoryServices.DirectorySearcher
    $Searcher.SearchRoot = [ADSI]"LDAP://$DefaultNC"
    $Searcher.Filter = "(&(objectClass=computer)(cn=$ComputerName))"
 
    $Result = $Searcher.FindOne()
 
    if ($Result -ne $null) {
        $Computer = $Result.GetDirectoryEntry()
        Write-Log "Computer '$ComputerName' found in Active Directory."
 
        # Update the description attribute
        $Computer.Properties["description"].Value = $NewDescription
        $Computer.CommitChanges()
 
        Write-Log "Description for computer '$ComputerName' updated successfully to '$NewDescription'."
    }
    else {
        Write-Log "Computer '$ComputerName' not found in Active Directory." -Level "ERROR"
    }
}
catch {
    Write-Log "An error occurred: $_" -Level "ERROR"
}
