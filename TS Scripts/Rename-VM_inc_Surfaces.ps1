<#
.SYNOPSIS
Sets OSDComputerName for Surfaces (trim first 5 chars) or other devices (just prefix), with CMTrace‑compatible logging.

.DESCRIPTION
1. Determines manufacturer/model.  
2. Fetches BIOS serial.  
3. If Surface: chops off first 5 chars.  
4. Else: keeps full serial.  
5. Prefixes “v1-”.  
6. Writes to OSDComputerName.  
7. Logs every step to SetDeviceName.log for CMTrace.

.NOTES
Author: Martin Smith (Data#3)  
Date: 24/07/2025  
Version: 1.1  
#>

# —— Logging Setup —— 
$LogPath = if ($env:OSDLogPath) {
    Join-Path $env:OSDLogPath 'SetDeviceName.log'
} else {
    "$env:TEMP\SetDeviceName.log"
}

function Write-Log {
    param (
        [string]$Message,
        [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO'
    )
    $ts    = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $entry = "{0} [{1}] {2}" -f $ts, $Level, $Message
    Add-Content -Path $LogPath -Value $entry
    Write-Host $entry
}

Write-Log "===== Starting SetDeviceName script ====="

try {
    # —— Gather System Info —— 
    Write-Log "Getting system manufacturer/model..."
    $cs   = Get-CimInstance -ClassName Win32_ComputerSystem
    $manu = $cs.Manufacturer.Trim()
    $model= $cs.Model.Trim()
    Write-Log "Manufacturer: $manu; Model: $model"

    Write-Log "Retrieving BIOS serial number..."
    $bios = Get-CimInstance -ClassName Win32_Bios
    $full = $bios.SerialNumber.Trim()
    if (-not $full) { throw "SerialNumber is empty." }
    Write-Log "Full serial: $full"

    # —— Serial Processing —— 
    if ($model -like '*Surface*') {
        Write-Log "Detected Surface device – trimming first 8 characters."
        if ($full.Length -lt 8) { throw "Serial '$full' too short to trim." }
        $proc = $full.Substring(0,8)
        Write-Log "Trimmed serial: $proc"
    }
    else {
        Write-Log "Non Surface device – keeping full serial."
        $proc = $full
    }

    # —— Construct New Name —— 
    $newName = "v1-$proc"
    Write-Log "New computer name: $newName"

    # —— Apply to TS —— 
    Write-Log "Setting OSDComputerName..."
    $TSEnv = New-Object -ComObject Microsoft.SMS.TSEnvironment
    $TSEnv.Value('OSDComputerName') = $newName
    Write-Log "OSDComputerName set successfully."

} catch {
    Write-Log "ERROR: $_" 'ERROR'
    throw
} finally {
    Write-Log "===== Finished SetDeviceName script ====="
}

