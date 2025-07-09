<#
.SYNOPSIS
Performs post-build validation and posts results to Microsoft Teams via M365 Connector.

.DESCRIPTION
Validates Office, Citrix, Falcon and update status, logs to file, skips VPN check on non-laptops, and posts a MessageCard with UNC log link.

.NOTES
Author: Martin Smith (COMPANYNAME)
Date: 03/06/2025
Version: 2.4
#>

# --- Logging Setup ---
$LogFile = "C:\Windows\CCM\Logs\PostBuildValidation.log"
function Write-LogFile {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    Add-Content -Path $LogFile -Value "$timestampt$Message"
}

function Write-Log {
    param([string]$Message, [string]$Component = "PostBuildCheck")
    $timestamp = Get-Date -Format "HH:mm:ss.fff"
    $log = "$timestamp $($PID) [$Component] $Message"
    Write-Output $log
    Write-LogFile $log
}

# Logging Function (CMTrace-Compatible)
function Write-Log {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "<![LOG[$Message]LOG]!><time=""$Timestamp"" date=""$(Get-Date -Format 'yyyy-MM-dd')"" component=""Update-ADComputerDescription"" context="" "" type=""$Level"" thread="" "" file="""" />"
    Add-Content -Path $LogFile -Value $LogMessage
    Write-Output $Message
}

# --- Detect TS or Full OS ---
$RunningInTS = $false
try {
    $tsenv = New-Object -COMObject Microsoft.SMS.TSEnvironment -ErrorAction Stop
    $RunningInTS = $true
    Write-Log "Detected Task Sequence environment."
} catch {
    Write-Log "No TS environment detected. Running in full OS mode."
    $tsenv = @{ "OSDStartTime" = (Get-Date).AddMinutes(-25).ToString("G") }
}

# --- Check 'skipAppChecks' TS Variable ---                    # Changed: new block inserted
Write-log Detect SkipAppChecks Variable
if ($RunningInTS) {
    try {
        $skipAppChecksRaw = $tsenv.Value("skipAppChecks")
        Write-Log "Detected TS variable 'skipAppChecks' with value: $skipAppChecksRaw"
        $skipAppChecks = [bool]::Parse($skipAppChecksRaw)
    } catch {
        Write-Log "TS variable 'skipAppChecks' not present or unreadable. Defaulting to: $false."
        $skipAppChecks = $false
    }
} else {
    $skipAppChecks = $false
}

function Test-AppInstalled {
    param ([string]$DisplayName)
    $paths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    foreach ($path in $paths) {
        if (Get-ItemProperty -Path $path -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*$DisplayName*" }) {
            return $true
        }
    }
    return $false
}

function Test-WindowsUpdated {
    Write-CMLog "Starting Windows Update check..."
    try {
        $service = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
        if ($service.Status -ne 'Running') {
            Write-CMLog "Starting Windows Update service..." "CheckUpdates" 2
            Start-Service -Name wuauserv
        }
        $updateSession = New-Object -ComObject Microsoft.Update.Session
        $updateSearcher = $updateSession.CreateUpdateSearcher()
        $searchResult = $updateSearcher.Search("IsInstalled=0 and Type='Software'")
        if ($searchResult.Updates.Count -eq 0) {
            Write-CMLog "No missing updates found." "CheckUpdates" 1
            return $true
        } else {
            Write-CMLog "$($searchResult.Updates.Count) update(s) missing:" "CheckUpdates" 2
            foreach ($u in $searchResult.Updates) {
                $kb = ($u.KBArticleIDs -join ', ') -replace '^$', 'N/A'
                Write-CMLog " - $($u.Title) (KB: $kb)" "CheckUpdates"
            }
            return $false
        }
    } catch {
        Write-CMLog "Update check error: $($_.Exception.Message)" "CheckUpdates" 3
        return $false
    }
}

Function Get-ComputerSite($ComputerName) {
    $site = nltest /server:$Env:ComputerName /dsgetsite 2>$null
    if ($LASTEXITCODE -eq 0) { return $site[0] }
    else { return "Unknown" }
}

function Test-ComputerGroupMembership {
    param (
        [string]$GroupName = "ComputerGroup - Certificate Policy (Desktops_Laptops)"
    )
    try {
        Add-Type -AssemblyName System.DirectoryServices.AccountManagement
        $ctxt = New-Object System.DirectoryServices.AccountManagement.PrincipalContext('Domain')
        $computer = [System.DirectoryServices.AccountManagement.ComputerPrincipal]::FindByIdentity($ctxt, $env:COMPUTERNAME)
        if ($computer -ne $null) {
            $groups = $computer.GetGroups()
            foreach ($group in $groups) {
                if ($group.Name -eq $GroupName) {
                    Write-Log "Computer is a member of AD group: '$GroupName'"
                    return $true
                }
            }
            return $false
            Write-Log "Computer is NOT a member of AD group: '$GroupName'"
        } else {
            Write-Log "Unable to resolve computer object in AD."
        }
    } catch {
        Write-Log "Error checking AD group membership: $($_.Exception.Message)"
    }
    return $false
}



# --- System Info ---
$Now = Get-Date
$Name = (Get-WmiObject Win32_ComputerSystem).Name
$Make = (Get-WmiObject Win32_BIOS).Manufacturer
$Model = (Get-WmiObject Win32_ComputerSystem).Model
$Serial = (Get-WmiObject Win32_BIOS).SerialNumber
$IP = (Get-WmiObject Win32_NetworkAdapterConfiguration | Where-object { $_.IPAddress -ne $null }).IPAddress | Select-Object -First 1
$TSName =  $tsenv.Value("_SMSTSPackageName")
$DeployType = $tsenv.Value("DeploymentType")
$OSDStart = if ($RunningInTS) { $tsenv.Value("OSDStartTime") } else { $tsenv["OSDStartTime"] }
$FinishTime = $Now.ToString("g")
$Duration = "{0:hh}:{0:mm}:{0:ss}" -f (New-TimeSpan -Start $OSDStart -End $Now)
$ADSite = Get-ComputerSite


# --- VPN Check Logic ---
$chassis = Get-WmiObject Win32_SystemEnclosure | Select-Object -ExpandProperty ChassisTypes -ErrorAction SilentlyContinue
$vpnCheckRequired = $false
$vpnChassisTypes = @(8, 9, 10, 11, 12, 14, 18, 21, 30, 31, 32)

foreach ($type in $chassis) {
    if ($vpnChassisTypes -contains $type) {
        $vpnCheckRequired = $true
        break
    }
}
Write-Log "Chassis type(s): $($chassis -join ', ')"
Write-Log "VPN Check Required: $vpnCheckRequired"

# --- Validation ---
$results = @()
$fail = $false
$checks = @(
    @{ Name = "CrowdStrike Falcon"; Test = { Test-AppInstalled "CrowdStrike" } },
    @{ Name = "Citrix Workspace"; Test = { Test-AppInstalled "Citrix Workspace" } },
    @{ Name = "Latest Windows Updates"; Test = { Test-WindowsUpdated } },
    @{ Name = "Added to Certificate Policy AD Group"; Test = { Test-ComputerGroupMembership } }
)
if ($vpnCheckRequired) {
    $checks += @{ Name = "Cisco Secure Client"; Test = { Test-AppInstalled "Cisco Secure Client - AnyConnect VPN" } }
}

foreach ($check in $checks) {
    $status = & $check.Test
    $symbol = if ($status) { "[OK]" } else { "[X]" }

    # Changed: new failure logic that honours skipAppChecks
    if (-not $status) {
        # Only fail on Windows Updates, or on app checks when skipAppChecks is FALSE
        if ($check.Name -eq "Latest Windows Updates" -or -not $skipAppChecks) {
            $fail = $true
        }
    }


    $results += "$symbol $($check.Name)"
    Write-Log "$($check.Name): $symbol"
}

# --- Check 'FailedSuccess' TS Variable Override ---
if ($RunningInTS) {
    try {
        $failedSuccessRaw = $tsenv.Value("FailedSuccess")
        Write-Log "Detected TS variable 'FailedSuccess' with value: $failedSuccessRaw"

        if ($failedSuccessRaw -eq 'false') {
            Write-Log "Override detected: build marked as failed by TS variable 'FailedSuccess'."
            $fail = $true
        } elseif ($failedSuccessRaw -eq 'true') {
            Write-Log "TS variable 'FailedSuccess' indicates success. Forcing build success."
            $fail = $false
        } else {
            Write-Log "TS variable 'FailedSuccess' is set to an unrecognised value. Ignoring override."
        }
    } catch {
        Write-Log "TS variable 'FailedSuccess' not present or unreadable. No override applied."
    }
}

write-log "The variable 'fail' is set to $fail"

# --- Teams Webhook Info ---
if ($fail) {
    $webhookUri = 'https://COMPANYNAME.webhook.office.com/webhookb2/42c0a175-845f-4600-a9d4-ae95d881d3b8@0f289d43-bbef-4446-9cec-57d0419a15c2/IncomingWebhook/2966bf057f694df6a68435cf82026c34/d176b296-b098-44ad-8053-2d61c7625bdb/V2pZs--yTd0OiSsCC35krwGg8l2TQGQSpUqnyqchTKgmA1'
    $cardTitle = "**[X] Build Failed - $name [X]**"
    $theme = "FF0000"
    $LogLink = "\\\\COMPANYNAME.internal\\applications$\\SCCMRepo$\\TaskSequenceLogs\\Failure\\$Name"
} else {
   $webhookUri = 'https://COMPANYNAME.webhook.office.com/webhookb2/42c0a175-845f-4600-a9d4-ae95d881d3b8@0f289d43-bbef-4446-9cec-57d0419a15c2/IncomingWebhook/2cfdbd959f7044d0a2af95cd30c2564b/d176b296-b098-44ad-8053-2d61c7625bdb/V2ZuNxa2N-Xrkrsirit5a4j0RDU3WAs1oml4MdGPzl0ZQ1'
    $cardTitle = "**[OK] Build Successful - $name [OK]**"
    $theme = "00C853"
    $LogLink = "\\\\COMPANYNAME.internal\\applications$\\SCCMRepo$\\TaskSequenceLogs\\Success\\$Name"
}

# --- Format Facts ---
$validationFactsArray = @()
foreach ($line in $results) {
    $split = $line -split ' ', 2
    $validationFactsArray += @{
        name  = $split[1]
        value = $split[0]
    }
}

$systemFactsArray = @(
    @{ name = "Name"; value = $Name },
    @{ name = "Task Sequence"; value = $TSName },
    @{ name = "Deployment Type"; value = $DeployType },
    @{ name = "Finished Time"; value = $FinishTime },
    @{ name = "Build Duration"; value = $Duration },
    @{ name = "IP Address"; value = $IP },
    @{ name = "Make"; value = $Make },
    @{ name = "Model"; value = $Model },
    @{ name = "Serial Number"; value = $Serial },
    @{ name = "AD Site"; value = $ADSite },
    @{ name = "Log Path"; value = $LogLink }
)

# --- MessageCard Payload ---
$payloadObject = @{
    "@type"    = "MessageCard"
    "@context" = "http://schema.org/extensions"
    summary    = "Post-Build Validation"
    themeColor = $theme
    sections   = @(
        @{
            activityTitle = $cardTitle
            text          = "**Validation Results**"
            facts         = $validationFactsArray
        },
        @{
            text  = "**System Information**"
            facts = $systemFactsArray
        }
    )
}
$payload = $payloadObject | ConvertTo-Json -Depth 10 -Compress

# --- Send to Teams ---
try {
    Invoke-RestMethod -Method Post -Uri $webhookUri -Body $payload -ContentType 'application/json'
    Write-Log "Notification sent to Teams: $cardTitle"
} catch {
    Write-Log "[X] Failed to send Teams notification: $_"
}

<# # --- Exit ---
if ($fail) {
    Write-Log "[X] BUILD FAILED [X]"
    exit 1
} else {
    Write-Log "[OK] BUILD SUCCESSFUL [OK]"
    exit 0
}
 #>
