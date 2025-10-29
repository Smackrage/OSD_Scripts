<#
.SYNOPSIS
Removes the computer account from all AD groups except 'Domain Computers' and other groups if required.
.DESCRIPTION
Designed to run in a Task Sequence without requiring any external modules, and logs actions in CMTrace-compatible format using _SMSTSLogPath.
.NOTES
Author: Martin Smith (Data #3)
Date: 05/08/2025
Version: 1.2
#>

# Resolve CMTrace-compatible log file path from TS environment
try {
    $tsEnv = New-Object -COMObject Microsoft.SMS.TSEnvironment
    $LogPath = Join-Path $tsEnv.Value("_SMSTSLogPath") "Remove-ComputerGroups.log"
} catch {
    $LogPath = "C:\windows\ccm\logs\Remove-ComputerGroups.log"
}

# Logging function (CMTrace-compatible)
function Write-Log {
    param (
        [string]$Message,
        [ValidateSet("1","2","3")][string]$Severity = "1"  # 1=INFO, 2=WARN, 3=ERROR
    )
    $timestamp = (Get-Date).ToString("HH:mm:ss.fff")
    $entry = "$timestamp`t$Severity`t$Message"
    Add-Content -Path $LogPath -Value $entry
    Write-Host $Message
}

Write-Log "Starting group membership clean-up for computer account..." "1"

# Allowed groups to retain.  Add additional groups as requried
$AllowedGroups = @(
    'Domain Computers',
    'Additional Group'
)

# Get computer name and DN
$ComputerName = "$env:COMPUTERNAME"
$Searcher = New-Object DirectoryServices.DirectorySearcher
$Searcher.Filter = "(&(objectCategory=computer)(sAMAccountName=$ComputerName`$))"

try {
    $Computer = $Searcher.FindOne()
    if (-not $Computer) {
        Write-Log "Computer account not found in AD: $ComputerName" "3"
        exit 0
    }

    $ComputerDN = $Computer.Properties["distinguishedname"][0]
    $GroupMemberships = $Computer.Properties["memberOf"]
    Write-Log "Found $($GroupMemberships.Count) group(s) for $ComputerName" "1"
}
catch {
    Write-Log "Failed to query computer account from AD: $_" "3"
    exit 0
}

foreach ($GroupDN in $GroupMemberships) {
    try {
        # Resolve group name from DN
        $GroupSearcher = New-Object DirectoryServices.DirectorySearcher
        $GroupSearcher.Filter = "(distinguishedName=$GroupDN)"
        $GroupObj = $GroupSearcher.FindOne()

        if (-not $GroupObj) {
            Write-Log "Could not resolve group DN: $GroupDN" "2"
            continue
        }

        $GroupName = $GroupObj.Properties["name"][0]

        if ($AllowedGroups -contains $GroupName) {
            Write-Log "Skipping allowed group: $GroupName" "1"
            continue
        }

        # Remove computer from group
        $Group = [ADSI]"LDAP://$GroupDN"
        $Group.Remove("LDAP://$ComputerDN")
        Write-Log "Removed $ComputerName from group: $GroupName" "1"
    }
    catch {
        Write-Log "Failed to process group: $GroupDN - $_" "3"
    }
}

Write-Log "Group clean-up completed for $ComputerName" "1"
 