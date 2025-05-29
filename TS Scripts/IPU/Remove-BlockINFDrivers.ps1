<#

.SYNOPSIS

   Deletes INF files associated with "Microsoft XPS Document Writer" and "Microsoft Print to PDF" if a registry key is enabled.

.DESCRIPTION

   This SCCM Task Sequence-safe script backs up and removes oem*.inf and .pnf files referencing Microsoft virtual printers.

   Outputs CMTrace-compatible logs to C:\Temp\BlockedDrivers\PrintDriverRemoval.log.

#>

 

# Log file path

$logFile = "C:\Temp\BlockedDrivers\PrintDriverRemoval.log"

 

# CMTrace-style logging

function Write-CMLog {

    param (

        [string]$Message,

        [ValidateSet("INFO", "WARN", "ERROR")]

        [string]$Level = "INFO"

    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"

    $line = "$timestamp [$Level] $Message"

    Write-Output $line

    Add-Content -Path $logFile -Value $line

}

 

# Ensure log directory exists

if (-not (Test-Path "C:\Temp")) {

    New-Item -ItemType Directory -Path "C:\Temp" | Out-Null

}

 

# Ensure log directory exists

if (-not (Test-Path "C:\Temp\BlockedDrivers")) {

    New-Item -ItemType Directory -Path "C:\Temp\BlockedDrivers" | Out-Null

}

 

# Registry key to check

$regPath = "HKLM:\SOFTWARE\Virgin Australia\WaaS\24H2"

$regName = "BlockPrintDriver"

 

try {

    $regValue = Get-ItemProperty -Path $regPath -Name $regName -ErrorAction Stop | Select-Object -ExpandProperty $regName

    if ($regValue -ne 1) {

        Write-CMLog -Message "BlockPrintDriver is not set to 1. Skipping INF cleanup." -Level "INFO"

        exit 0

    }

    Write-CMLog -Message "BlockPrintDriver registry key found. Proceeding with INF cleanup." -Level "INFO"

}

catch {

    Write-CMLog -Message "Registry key/value not found. Skipping INF cleanup. Error: $_" -Level "INFO"

    exit 0

}

 

# Set INF directory path

$infPath = "$env:windir\INF"

$oemFiles = Get-ChildItem -Path $infPath -Filter 'oem*.inf' -ErrorAction SilentlyContinue

 

foreach ($file in $oemFiles) {

    try {

        $content = Get-Content -Path $file.FullName -Raw -ErrorAction Stop

 

        if ($content -match 'Microsoft XPS Document Writer' -or $content -match 'Microsoft Print To PDF') {

            Write-CMLog -Message "Match found in: $($file.FullName)" -Level "INFO"

 

            # Copy INF file to C:\Temp\BlockedDrivers

            $destInf = Join-Path -Path "C:\Temp\BlockedDrivers" -ChildPath $file.Name

            Copy-Item -Path $file.FullName -Destination $destInf -Force

            Write-CMLog -Message "Copied INF to: $destInf" -Level "INFO"

 

            # Delete INF file

            Remove-Item -Path $file.FullName -Force

            Write-CMLog -Message "Deleted INF: $($file.FullName)" -Level "INFO"

 

            # Also handle PNF file

            $pnfPath = [System.IO.Path]::ChangeExtension($file.FullName, ".pnf")

            if (Test-Path $pnfPath) {

                $destPnf = Join-Path -Path "C:\Temp\BlockedDrivers" -ChildPath ([System.IO.Path]::GetFileName($pnfPath))

                Copy-Item -Path $pnfPath -Destination $destPnf -Force

                Write-CMLog -Message "Copied PNF to: $destPnf" -Level "INFO"

 

                Remove-Item -Path $pnfPath -Force

                Write-CMLog -Message "Deleted PNF: $pnfPath" -Level "INFO"

            }

        }

    } catch {

        Write-CMLog -Message "Error processing $($file.FullName): $_" -Level "ERROR"

    }

}