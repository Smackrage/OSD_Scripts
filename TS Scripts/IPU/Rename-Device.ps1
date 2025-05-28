<#
.SYNOPSIS
Renames a Windows machine from "VX-%serial%" to "V1-%serial%" in an MECM Task Sequence.
 
.DESCRIPTION
This script does the following
1. Checks if the current name follows the "VX-XXXXX" format.
2. Replaces the second character ("X") with "1".
3. Renames the computer without forcing a restart.
4. Logs the changes to a file for troubleshooting.
5. Allows Active Directory to update automatically within 24 hours.
 
.EXAMPLE
.\Rename-Computer-MECM.ps1
Logs to C:\Windows\ccm\logs\RenameComputer.log.
 
.NOTES
Author: Martin Smith (D3)
Date: 30 January 2025
Version: 1.0
Compatibility: Windows 10, Windows 11
Tested with MECM Task Sequences and package deployments.
#>
 
# Set log file location
$LogFile = "C:\Windows\ccm\logs\RenameComputer.log"
 
# Function to log messages
function Write-Log {
    param ([string]$Message)
    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogFile -Value "$TimeStamp - $Message"
}
 
Write-Log "Starting rename process..."
 
# Get the current computer name
$CurrentName = $env:COMPUTERNAME
Write-Log "Current Computer Name: $CurrentName"
 
# Ensure the name starts with "VX-" before modifying
if ($CurrentName -match "^VX-(.*)") {
    # Replace the second character "X" with "1"
    $NewName = "V1-" + $matches[1]
    Write-Log "New Computer Name: $NewName"
 
    # Rename the computer (without restart)
    try {
        Rename-Computer -NewName $NewName -Force -ErrorAction Stop
        Write-Log "Rename successful. Active Directory will update within 24 hours."
        Write-Log "A restart is required for the change to fully apply."
    } catch {
        Write-Log "ERROR: Failed to rename the computer. $_"
        Exit 1  # Exit with an error for MECM to detect failure
    }
} else {
    Write-Log "Computer name does not match 'VX-XXXXX' pattern. No changes made."
    Exit 0  # Exit with success (no change needed)
}
 
Exit 0  # Success for MECM