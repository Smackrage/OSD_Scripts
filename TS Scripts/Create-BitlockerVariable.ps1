<#
.SYNOPSIS
Sets a task sequence variable for BitLocker status.

.DESCRIPTION
This script sets a task sequence variable called BitLockerStatus to 'false', if previous step 'Enable Bitlocker' fails. (which is my case is due to AD replication issues) 
It then exits with a custom exit code (404404).

.NOTES
Author: Martin Smith (Data #3)
Date: 27/08/2025
Version: 1.0
#>

# Set Task Sequence Variable
$TSEnv = New-Object -ComObject Microsoft.SMS.TSEnvironment
$TSEnv.Value("BitLockerStatus") = "False"

try {
    $dc = ([System.DirectoryServices.ActiveDirectory.Domain]::GetComputerDomain()).FindDomainController().Name
    if ($dc) { $TSEnv.Value("BitLockerDC") = $dc }
    Write-Host "DCInUse=$dc"
} catch {
    Write-Host "Could not resolve a DC (likely not domain-joined or running in WinPE)."
}

# Exit with requested code
Exit 404404
