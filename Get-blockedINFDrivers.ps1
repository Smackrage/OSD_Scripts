<#
.SYNOPSIS
    Scans CompatData XML files for blocked driver packages and detects virtual print drivers via INF content.
.DESCRIPTION
    If a virtual printer driver is detected (by content), it sets a registry flag and TS variable. Blocked INF files are logged and optionally copied.
.NOTES
    Author: Updated by ChatGPT for Ewan
    Date: 28/05/2025
    Version: 2.0
#>
 
# Logging function first
function Write-Log {
    param (
        [string]$Message,
        [string]$Component = "CompatScan",
        [ValidateSet("Info", "Warning", "Error", "Debug")]
        [string]$LogLevel = "Info"
    )
 
    $timestamp = Get-Date -Format "MM-dd-yyyy HH:mm:ss.fff"
    $logEntry = "$timestamp,$Component,[$LogLevel] $Message"
 
    Write-Host $logEntry
    Add-Content -Path $logFilePath -Value $logEntry
}
 
# === Configuration ===
$logFilePath = "C:\windows\ccm\Logs\CompatScanDriver.log"
#$pantherPath = "C:\temp\VX-J8N6TG3" 
$pantherPath = "C:\$WINDOWS.~BT\Sources\Panther" 
$sourcePath = "C:\Windows\INF"       # Local fallback path
 
# Determine computer name
$osdComputerName = $env:OSDComputerName
if (-not $osdComputerName) {
    Write-Log "OSDComputerName not found; using COMPUTERNAME fallback." "CompatScan" "Warning"
    $osdComputerName = $env:COMPUTERNAME
}
 
# Start script
Write-Log "CompatScan script started on machine: $env:COMPUTERNAME"
 
# Get XML files
try {
    $xmlFiles = Get-ChildItem -Path $pantherPath -Filter "CompatData_*.xml" | Where-Object { -not $_.PSIsContainer }
    Write-Log "Found $($xmlFiles.Count) CompatData XML files in $pantherPath"
} catch {
    Write-Log "Failed to access source path: $pantherPath - $_" "CompatScan" "Error"
    exit 1
}
 
# Process each file
foreach ($file in $xmlFiles) {
    try {
        Write-Log "Processing file: $($file.FullName)" "CompatScan" "Debug"
 
        [xml]$xmlContent = Get-Content -Path $file.FullName
        $driverPackages = $xmlContent.SelectNodes("//*[local-name()='DriverPackage']")
        Write-Log "Found $($driverPackages.Count) DriverPackage nodes in $($file.Name)"
 
        foreach ($driver in $driverPackages) {
            $inf = $driver.GetAttribute("Inf")
            $blockMigration = $driver.GetAttribute("BlockMigration")
 
            Write-Log "DriverPackage - INF: $inf, BlockMigration: $blockMigration"
 
            # Full path to INF file
            $infFilePath = Join-Path -Path $sourcePath -ChildPath $inf
 
            Write-Log "Checking INF file content at: $infFilePath" "CompatScan" "Debug"
 
            if (Test-Path -Path $infFilePath) {
                try {
                    $infContent = Get-Content -Path $infFilePath -Raw -ErrorAction Stop
 
                    if ($infContent -match "Microsoft XPS Document Writer" -or $infContent -match "Microsoft Print to PDF") {
                        Write-Log "Match found in INF file for virtual printer driver: $inf" "CompatScan" "Warning"
 
                        # Set TS variable if available
                        try {
                            $tsEnv = New-Object -COMObject Microsoft.SMS.TSEnvironment
                            $tsEnv.Value("DriverBlock") = "True"
                            Write-Log "Task sequence variable 'DriverBlock' set to True." "CompatScan" "Info"
                        } catch {
                            Write-Log "Unable to set task sequence variable. Not in task sequence environment? - $_" "CompatScan" "Warning"
                        }
 
                        # Set registry key
                        try {
                            $regPath = "HKLM:\SOFTWARE\Virgin Australia\WaaS\24H2"
                            if (-not (Test-Path $regPath)) {
                                New-Item -Path $regPath -Force | Out-Null
                                Write-Log "Created registry key: $regPath"
                            }
 
                            Set-ItemProperty -Path $regPath -Name "BlockPrintDriver" -Value 1 -Type DWord
                            Set-ItemProperty -Path $regPath -Name "CompatScanStatus" -Value 0 -Type DWord
                            Set-ItemProperty -Path $regPath -Name "ReadinessStatus" -Value 0 -Type DWord
                            Set-ItemProperty -Path $regPath -Name "PreCacheStatus" -Value 0 -Type DWord
                            Write-Log "Registry key 'BlockPrintDriver' set to 1, and CompatScanStatus, ReadinessStatus and PreCacheStatus to 0 the IPU will remove the problem drivers before running the Upgrade " "CompatScan" "Info"
                        } catch {
                            Write-Log "Failed to write registry key: $_" "CompatScan" "Error"
                        }
                    }
                } catch {
                    Write-Log "Error reading INF file $infFilePath - $_" "CompatScan" "Error"
                }
            } else {
                Write-Log "INF file not found at expected location: $infFilePath" "CompatScan" "Warning"
            }
 
            # Optional: copy all BlockMigration=True INF files
            if ($blockMigration -eq "True") {
                # Implement copy logic here if needed
                Write-Log "BlockMigration=True set for $inf, but no copy destination defined in test mode." "CompatScan" "Debug"
            }
        }
 
    } catch {
        Write-Log "Error processing file: $($file.Name) - $_" "CompatScan" "Error"
    }
}
 
Write-Log "CompatScan script completed." "CompatScan" "Info"