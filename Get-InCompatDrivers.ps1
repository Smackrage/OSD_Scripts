<#
.SYNOPSIS
Scans CompatData XML files for blocked driver packages and copies associated INF files to a network share.

.DESCRIPTION
This script looks through all CompatData_*.xml files in the current directory, identifies driver packages with BlockMigration="True", outputs the corresponding INF file names, and copies these INF files to a designated network share.

.NOTES
Author: Martin Smith (Data #3)
Date: 22/05/2025
Version: 1.1
#>

# Network share path where INF files should be copied
$networkSharePath = "\\NetworkShare\CompatDataINF"

# Function to log messages in CMTrace-compatible format
function Write-Log {
    param (
        [string]$Message,           # The message to be logged
        [string]$Component = "CompatScan"  # Component name for context, defaults to "CompatScan"
    )
    # Capture current timestamp in specified format
    $timestamp = Get-Date -Format "MM-dd-yyyy HH:mm:ss.fff"
    # Capture current process identifier
    $pid = $PID
    # Output log message in the required format
    Write-Output "$timestamp,$pid,$Component,$Message"
}

# Retrieve all XML files matching the pattern 'CompatData_*.xml' in the current directory
$xmlFiles = Get-ChildItem -Filter "CompatData_*.xml" -File

# Iterate over each XML file found
foreach ($file in $xmlFiles) {
    try {
        # Log the start of processing for the current file
        Write-Log "Processing file: $($file.Name)"

        # Load the content of the XML file into an XML object
        [xml]$xmlContent = Get-Content -Path $file.FullName

        # Create a namespace manager to handle XML namespaces
        $nsmgr = New-Object System.Xml.XmlNamespaceManager($xmlContent.NameTable)
        # Add the relevant namespace used in the XML files
        $nsmgr.AddNamespace("ns", "http://www.microsoft.com/ApplicationExperience/UpgradeAdvisor/01012009")

        # Select nodes corresponding to driver packages with BlockMigration attribute set to "True"
        $blockedDrivers = $xmlContent.SelectNodes("//ns:DriverPackage[@BlockMigration='True']", $nsmgr)

        # Iterate over each blocked driver package found
        foreach ($driver in $blockedDrivers) {
            # Extract the INF file name attribute
            $inf = $driver.GetAttribute("Inf")

            # Log the discovery of a blocked driver with its INF file name
            Write-Log "Blocked driver found: $inf in file: $($file.Name)"

            # Construct the path to the INF file assuming it's in the same directory as the XML
      UPDATE WITH LOCATION OF DRIVER #      $infFilePath = Join-Path -Path $file.DirectoryName -ChildPath $inf

            # Copy the INF file to the network share
            if (Test-Path -Path $infFilePath) {
                # Ensure the target directory exists
                if (-not (Test-Path -Path $networkSharePath)) {
                    New-Item -ItemType Directory -Path $networkSharePath -Force | Out-Null
                }
                
                # Copy the file and log the action
                Copy-Item -Path $infFilePath -Destination $networkSharePath -Force
                Write-Log "Copied INF file: $inf to network share: $networkSharePath"
            } else {
                Write-Log "INF file not found: $inf at expected location: $infFilePath" "Warning"
            }
        }
    }
    catch {
        # Log any error encountered during file processing
        Write-Log "Error processing file: $($file.Name) - $_" "Error"
    }
}
