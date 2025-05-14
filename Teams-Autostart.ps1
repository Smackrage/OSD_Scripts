<#
.SYNOPSIS
A PowerShell script to force the New Microsoft Teams client to autostart for users on first logon.

.DESCRIPTION
This script updates the Default User registry hive (so new profiles get the setting) and also enumerates loaded HKEY_USERS hives to enable Teams autostart for any existing users. It targets the MSIX startup task for the New Teams client.

.NOTES
Author: Martin Smith (Data #3)
Date:   14/05/2025
Version: 1.0
#>

#region Logging setup
$ScriptName = Split-Path -Leaf $MyInvocation.MyCommand.Path
$LogFile    = Join-Path $PSScriptRoot "$ScriptName.log"

function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$ts $Message" | Out-File -FilePath $LogFile -Append -Force
}

Write-Log "===== Script started ====="
#endregion

try {
    # Path to Default User hive
    $DefaultHiveFile = "$env:SystemDrive\Users\Default\NTUSER.DAT"
    $MountPoint      = 'HKLM\DefaultUser'

    Write-Log "Loading Default User hive from '$DefaultHiveFile'"
    reg.exe load $MountPoint $DefaultHiveFile | Out-Null

    # Registry path for New Teams MSIX startup task
    $DefaultTeamsKey = "Registry::HKLM\DefaultUser\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\MSTeams_8wekyb3d8bbwe\TeamsTfwStartupTask"

    Write-Log "Ensuring default-user key exists"
    if (-not (Test-Path $DefaultTeamsKey)) {
        New-Item -Path $DefaultTeamsKey -Force | Out-Null
    }

    Write-Log "Setting 'State' = 2 to enable autostart for New Teams (Default User)"
    Set-ItemProperty -Path $DefaultTeamsKey -Name 'State' -Value 2 -Type DWord -Force

    Write-Log "Unloading Default User hive"
    reg.exe unload $MountPoint | Out-Null

    # Apply to any currently-loaded user hives
    Write-Log "Applying to loaded user hives under HKEY_USERS"
    Get-ChildItem 'Registry::HKEY_USERS' |
        Where-Object {
            $_.PSChildName -notmatch '^(?:S-1-5-18|S-1-5-19|S-1-5-20)$' -and
            $_.PSChildName -notlike '*_Classes'
        } |
        ForEach-Object {
            $sid       = $_.PSChildName
            $userKey   = "Registry::HKEY_USERS\$sid\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\MSTeams_8wekyb3d8bbwe\TeamsTfwStartupTask"
            Write-Log "Processing SID $sid"

            if (-not (Test-Path $userKey)) {
                Write-Log "  Creating Teams startup key for $sid"
                New-Item -Path $userKey -Force | Out-Null
            }

            Write-Log "  Enabling autostart (State=2) for $sid"
            Set-ItemProperty -Path $userKey -Name 'State' -Value 2 -Type DWord -Force
        }

    Write-Log "===== Script completed successfully ====="
}
catch {
    Write-Log "ERROR: $_"
    throw
}
