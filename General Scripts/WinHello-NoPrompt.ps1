<#
.SYNOPSIS
Sets the Windows Hello for Business policy registry key.

.DESCRIPTION
This script sets the Enabled value under:
HKLM\SOFTWARE\Policies\Microsoft\PassportForWork

The script includes CMTrace-compatible logging, suitable for use in an SCCM Task Sequence.

.NOTES
Author: Martin Smith (Data #3)
Date: 21/10/2025
Version: 1.0
#>

#region Logging setup
function Write-Log {
    param(
        [string]$Message,
        [string]$Severity = "INFO"
    )

    $Time = (Get-Date).ToString("HH:mm:ss.fff")
    $Date = (Get-Date).ToString("MM-dd-yyyy")
    $Component = "Set-PassportForWorkKey"

    $LogLine = "<![LOG[$Message]LOG]!><time=""$Time"" date=""$Date"" component=""$Component"" context="""" type=""1"" thread=""$([System.Threading.Thread]::CurrentThread.ManagedThreadId)"" file="""">"
    Write-Output $LogLine
    Add-Content -Path $Global:LogFile -Value $LogLine
}

# Determine log file path
$LogRoot = $env:_SMSTSLogPath
if (-not $LogRoot) { $LogRoot = $env:LOGPATH }
if (-not $LogRoot) { 
    if (Test-Path "C:\Windows\CCM\Logs") {
        $LogRoot = "C:\Windows\CCM\Logs"
    } else {
        $LogRoot = "C:\Windows\Temp"
    }
}
$ScriptName = (Split-Path -Leaf $PSCommandPath)
$Global:LogFile = Join-Path $LogRoot "$($ScriptName).log"
#endregion Logging setup

Write-Log "----- Starting registry configuration for PassportForWork -----"

try {
    $RegPath = "HKLM:\SOFTWARE\Policies\Microsoft\PassportForWork"
    if (-not (Test-Path $RegPath)) {
        Write-Log "Registry key not found. Creating: $RegPath"
        New-Item -Path $RegPath -Force | Out-Null
    }

    Set-ItemProperty -Path $RegPath -Name "Enabled" -Value 1 -Type DWord -Force
    Write-Log "Successfully set 'Enabled' to 1 at $RegPath"
}
catch {
    Write-Log "Error: $($_.Exception.Message)" "ERROR"
    Exit 1
}

Write-Log "Registry modification completed successfully."
Write-Log "----- Script finished -----"
Exit 0
