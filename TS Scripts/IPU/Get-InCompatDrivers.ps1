<#
.SYNOPSIS
Scans CompatData XML files for blocked driver packages and copies associated INF files to a network share.

.DESCRIPTION
This script looks through all CompatData_*.xml files in a specified directory, identifies driver packages with BlockMigration="True", outputs the corresponding INF file names, and copies these INF files to a designated network share.

.NOTES
Author: Martin Smith (Data #3)
Date: 22/05/2025
Version: 1.2
#>

# Define source and target paths
$sourcePath = "$env:SYSTEMDRIVE\$WINDOWS.~BT\Sources\Panther"
$networkShareBasePath = "L:\failure\%OSComputername%"
# Adjust this path as needed
$logFilePath = "C:\windows\CCM\Logs\CompatScanDriver.log"  

# Function to log messages in CMTrace-compatible format
function Write-Log {
    param (
        [string]$Message,
        [string]$Component = "CompatScan"
    )
    $timestamp = Get-Date -Format "MM-dd-yyyy HH:mm:ss.fff"
    $logEntry = "$timestamp,$Component,$Message"
    
    # Write log entry to the console
    Write-Output $logEntry
    
    # Append log entry to the log file
    Add-Content -Path $logFilePath -Value $logEntry
}

# Retrieve all XML files matching the pattern 'CompatData_*.xml' in the source directory
$xmlFiles = Get-ChildItem -Path $sourcePath -Filter "CompatData_*.xml" -File

# Iterate over each XML file found
foreach ($file in $xmlFiles) {
    try {
        Write-Log "Processing file: $($file.Name)"

        [xml]$xmlContent = Get-Content -Path $file.FullName

        # Create a namespace manager to handle XML namespaces
        $nsmgr = New-Object System.Xml.XmlNamespaceManager($xmlContent.NameTable)
        $nsmgr.AddNamespace("ns", "http://www.microsoft.com/ApplicationExperience/UpgradeAdvisor/01012009")

        # Select nodes corresponding to driver packages with BlockMigration attribute set to "True"
        $blockedDrivers = $xmlContent.SelectNodes("//ns:DriverPackage[@BlockMigration='True']", $nsmgr)

        foreach ($driver in $blockedDrivers) {
            $inf = $driver.GetAttribute("Inf")
            Write-Log "Blocked driver found: $inf in file: $($file.Name)"

            $infFilePath = Join-Path -Path $sourcePath -ChildPath $inf

            if (Test-Path -Path $infFilePath) {
                # Construct the target path using %OSDComputerName%
                $osdComputerName = $env:OSDComputerName
                $networkSharePath = Join-Path -Path $networkShareBasePath -ChildPath $osdComputerName
                
                # Ensure the target directory exists
                if (-not (Test-Path -Path $networkSharePath)) {
                    New-Item -ItemType Directory -Path $networkSharePath -Force | Out-Null
                }
                
                Copy-Item -Path $infFilePath -Destination $networkSharePath -Force
                Write-Log "Copied INF file: $inf to network share: $networkSharePath"
            } else {
                Write-Log "INF file not found: $inf at expected location: $infFilePath" "Warning"
            }
        }
    }
    catch {
        Write-Log "Error processing file: $($file.Name) - $_" "Error"
    }
}
