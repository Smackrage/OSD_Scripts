<#
.SYNOPSIS
Post-build validation with Teams notification.

.NOTES
Author: Martin Smith (Data #3)
#>

# --- Logging Setup ---
$LogFile = "C:\Windows\CCM\Logs\PostBuildValidation.log"

# Function to write a message to the log file with a timestamp
function Write-LogFile {
    param([string]$Message)
    # Get the current date and time in the format yyyy-MM-dd HH:mm:ss.fff
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    # Append the timestamped message to the log file specified by $LogFile
    Add-Content -Path $LogFile -Value "$timestamp`t$Message"
}

# Function to log a message to both the output console and the log file
function Write-Log {
    param([string]$Message, [string]$Component = "PostBuildCheck")
    # Get the current time in the format HH:mm:ss.fff
    $timestamp = Get-Date -Format "HH:mm:ss.fff"
    # Construct a log message that includes timestamp, process ID, component, and the message
    $log = "$timestamp $($PID) [$Component] $Message"
    # Output the log message to the console
    Write-Output $log
    # Write the log message to the log file using Write-LogFile
    Write-LogFile $log
}

# Function to write a log entry in Configuration Manager log format
function Write-CMLog {
    param([string]$Message, [string]$Component = "CheckUpdates", [string]$Severity = "1")
    # Get the current time and date in specific formats for logging
    $Time = Get-Date -Format "HH:mm:ss.fff"
    $Date = Get-Date -Format "MM-dd-yyyy"
    # Construct a CM log entry using message, time, date, and other details
    $line = "<![LOG[$Message]LOG]!><time=`"$Time`" date=`"$Date`" component=`"$Component`" context=`"`" type=`"$Severity`" thread=`"`" file=`"`">"
    # Output the CM log entry to the console
    Write-Output $line
    # Write the CM log entry to the log file using Write-LogFile
    Write-LogFile $line
}

# --- Detect TS or Full OS ---
# Determine if the script is running within a Task Sequence environment
$RunningInTS = $false
# Attempt to create a COM object for the Task Sequence environment
try {
    $tsenv = New-Object -COMObject Microsoft.SMS.TSEnvironment -ErrorAction Stop
    # If successful, set the running in Task Sequence flag to true
    $RunningInTS = $true
    Write-Log "Detected Task Sequence environment."
} catch {
    # If failure occurs, log the environment type as full OS mode
    Write-Log "No TS environment detected. Running in full OS mode."
    # Use the current date minus 25 minutes as a fake OSD start time
    $tsenv = @{ "OSDStartTime" = (Get-Date).AddMinutes(-25).ToString("G") }
}

# Function to check if a given application is installed on the system
function Test-AppInstalled {
    param ([string]$DisplayName)
    # Define registry paths where installed applications can be found
    $paths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    # Iterate over each registry path
    foreach ($path in $paths) {
        # Check if the application with the given display name is listed
        if (Get-ItemProperty -Path $path -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*$DisplayName*" }) {
            # Return true if the application is found
            return $true
        }
    }
    # Return false if the application is not found in any registry path
    return $false
}
# Function to retrieve the Active Directory site of the computer
function Get-ComputerSite {
    try {
        # Attempt to get the domain of the computer using Active Directory
        $domain = [System.DirectoryServices.ActiveDirectory.Domain]::GetComputerDomain()
        # Return the domain name if successful
        return $domain.Name
    } catch {
        # If an error occurs, return "Unknown" as the site name
        return "Unknown"
    }
}

# --- System Info ---
# Store the current date and time
$Now = Get-Date

# Retrieve the system's name using WMI
$Name = (Get-WmiObject Win32_ComputerSystem).Name

# Retrieve the BIOS manufacturer using WMI
$Make = (Get-WmiObject Win32_BIOS).Manufacturer

# Retrieve the system's model using WMI
$Model = (Get-WmiObject Win32_ComputerSystem).Model

# Retrieve the system's BIOS serial number using WMI
$Serial = (Get-WmiObject Win32_BIOS).SerialNumber

# Retrieve the first non-null IP address of the system's network adapter
$IP = (Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object { $_.IPAddress -ne $null }).IPAddress | Select-Object -First 1

# Retrieve the name of the taks sequence currently running.
$TSName =  $tsenv.Value("_SMSTSPackageName")

# Determine the OSD start time based on the environment (Task Sequence or Full OS)
$OSDStart = if ($RunningInTS) { $tsenv.Value("OSDStartTime") } else { $tsenv["OSDStartTime"] }

# Convert the current date to a formatted string
$FinishTime = $Now.ToString("g")

# Calculate the duration of the build process
$Duration = "{0:hh}:{0:mm}:{0:ss}" -f (New-TimeSpan -Start $OSDStart -End $Now)

# Retrieve the Active Directory site of the computer
$ADSite = Get-ComputerSite

# --- VPN Check Logic ---
# Retrieve the chassis types of the system's enclosure using WMI
$chassis = Get-WmiObject Win32_SystemEnclosure | Select-Object -ExpandProperty ChassisTypes -ErrorAction SilentlyContinue

# Initialize a flag to indicate if VPN check is required
$vpnCheckRequired = $false

# Loop through each chassis type to determine if a VPN check is required
foreach ($type in $chassis) {
    # Check if the current chassis type is one that requires a VPN check
    if ($type -in @("8","9","10","11","12","14","18","21","30","31","32")) {
        # Set the flag to true if a matching chassis type is found
        $vpnCheckRequired = $true
        break
    }
}

# Log the identified chassis types
Write-Log "Chassis type(s): $($chassis -join ', ')"

# Log whether a VPN check is required
Write-Log "VPN Check Required: $vpnCheckRequired"

# --- Validation ---
# Initialize an array to hold validation results
$results = @()

# Flag to indicate if any checks have failed
$fail = $false

# Define a set of validation checks to perform
$checks = @(
    @{ Name = "CrowdStrike Falcon"; Test = { Test-AppInstalled "CrowdStrike" } },
    @{ Name = "M365 Apps"; Test = { Test-AppInstalled "Microsoft 365" } },
    @{ Name = "Citrix Workspace"; Test = { Test-AppInstalled "Citrix Workspace" } },
    @{ Name = "Latest Windows Updates"; Test = { Test-WindowsUpdated } }
)

# If a VPN check is required, add it to the list of checks
if ($vpnCheckRequired) {
    $checks += @{ Name = "VPN Client"; Test = { Test-AppInstalled "Cisco Secure Client - AnyConnect VPN" } }
}

# Execute each validation check
foreach ($check in $checks) {
    # Run the test function associated with the check and capture the status
    $status = & $check.Test
    # Determine the result symbol based on the status
    $symbol = if ($status) { "[OK]" } else { "[X]" }
    # If a check fails, set the fail flag to true
    if (-not $status) { $fail = $true }
    # Add the result to the results array
    $results += "$symbol $($check.Name)"
    # Log the result of the check
    Write-Log "$($check.Name): $symbol"
}
# --- Teams Webhook Info ---
# --- Teams Webhook Info ---
# Determine the Teams webhook details based on the build's success or failure
if ($fail) {
    # If a failure was detected during validation
    # Set the webhook URL for failure notifications
    $webhookUri = 'https://COMPANYNAME.webhook.office.com/webhookb2/42c0a175-845f-4600-a9d4-ae95d881d3b8@0f289d43-bbef-4446-9cec-57d0419a15c2/IncomingWebhook/2966bf057f694df6a68435cf82026c34/d176b296-b098-44ad-8053-2d61c7625bdb/V2pZs--yTd0OiSsCC35krwGg8l2TQGQSpUqnyqchTKgmA1'
    # Set the Teams notification card title to indicate a failed build
    $cardTitle = "**[X] Build Failed [X]**"
    # Set the card theme color to red to indicate an error
    $theme = "FF0000"
    # Set the log link path for failure logs
    $LogLink = "\\\\CompanyName.internal\\applications$\\SCCMRepo$\\TaskSequenceLogs\\Failure\\$Name"
} else {
    # If no failure was detected
    # Set the webhook URL for success notifications
    $webhookUri = 'https://COMPANYNAME.webhook.office.com/webhookb2/42c0a175-845f-4600-a9d4-ae95d881d3b8@0f289d43-bbef-4446-9cec-57d0419a15c2/IncomingWebhook/2cfdbd959f7044d0a2af95cd30c2564b/d176b296-b098-44ad-8053-2d61c7625bdb/V2ZuNxa2N-Xrkrsirit5a4j0RDU3WAs1oml4MdGPzl0ZQ1'
    # Set the Teams notification card title to indicate a successful build
    $cardTitle = "**[OK] Build Successful [OK]**"
    # Set the card theme color to green to indicate success
    $theme = "00C853"
    # Set the log link path for success logs
    $LogLink = "\\\\CompanyName.internal\\applications$\\SCCMRepo$\\TaskSequenceLogs\\Success\\$Name"
}

# --- Format Facts ---
# Prepare an array to hold formatted validation facts for the Teams notification
$validationFactsArray = @()
# Iterate through each result line from the validation checks
foreach ($line in $results) {
    # Split each result line into a symbol and a fact name using space as a delimiter, allowing a maximum of two parts
    $split = $line -split ' ', 2
    # Add the split results to the facts array with 'name' and 'value' keys
    $validationFactsArray += @{
        name  = $split[1]  # The name of the validation check
        value = $split[0]  # The result symbol of the validation check (e.g., [OK] or [X])
    }
}


# Create an array of system facts to be included in the Teams notification
$systemFactsArray = @(
    # Add the name of the computer system
    @{ name = "Name"; value = $Name },

    # Add the name of the task sequence currently
    @{ name = "Task Sequence"; value = $TSName },
    
    # Add the finish time of the build process
    @{ name = "Finished Time"; value = $FinishTime },
    
    # Add the duration of the build process
    @{ name = "Build Duration"; value = $Duration },
    
    # Add the IP address of the system
    @{ name = "IP Address"; value = $IP },
    
    # Add the manufacturer of the system's BIOS
    @{ name = "Make"; value = $Make },
    
    # Add the model of the computer system
    @{ name = "Model"; value = $Model },
    
    # Add the serial number of the BIOS
    @{ name = "Serial Number"; value = $Serial },
    
    # Add the Active Directory site name
    @{ name = "AD Site"; value = $ADSite },
    
    # Add the path to the log file associated with the build
    @{ name = "Log Path"; value = $LogLink }
)


# --- MessageCard Payload ---
# Construct a hashtable to define the message card payload for a Microsoft Teams notification
$payloadObject = @{
    # Specify the type of card being created
    "@type" = "MessageCard"
    # Define the context of the card, required for schema recognition in Teams
    "@context" = "http://schema.org/extensions"
    # Provide a summary of what the message card is about
    summary = "Post-Build Validation"
    # Specify the color theme for the card, indicating the result (e.g., red for failure, green for success)
    themeColor = $theme
    # Define the sections to be included in the card
    sections = @(
        @{
            # Set the title of the activity section of the card
            activityTitle = $cardTitle
            # Add text to the section for validation results
            text = "**Validation Results**"
            # Include the facts array containing validation results
            facts = $validationFactsArray
        },
        @{
            # Add text to the section for system information
            text = "**System Information**"
            # Include the facts array containing system information
            facts = $systemFactsArray
        }
    )
}

# Convert the message card payload from a hashtable to a JSON string
# Specify a conversion depth to handle nested structures and compress output for network transmission
$payload = $payloadObject | ConvertTo-Json -Depth 10 -Compress


# --- Send to Teams ---
# Attempt to send the notification to Microsoft Teams
try {
    # Use the Invoke-RestMethod cmdlet to send an HTTP POST request to the specified webhook URI
    # The payload is sent as the request body in JSON format with the appropriate content type
    Invoke-RestMethod -Method Post -Uri $webhookUri -Body $payload -ContentType 'application/json'
    # Log a message indicating that the notification was successfully sent to Teams
    Write-Log "Notification sent to Teams: $cardTitle"
} catch {
    # Catch any exceptions that occur during the execution of the try block
    # Log an error message indicating failure to send the notification, including the exception message
    Write-Log "[X] Failed to send Teams notification: $_"
}

# --- Exit ---
# Determine the exit status of the script based on the results of the validation checks
if ($fail) {
    # If any validation check failed, log a failure message and exit with a status code of 1
    Write-Log "[X] BUILD FAILED [X]"
    exit 1
} else {
    # If all validation checks were successful, log a success message and exit with a status code of 0
    Write-Log "[OK] BUILD SUCCESSFUL [OK]"
    exit 0
}

