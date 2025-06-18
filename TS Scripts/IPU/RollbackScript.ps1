<#
.SYNOPSIS
Handles post-rollback remediation for Windows Setup failures.

.DESCRIPTION
This script is invoked via the /PostRollback switch to:
- Move the device back to the Windows 10 OU in AD
- Rename the device to VX-XXXXX format
- Reset the MECM client to avoid stuck deployments
- Send a Teams notification reporting the success/failure of each step

Designed to run in low-trust, module-less contexts like recovery or setup rollback.

.NOTES
Author: Martin Smith (Data #3)
Date: 17/06/2025
Version: 2.3
#>

param (
    [switch]$DryRun
)

# ========== Configuration ==========
$ComputerNamePrefix = "VX"
$CMTraceLog = "C:\Windows\Temp\PostRollback.log"

# this uses messages cards, so will need to be updated for adaptive cards in the future
$TeamsWebhookURL = 'https://COMPNAYNANE.webhook.office.com/webhookb2/' # Replace with your actual Teams webhook URL' 

# Credential files (must be pre-generated securely)
$UserFile = "C:\temp\Rollback\domainuser.txt"
$PasswordFile = "C:\Temp\Rollback\domainpw.txt"

# ========== Logging ==========
function Write-Log {
    param([string]$Message, [string]$Type = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $entry = "<$Type> [$timestamp] $Message"
    Write-Output $entry
    Add-Content -Path $CMTraceLog -Value $entry
}

# ========== Status Tracking ==========
$Result = @{
    OU_Move      = "Not attempted"
    Rename       = "Not attempted"
    MECM_Repair  = "Not attempted"
    DeviceName   = $env:COMPUTERNAME
    DryRun       = $DryRun.IsPresent
}

# ========== Get Secure Credentials ==========
function Get-DomainCred {
    try {
        $User = Get-Content $UserFile -ErrorAction Stop
        $Password = Get-Content $PasswordFile -ErrorAction Stop | ConvertTo-SecureString
        return New-Object System.Management.Automation.PSCredential($User, $Password)
    } catch {
        Write-Log "Failed to read or decode credentials: $_" "ERROR"
        return $null
    }
}

# ========== Move to OU via ADSI ==========
function Move-ComputerOU {
    param([PSCredential]$Cred)

    try {
        $ComputerName = $env:COMPUTERNAME
        $Domain = ([ADSI]"").distinguishedName
        $Searcher = New-Object DirectoryServices.DirectorySearcher
        $Searcher.Filter = "(&(objectClass=computer)(name=$ComputerName))"
        $Searcher.SearchRoot = "LDAP://$Domain"
        $Searcher.PropertiesToLoad.Add("distinguishedName") | Out-Null

        $SearchResult = $Searcher.FindOne()
        if (-not $SearchResult) {
            Write-Log "Computer account not found in Active Directory." "ERROR"
            $Result.OU_Move = "Failure"
            return
        }

        $CurrentDN = $SearchResult.Properties["distinguishedName"][0]
        Write-Log "Computer DN: $CurrentDN"

        # Extract OU path
        $OU = ($CurrentDN -split ',')[1..($CurrentDN.Length)] -join ','

        if ($OU -match "Windows11") {
            $TargetOU = $OU -replace "Windows11", "Windows10 20H2"
            Write-Log "Mapped rollback target OU: $TargetOU"
        } else {
            Write-Log "Current OU is not a Windows11 path. Skipping OU move." "INFO"
            $Result.OU_Move = "Skipped"
            return
        }

        if ($DryRun) {
            Write-Log "[DryRun] Would move $ComputerName to $TargetOU"
            $Result.OU_Move = "Success (DryRun)"
            return
        }

        $ADSI = [ADSI]"LDAP://$CurrentDN"
        $ADSI.MoveTo([ADSI]"LDAP://$TargetOU")
        Write-Log "Moved $ComputerName to $TargetOU"
        $Result.OU_Move = "Success"
    } catch {
        Write-Log "Failed to move computer to rollback OU: $_" "ERROR"
        $Result.OU_Move = "Failure"
    }
}


# ========== Rename Computer ==========
function Rename-ComputerToStandard {
    try {
        $Serial = (Get-WmiObject -Class Win32_BIOS).SerialNumber
        $NewName = "$ComputerNamePrefix-$($Serial.Substring($Serial.Length - 5))"

        if ($env:COMPUTERNAME -eq $NewName) {
            Write-Log "Computer name already correct: $NewName"
            $Result.Rename = "Already correct"
        }
        elseif ($DryRun) {
            Write-Log "[DryRun] Would rename computer to $NewName"
            $Result.Rename = "Success (DryRun)"
        } else {
            Rename-Computer -NewName $NewName -Force -PassThru | Out-Null
            Write-Log "Renamed computer to $NewName"
            $Result.Rename = "Success"
        }

        $Result.DeviceName = $NewName
    } catch {
        Write-Log "Failed to rename computer: $_" "ERROR"
        $Result.Rename = "Failure"
    }
}

# ========== Repair MECM Client ==========
function Repair-MECMClient {
    try {
        if ($DryRun) {
            Write-Log "[DryRun] Would repair MECM client"
            $Result.MECM_Repair = "Success (DryRun)"
            return
        }

        Set-Service -StartupType Automatic -Name ccmexec
        Start-Service ccmexec
        Invoke-WmiMethod -Namespace root\CCM -Class SMS_Client -Name SetClientProvisioningMode -ArgumentList $false
        Restart-Service ccmexec

        $c = Get-WmiObject -Namespace root\ccm\SoftMgmtAgent -Class CCM_TSExecutionRequest -Filter "State = 'Completed' And CompletionState = 'Failure'"
        if ($c) {
            $c.Delete()
            Restart-Service ccmexec -Force
            Write-Log "Deleted failed TSExecutionRequest and restarted ccmexec"
        }

        $Result.MECM_Repair = "Success"
    } catch {
        Write-Log "Failed to repair MECM client: $_" "ERROR"
        $Result.MECM_Repair = "Failure"
    }
}

# ========== Send Teams Notification ==========
function Send-RollbackNotification {
    try {
        $Emoji = @{
            Success = "[OK]"
            Failure = "[X]"
            'Not attempted' = "[-]"
            'Success (DryRun)' = "[~]"
            'Already correct' = "[OK]"
        }

        $Facts = @(
            @{ name = "Device Name";   value = $Result.DeviceName },
            @{ name = "OU Move";       value = "$($Emoji[$Result.OU_Move]) $($Result.OU_Move)" },
            @{ name = "Rename";        value = "$($Emoji[$Result.Rename]) $($Result.Rename)" },
            @{ name = "MECM Repair";   value = "$($Emoji[$Result.MECM_Repair]) $($Result.MECM_Repair)" },
            @{ name = "Timestamp";     value = (Get-Date).ToString("g") }
        )

        if ($Result.DryRun) {
            $Facts += @{ name = "Dry Run Mode"; value = "True" }
        }

        $ThemeColour = if ($Result.DryRun) { "0078D7" } else { "FF0000" }

        $Payload = @{
            title = "Rollback Detected"
            text  = "Device **$($Result.DeviceName)** has rolled back to Windows 10."
            themeColor = $ThemeColour
            sections = @(
                @{
                    activityTitle = "[X] Rollback Recovery Summary"
                    facts = $Facts
                }
            )
        }

        Invoke-RestMethod -Uri $TeamsWebhookURL -Method Post -Body (ConvertTo-Json $Payload -Depth 4) -ContentType 'application/json'
        Write-Log "Sent rollback notification to Teams"
    } catch {
        Write-Log "Failed to send Teams notification: $_" "ERROR"
    }
}

# ========== MAIN ==========
Write-Log "===== PostRollback Script Start ====="
if ($DryRun) { Write-Log "[DryRun Mode ENABLED]" }

$Cred = Get-DomainCred
if ($Cred) {
    Move-ComputerOU -Cred $Cred
} else {
    Write-Log "Skipping OU move due to missing credentials" "ERROR"
    $Result.OU_Move = "Failure"
}

Rename-ComputerToStandard
Repair-MECMClient
Send-RollbackNotification
Write-Log "===== PostRollback Script End ====="
