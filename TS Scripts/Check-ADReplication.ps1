<#
.SYNOPSIS
Waits for AD computer object replication to the connected domain controller.

.DESCRIPTION
Used post-client install in an MECM Task Sequence to ensure the local Domain Controller has a replicated view of the computer account.
This was created due to the presence of a large amount of domain controllers in the environment, which can lead to delays in replication.
Without this script, random issues we seen when bitlocker was trying to escrow the recovery key to AD, as the computer object was not yet visible to the local DC.
This is a work around until the project is completed to reduce the number of domain controllers in the environment.

.NOTES
Author: Martin Smith (Data #3)
Date: 23/06/2025
Version: 1.1
#>

# Define constants
$MaxAttempts = 15
$WaitSeconds = 60
$ComputerName = $env:COMPUTERNAME
$Domain = ([System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()).Name
$LogFile = "C:\Windows\CCM\logs\ADReplicationCheck.log"

function Write-Log {
    param (
        [string]$Message,
        [string]$Type = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $logMessage = "$timestamp`0$Type`0$Message"
    Add-Content -Path $LogFile -Value $logMessage
    Write-Host "${Type}: $Message"
}

Write-Log "Starting AD replication check for computer '$ComputerName' in domain '$Domain'."

# Get the current domain controller the machine is connected to
$CurrentDC = ([System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()).FindDomainController().Name
Write-Log "Using domain controller: $CurrentDC"

$attempt = 0
$replicated = $false

do {
    $attempt++
    Write-Log "Attempt $attempt of $MaxAttempts - Checking if computer object '$ComputerName' is visible to the local DC..."

    try {
        # Query the local domain controller explicitly
        $Searcher = New-Object DirectoryServices.DirectorySearcher
        $Searcher.SearchRoot = "LDAP://$CurrentDC"
        $Searcher.Filter = "(&(objectClass=computer)(sAMAccountName=$ComputerName`$))"
        $Searcher.PropertiesToLoad.Add("name") | Out-Null
        $result = $Searcher.FindOne()

        if ($result) {
            Write-Log "Computer object '$ComputerName' found on domain controller '$CurrentDC'. Replication confirmed." "SUCCESS"
            $replicated = $true
        } else {
            Write-Log "Computer object '$ComputerName' not yet visible to '$CurrentDC'. Will retry after $WaitSeconds seconds." "WARN"
            Start-Sleep -Seconds $WaitSeconds
        }
    } catch {
        Write-Log "Error while querying AD: $_" "ERROR"
        Start-Sleep -Seconds $WaitSeconds
    }

} until ($replicated -or $attempt -ge $MaxAttempts)

if (-not $replicated) {
    Write-Log "Computer object '$ComputerName' did NOT replicate to the connected DC within the expected time window." "ERROR"
    exit 1
} else {
    Write-Log "Replication confirmed. Proceeding with task sequence." "INFO"
    exit 0
}
