<#
.SYNOPSIS
A PowerShell script template with logging included by default.

.DESCRIPTION
This script provides a structured template for PowerShell scripts, ensuring consistency and maintainability.

.NOTES
Author: Martin Smith (Data #3)
Date: 30/01/2025 (hardcoded to the script's creation date)
Version: 1.0
#>

# Define log file path (change as needed)
$LogFile = "$PSScriptRoot\ScriptLog.log"

function Write-Log {
    param (
        [string]$Message,
        [string]$Component = 'Script',
        [string]$Severity = '1'
    )
    $Time = Get-Date -Format "HH:mm:ss.fff"
    $Date = Get-Date -Format "MM-dd-yyyy"
    $ProcessID = $PID
    $Line = "$Time`,$Date`,$Component`,$Severity`,$Message`,$ProcessID"
    Add-Content -Path $LogFile -Value $Line
}

# Example usage
Write-Log -Message "Script started."

try {
    # Your code goes here
    Write-Log -Message "Running main script block."

    # Simulate some action
    Start-Sleep -Seconds 2

    Write-Log -Message "Script completed successfully." -Severity 1
}
catch {
    Write-Log -Message "ERROR: $($_.Exception.Message)" -Severity 3
    throw
}
