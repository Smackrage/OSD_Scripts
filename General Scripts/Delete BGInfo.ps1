<#
.SYNOPSIS
Removes BGInfo and the "BGInfo reset" scheduled task.
.DESCRIPTION
Designed for use in an IPU Task Sequence. Logs to C:\Windows\CCM\Logs\BGInfoCleanup.log and echoes to SMSTS log via Write-Host.
.NOTES
Author: Ewan Monro
Date: 07/05/2025
#>
 
# Define CMTrace-compatible log file
$LogFile = "C:\Windows\CCM\Logs\BGInfoCleanup.log"
 
Function Write-Log {
    param (
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR")]
        [string]$Severity = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "$timestamp [$Severity] $Message"
    Add-Content -Path $LogFile -Value $entry
    Write-Host "$entry"
}
 
# Start
Write-Log "===== BGInfo Cleanup script started ====="
 
# Define values
$BGInfoPath = "C:\ProgramData\BGInfo"
$TaskName = "BGInfo reset"
 
# Remove BGInfo folder
if (Test-Path $BGInfoPath) {
    try {
        Write-Log "Removing BGInfo folder: $BGInfoPath"
        Remove-Item -Path $BGInfoPath -Recurse -Force -ErrorAction Stop
        Write-Log "Successfully deleted BGInfo folder."
    } catch {
        Write-Log "Failed to delete BGInfo folder: $_" "ERROR"
    }
} else {
    Write-Log "BGInfo folder not found. Skipping." "WARN"
}
 
# Remove scheduled task
try {
    Write-Log "Attempting to delete scheduled task: $TaskName"
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop
    Write-Log "Scheduled task '$TaskName' deleted."
} catch {
    Write-Log "Scheduled task '$TaskName' not found or failed to delete: $_" "WARN"
}
 
Write-Log "===== BGInfo Cleanup script completed ====="