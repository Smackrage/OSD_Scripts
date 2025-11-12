<#
.SYNOPSIS
Ensures correct network priority: Ethernet > Wi-Fi > WWLAN (SIM-based) by setting interface metrics.

.DESCRIPTION
Sets static metrics for network interfaces:
- Ethernet: 5
- Wi-Fi: 30
- WWLAN (Cellular): 50
Includes CMTrace-compatible logging.

.NOTES
Author: Martin Smith (Data #3)
Date: 19/05/2025
Version: 1.1
#>

function Write-Log {
    param (
        [string]$Message,               # The log message to be written.
        [string]$Severity = "INFO"      # Default severity level is INFO unless specified.
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss" # Gets the current timestamp for the log entry.
    Write-Output "$timestamp`t$Severity`t$Message"     # Outputs the log entry with timestamp and severity.
}

try {
    Write-Log "Fetching network adapters..." # Log the action of fetching network adapters information.

    # Retrieve all Ethernet adapters with IPv4 configuration.
    $ethernetAdapters = Get-NetIPInterface | Where-Object { $_.InterfaceAlias -match "Ethernet" -and $_.AddressFamily -eq 'IPv4' }

    # Retrieve all Wi-Fi adapters with IPv4 configuration.
    $wifiAdapters     = Get-NetIPInterface | Where-Object { $_.InterfaceAlias -match "Wi-Fi" -and $_.AddressFamily -eq 'IPv4' }

    # Retrieve all Cellular (WWLAN) adapters with IPv4 configuration.
    $wwlanAdapters    = Get-NetIPInterface | Where-Object { $_.InterfaceAlias -match "Cellular" -and $_.AddressFamily -eq 'IPv4' }

    if ($ethernetAdapters) {
        # Iterate over each Ethernet adapter and set its metric to 5.
        foreach ($adapter in $ethernetAdapters) {
            Write-Log "Setting Ethernet adapter '$($adapter.InterfaceAlias)' metric to 5..."
            Set-NetIPInterface -InterfaceAlias $adapter.InterfaceAlias -InterfaceMetric 5
        }
    } else {
        Write-Log "No Ethernet adapters found." "WARNING" # Log warning if no Ethernet adapters are found.
    }

    if ($wifiAdapters) {
        # Iterate over each Wi-Fi adapter and set its metric to 30.
        foreach ($adapter in $wifiAdapters) {
            Write-Log "Setting Wi-Fi adapter '$($adapter.InterfaceAlias)' metric to 30..."
            Set-NetIPInterface -InterfaceAlias $adapter.InterfaceAlias -InterfaceMetric 30
        }
    } else {
        Write-Log "No Wi-Fi adapters found." "WARNING" # Log warning if no Wi-Fi adapters are found.
    }

    if ($wwlanAdapters) {
        # Iterate over each WWLAN (Cellular) adapter and set its metric to 50.
        foreach ($adapter in $wwlanAdapters) {
            Write-Log "Setting WWLAN (Cellular) adapter '$($adapter.InterfaceAlias)' metric to 50..."
            Set-NetIPInterface -InterfaceAlias $adapter.InterfaceAlias -InterfaceMetric 50
        }
    } else {
        Write-Log "No WWLAN (Cellular) adapters found." "INFO" # Log informational message if no WWLAN adapters are found.
    }

    Write-Log "Interface priorities updated successfully." # Log successful completion of the task.

} catch {
    Write-Log "An error occurred: $_" "ERROR" # Log any error that occurs during execution.
}
