<#

.SYNOPSIS

Copies a custom Start menu layout to all user profiles and the default profile.

.DESCRIPTION

This script applies a pre-configured Start menu layout by copying a template file to all user profiles and ensuring the default profile is updated for new users.

.EXAMPLE

.\Apply-StartMenuLayout.ps1

Copies the Start menu layout template to all existing and default user profiles.

.NOTES

Author: Martin Smith (Data3)

Date: 13 January 2025

Version: 1.1

Compatibility: Windows 11

#>

# Define log path

$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Definition)

$logPath = "c:\windows\ccm\logs\startmenu.log"

function Write-Log {

    param (

        [string]$Message,

        [string]$Level = "INFO"

    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $entry = "<$timestamp> [$Level] $Message"

    Add-Content -Path $logPath -Value $entry

}

# Source start menu template

$startmenuTemplate = ".\start2.bin"

Write-Host "Starting Start Menu layout deployment..."

Write-Log "Start Menu layout deployment started."

# Get all user profile folders

$usersStartMenu = Get-ChildItem -Path "C:\Users\*\AppData\Local\Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy\LocalState"

# Copy Start menu to all user folders

ForEach ($startmenu in $usersStartMenu) {

    try {

        Copy-Item -Path $startmenuTemplate -Destination $startmenu -Force

        $msg = "Copied Start menu layout to: $($startmenu.FullName)"

        Write-Host $msg

        Write-Log $msg

    } catch {

        $msg = "Failed to copy to: $($startmenu.FullName) - $_"

        Write-Warning $msg

        Write-Log $msg "ERROR"

    }

}

# Default profile path

$defaultProfile = "C:\Users\default\AppData\Local\Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy\LocalState"

# Create folder if it doesn't exist

if (-not (Test-Path $defaultProfile)) {

    try {

        New-Item -Path $defaultProfile -ItemType Directory -Force | Out-Null

        $msg = "Created default profile folder: $defaultProfile"

        Write-Host $msg

        Write-Log $msg

    } catch {

        $msg = "Failed to create default profile folder: $defaultProfile - $_"

        Write-Warning $msg

        Write-Log $msg "ERROR"

    }

}

# Copy file to the default profile

try {

    Copy-Item -Path $startmenuTemplate -Destination $defaultProfile -Force

    $msg = "Copied Start menu layout to default profile: $defaultProfile"

    Write-Host $msg

    Write-Log $msg

} catch {

    $msg = "Failed to copy Start menu layout to default profile: $defaultProfile - $_"

    Write-Warning $msg

    Write-Log $msg "ERROR"

}

# Get user profiles excluding system/default ones

$users = Get-CimInstance Win32_UserProfile | Where-Object {

    $_.LocalPath -notlike "*Default*" -and

    $_.LocalPath -notlike "*Public*" -and

    $_.Special -eq $false

}

 

$sharedLayoutPath = "C:\ProgramData\StartLayout"

$applyScriptPath = "$sharedLayoutPath\ApplyLayout.ps1"

 

# Ensure the layout and script exist

if (-not (Test-Path $sharedLayoutPath)) {

    New-Item -Path $sharedLayoutPath -ItemType Directory -Force | Out-Null

}

 

Copy-Item -Path $startmenuTemplate -Destination "$sharedLayoutPath\start2.bin" -Force

 

# Create script to apply layout once

Set-Content -Path $applyScriptPath -Value @'

$source = "C:\ProgramData\StartLayout\start2.bin"

$dest = "$env:LOCALAPPDATA\Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy\LocalState\start2.bin"

try {

    Copy-Item -Path $source -Destination $dest -Force

} catch {}

'@

 

# Inject into RunOnce for each profile

foreach ($user in $users) {

    try {

        $sid = $user.SID

        $userPath = $user.LocalPath

        $ntuserDat = Join-Path -Path $userPath -ChildPath "NTUSER.DAT"

        $hiveName = "TempHive_$($sid.Split('-')[-1])"

 

        # Skip if NTUSER.DAT doesn't exist

        if (-not (Test-Path $ntuserDat)) {

            Write-Warning "NTUSER.DAT not found for $userPath, skipping..."

            continue

        }

 

        # Load the hive if not already loaded

        if (-not (Test-Path "Registry::HKEY_USERS\$sid")) {

            reg load "HKU\$hiveName" "$ntuserDat" | Out-Null

            $regPath = "Registry::HKEY_USERS\$hiveName\Software\Microsoft\Windows\CurrentVersion\RunOnce"

        } else {

            $regPath = "Registry::HKEY_USERS\$sid\Software\Microsoft\Windows\CurrentVersion\RunOnce"

        }

 

        # Create RunOnce key if needed

        if (-not (Test-Path $regPath)) {

            New-Item -Path $regPath -Force | Out-Null

        }

 

        # Set RunOnce value

        Set-ItemProperty -Path $regPath -Name "ApplyStartLayoutOnce" -Value "powershell.exe -ExecutionPolicy Bypass -File `"$applyScriptPath`""

 

        Write-Host "Set RunOnce for user $userPath"

 

        # Unload hive if we loaded it

        if (Test-Path "Registry::HKEY_USERS\$hiveName") {

            reg unload "HKU\$hiveName" | Out-Null

        }

 

    } catch {

        Write-Warning "Failed to set RunOnce for $($user.LocalPath): $_"

    }

}

 

 

Write-Host "Start Menu layout deployment completed."

Write-Log "Start Menu layout deployment completed."