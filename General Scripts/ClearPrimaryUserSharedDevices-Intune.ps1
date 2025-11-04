<#
.SYNOPSIS
Run a Defender Advanced Hunting query via Graph to find devices with ≥ 5 distinct users,
then pass those devices into subsequent automation (e.g. Intune primary user clearing).

.NOTES
Author: Martin Smith (Data#3)
Date: 04/11/2025
Version: 1.0
#>

#Requires -Modules Microsoft.Graph, Microsoft.Graph.Security, Microsoft.Graph.DeviceManagement

Install-Module Microsoft.Graph -Scope AllUsers
Install-Module Microsoft.Graph.Security
Install-Module Microsoft.Graph.DeviceManagement


#region --- Logging Setup (CMTrace-compatible) ---
function Write-Log {
    param (
        [string]$Message,
        [ValidateSet("1","2","3")] [string]$Severity = "1"  # 1=Info,2=Warning,3=Error
    )
    $time = Get-Date -Format "HH:mm:ss.fff"
    $date = Get-Date -Format "MM-dd-yyyy"
    $component = "Find-MultiUserDevices"
    $log = "<![LOG[$Message]LOG]!><time=""$time"" date=""$date"" component=""$component"" type=""$Severity"" thread=""$PID"" file="""">"
    Write-Output $log
}
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
    $result = Invoke-MgSecurityHuntingQuery -Query $query
    $Devices = $result.Results
    if (-not $Devices) {
        Write-Log "No devices found with more than 5 users in the last 30 days." 2
        return
    }
    Write-Log "Found $($Devices.Count) candidate devices with ≥5 users." 1
} catch {
    Write-Log "Failed to run Defender Advanced Hunting query: $($_.Exception.Message)" 3
    return
}
#endregion

#region --- Example: Use Devices for Next Steps (Intune) ---
foreach ($Device in $Devices) {
    $DeviceName = $Device.DeviceName
    Write-Log "Processing device: $DeviceName" 1

    try {
        # Example: retrieve the Intune managed device object
        $IntuneDevice = Get-MgDeviceManagementManagedDevice -Filter "deviceName eq '$DeviceName'"

        if ($IntuneDevice) {
            # Example: Clear Primary User (only if one exists)
            $UserCount = ($IntuneDevice.UsersPrincipalNames).Count
            if ($UserCount -gt 0) {
                Write-Log "Clearing Primary User for $DeviceName..." 1
                # This endpoint requires beta profile (which we’ve selected)
                Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$($IntuneDevice.Id)/users/deleteAllDeviceUsers"
                Write-Log "Cleared Primary User for $DeviceName." 1
            } else {
                Write-Log "$DeviceName has no assigned primary user; skipping." 1
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
