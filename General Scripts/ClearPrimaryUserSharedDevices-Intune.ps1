<#
.SYNOPSIS
Run a Defender Advanced Hunting query via Graph to find devices with ≥ 5 distinct users,
then (optionally) clear their Intune primary users.

.PARAMETER WhatIf
Simulate the run without performing any Graph write actions.

.Example
Safe test (no changes)                     - .\Find-MultiUserDevices.ps1 -WhatIf
Live mode (performs Intune user clears)    - .\Find-MultiUserDevices.ps1      

.NOTES
Author: Martin Smith (Data#3)
Date: 04/11/2025
Version: 1.1
#>

param (
    [switch]$WhatIf
)



#region --- Logging Setup (CMTrace-compatible) ---
function Write-Log {
    param (
        [string]$Message,
        [ValidateSet("1","2","3")] [string]$Severity = "1"  # 1=Info,2=Warning,3=Error
    )

    $time = Get-Date -Format "HH:mm:ss.fff"
    $date = Get-Date -Format "MM-dd-yyyy"
    $component = "Find-MultiUserDevices"
    $logEntry = "<![LOG[$Message]LOG]!><time=""$time"" date=""$date"" component=""$component"" type=""$Severity"" thread=""$PID"" file="""">"

    # Define log file path
    $logPath = "C:\Windows\Temp\Find-MultiUserDevices.log"

    # Write to console
    Write-Output $logEntry

    # Write to log file
    try {
        Add-Content -Path $logPath -Value $logEntry -Encoding UTF8
    } catch {
        Write-Warning "Failed to write to log file: $($_.Exception.Message)"
    }
}

#endregion


#Requires -Modules Microsoft.Graph, Microsoft.Graph.Security, Microsoft.Graph.DeviceManagement
#region --- Ensure Graph Modules Are Present ---
function Install-GraphModules {
    [CmdletBinding()]
    param()

    $modules = @(
        'Microsoft.Graph',
        'Microsoft.Graph.Security',
        'Microsoft.Graph.DeviceManagement'
    )

    foreach ($mod in $modules) {
        $installed = Get-Module -ListAvailable -Name $mod
        if (-not $installed) {
            Write-Log "Module $mod not found — installing..." 2
            try {
                Install-Module $mod -Scope AllUsers -Force -AllowClobber -ErrorAction Stop
                Write-Log "Successfully installed $mod." 1
            } catch {
                Write-Log "Failed to install $mod : $($_.Exception.Message)" 3
                throw
            }
        } else {
            Write-Log "Module $mod already installed." 1
        }
    }
}

Write-Log "Checking for required Graph modules..." 1
Install-GraphModules
#endregion

#region --- Connect to Microsoft Graph ---
Write-Log "Connecting to Microsoft Graph..." 1
Connect-MgGraph -Scopes "SecurityEvents.Read.All","DeviceManagementManagedDevices.ReadWrite.All" -NoWelcome
Select-MgProfile beta
Write-Log "Graph connection established." 1
#endregion

#region --- Defender Advanced Hunting Query ---
$query = @'
DeviceLogonEvents
| where Timestamp > ago(30d)
| where LogonType in ("Interactive", "Unlock", "RemoteInteractive", "CachedInteractive")
| extend normDomain = tolower(coalesce(AccountDomain, "")),
         normName   = tolower(coalesce(AccountName,  ""))
| extend UserKey    = iff(isnotempty(AccountSid), AccountSid, strcat(normDomain, "\\", normName))
| where isnotempty(DeviceId) and isnotempty(DeviceName)
| where DeviceName hasprefix "v1-" or DeviceName hasprefix "vx-"
| where isnotempty(UserKey) and UserKey <> "\\"
| where not(normName endswith "$")
| where normName !startswith "umfd-" and normName !startswith "dwm-" and normName !startswith "svc"
| where normName !in~ ("system","local service","network service","defaultaccount","guest","wdagutilityaccount")
| where normName !contains "-admin" and normName !startswith "ksk"
| distinct DeviceId, DeviceName, UserKey, normDomain, normName
| join kind=leftouter (
    IdentityLogonEvents
    | where Timestamp > ago(30d)
    | where isnotempty(AccountSid)
    | summarize arg_max(Timestamp, *) by AccountSid
    | project AccountSid,
              AADUpn = tolower(coalesce(column_ifexists("AccountUpn",""), column_ifexists("UserPrincipalName","")))
) on $left.UserKey == $right.AccountSid
| extend ResolvedUser = iff(isnotempty(AADUpn), AADUpn, strcat(normDomain, "\\", normName))
| summarize DistinctUsers = dcount(ResolvedUser),
            SampleUsers   = make_set(ResolvedUser, 10)
  by DeviceId, DeviceName
| where DistinctUsers > 5
| order by DistinctUsers desc
'@

Write-Log "Running Advanced Hunting query in Microsoft 365 Defender..." 1
try {
    $result  = Invoke-MgSecurityHuntingQuery -Query $query
    $Devices = $result.Results
    if (-not $Devices) {
        Write-Log "No devices found with ≥5 users in the last 30 days." 2
        return
    }
    Write-Log "Found $($Devices.Count) candidate devices with ≥5 users." 1
} catch {
    Write-Log "Failed to run Defender query: $($_.Exception.Message)" 3
    return
}
#endregion

#region --- Process Each Device (Optionally Modify Intune) ---
foreach ($Device in $Devices) {
    $DeviceName = $Device.DeviceName
    Write-Log "Processing device: $DeviceName" 1

    try {
        $IntuneDevice = Get-MgDeviceManagementManagedDevice -Filter "deviceName eq '$DeviceName'"
        if ($IntuneDevice) {
            $UserCount = ($IntuneDevice.UsersPrincipalNames).Count
            if ($UserCount -gt 0) {
                if ($WhatIf) {
                    Write-Log "[WhatIf] Would clear Primary User for $DeviceName (currently $UserCount user(s))." 2
                } else {
                    Write-Log "Clearing Primary User for $DeviceName..." 1
                    Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$($IntuneDevice.Id)/users/deleteAllDeviceUsers"
                    Write-Log "Cleared Primary User for $DeviceName." 1
                }
            } else {
                Write-Log "$DeviceName has no assigned Primary User; skipping." 1
            }
        } else {
            Write-Log "Device $DeviceName not found in Intune." 2
        }
    } catch {
        Write-Log "Error processing $DeviceName : $($_.Exception.Message)" 3
    }
}
#endregion

Write-Log "Script completed successfully." 1
