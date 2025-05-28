<#
.SYNOPSIS
Clears the SCCM client cache, including persistent content, on the local machine.

.DESCRIPTION
This script connects to the local Configuration Manager client cache and removes all items, including those marked as persistent.

.NOTES
Author: ChatGPT (adapted for Australian English)
Date: 29/04/2025
Version: 1.0
#>

# --- Variables ---
$LogFile = "C:\Temp\Clear-SCCMCache.log"

# --- Functions ---
function Write-Log {
    param (
        [string]$Message,
        [string]$Severity = "INFO"
    )
    $Timestamp = Get-Date -Format "HH:mm:ss.fff"
    $Entry = "<$($Severity)>[$(Get-Date -Format 'dd-MM-yyyy') $Timestamp] $Message"
    Add-Content -Path $LogFile -Value $Entry
}

# --- Main Script ---

# Create log folder if it doesn't exist
if (-not (Test-Path -Path (Split-Path -Path $LogFile))) {
    New-Item -Path (Split-Path -Path $LogFile) -ItemType Directory -Force
}

Write-Log "Starting SCCM Cache clearance process."

# Load the CCM object
try {
    $CCMCache = Get-WmiObject -Namespace "root\ccm\softmgmtagent" -Class "CacheConfig"
    if ($null -eq $CCMCache) {
        Write-Log "Unable to load CCM CacheConfig class. Exiting script." "ERROR"
        exit 1
    }
} catch {
    Write-Log "Failed to connect to SCCM WMI namespace: $_" "ERROR"
    exit 1
}

# Get all CacheItems
try {
    $CacheItems = Get-WmiObject -Namespace "root\ccm\softmgmtagent" -Class "CacheInfoEx"
    if ($CacheItems.Count -eq 0) {
        Write-Log "No items found in cache. Nothing to clear."
    } else {
        foreach ($Item in $CacheItems) {
            try {
                Write-Log "Attempting to delete CacheID: $($Item.CacheID) | Persisted: $($Item.Persisted)"

                # Force deletion, even for persistent items
                $Item.Delete()
                Write-Log "Successfully deleted CacheID: $($Item.CacheID)"
            } catch {
                Write-Log "Failed to delete CacheID: $($Item.CacheID) - $_" "ERROR"
            }
        }
    }
} catch {
    Write-Log "Failed to retrieve cache items: $_" "ERROR"
    exit 1
}

Write-Log "SCCM Cache clearance process completed."
