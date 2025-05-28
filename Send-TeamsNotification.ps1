<#
.SYNOPSIS
Sends a Microsoft Teams notification upon successful completion of an OSD task sequence.

.DESCRIPTION
This script gathers key system information and task sequence environment variables 
at the end of an OSD deployment and sends a formatted notification to a specified 
Microsoft Teams webhook URL. The message includes details such as device name, 
deployment finish time, build duration, make/model, serial number, and AD site.

.NOTES
============================================================================
Created on:   06/11/2020 13:07 
Created by:   Martin Smith 
Organisation: Data#3
Modified on:  20/05/2025
============================================================================
#>

# Function to log messages in CMTrace-compatible format
function Write-Log {
    param (
        [string]$Message,
        [string]$LogPath = "$env:WINDIR\Temp\OSD-TeamsNotification.log"
    )
    $TimeStamp = Get-Date -Format "MM-dd-yyyy HH:mm:ss"
    $Line = "$TimeStamp`t$Message"
    Add-Content -Value $Line -Path $LogPath
}

Write-Log "Starting Teams notification script."

# Webhook URI for Microsoft Teams channel
$uri = 'https://virginaustralia.webhook.office.com/webhookb2/42c0a175-845f-4600-a9d4-ae95d881d3b8@0f289d43-bbef-4446-9cec-57d0419a15c2/IncomingWebhook/2cfdbd959f7044d0a2af95cd30c2564b/d176b296-b098-44ad-8053-2d61c7625bdb/V2ZuNxa2N-Xrkrsirit5a4j0RDU3WAs1oml4MdGPzl0ZQ1'

# Collect current date and time
$DateTime = Get-Date -Format g
$Time = Get-Date -Format HH:mm

# Retrieve system information
$Make = (Get-WmiObject -Class Win32_BIOS).Manufacturer
$Model = (Get-WmiObject -Class Win32_ComputerSystem).Model
$Name = (Get-WmiObject -Class Win32_ComputerSystem).Name
[string]$SerialNumber = (Get-WmiObject win32_bios).SerialNumber

# Get first non-null IP address from network adapters
$IPAddress = (Get-WmiObject win32_Networkadapterconfiguration | Where-Object { $_.ipaddress -notlike $null }).IPaddress | Select-Object -First 1

Write-Log "Retrieved system information: $Name - $Make $Model"

# Attempt to read task sequence environment variables
$TSenv = New-Object -COMObject Microsoft.SMS.TSEnvironment -ErrorAction SilentlyContinue
$TSlogPath = $TSenv.Value("_SMSTSLogPath")
$TSErrorCode = $TSenv.Value("_SMSTSLastActionRetCode")

# Capture current time and task sequence start time
$InstallTime = Get-Date -Format G
$OSDStartTime = $TSenv.Value("OSDStartTime")

# Calculate time taken to complete the OSD
$OSDTimeSpan = New-TimeSpan -Start $OSDStartTime -End $InstallTime
$OSDDuration = "{0:hh}:{0:mm}:{0:ss}" -f $OSDTimeSpan

Write-Log "Calculated OSD duration: $OSDDuration"

# Function to get the Active Directory site of the computer
function Get-ComputerSite($ComputerName) {
    $site = nltest /server:$ComputerName /dsgetsite 2>$null
    if ($LASTEXITCODE -eq 0) { $site[0] }
}

$ADSite = Get-ComputerSite $Name
Write-Log "Active Directory site: $ADSite"

# Build the JSON payload for the Teams notification
$body = ConvertTo-Json -Depth 9 @{
    title = "$Name Completed Successfully"
    text  = "Completed Successfully"
    sections = @(
        @{
            activityTitle    = 'Task Sequence'
            activitySubtitle = 'Windows 11 24H2 Production'  # Modify if you're using another deployment type
            activityText     = 'Completed Successfully'
            activityImage    = ''  # Optional: add image path for branding
        },
        @{
            title = '<h2 style=color:blue;>Deployment Details'
            facts = @(
                @{ name = 'Name'; value = $Name },
                @{ name = 'Finished'; value = "$DateTime" },
                @{ name = 'Time'; value = "$Time" },
                @{ name = 'Build Duration'; value = "$OSDDuration" },
                @{ name = 'IP Address'; value = $IPAddress },
                @{ name = 'Make'; value = $Make },
                @{ name = 'Model'; value = $Model },
                @{ name = 'Serial'; value = $SerialNumber },
                @{ name = 'Site'; value = $ADSite }
            )
        }
    )
}

Write-Log "Sending notification to Teams webhook..."

# Send the JSON message to Microsoft Teams via webhook
Invoke-RestMethod -Uri $uri -Method Post -Body $body -ContentType 'application/json'

Write-Log "Notification sent successfully."
