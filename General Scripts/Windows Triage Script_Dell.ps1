<#
.SYNOPSIS
Interactive GUI tool to triage and remediate Windows In-Place Upgrade (IPU) failures.

.DESCRIPTION
Single button to run DISM /RestoreHealth then SFC /scannow (captured to per-run logs and echoed to GUI).
Open Main Log button prefers CMTrace, falls back to Notepad.
Hardened log trailer: safe initialisation, handle checks, and delayed timer start.

.NOTES
Author: Martin Smith (Data #3)
Date: 04/11/2025
Version: 1.6.1
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ===========================
# LOGGING (CMTrace-compatible)
# ===========================
$LogRoot  = "C:\Logs"
$logFile  = Join-Path $LogRoot "WaaS_Triage.log"
if (-not (Test-Path $LogRoot)) { New-Item -Path $LogRoot -ItemType Directory | Out-Null }
New-Item -Path $logFile -ItemType File -Force | Out-Null

function Write-Log {
    param(
        [string]$Message,
        [string]$Component = "WaaS-Triage",
        [ValidateSet("1","2","3")] [string]$Severity = "1"  # 1=Info 2=Warn 3=Error
    )
    $ts = Get-Date -Format "MM-dd-yyyy HH:mm:ss.fff"
    "$ts,$PID,$Component,$Message,$Severity" | Out-File -FilePath $logFile -Append -Encoding utf8
}

function Test-IsAdmin {
    try {
        $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
    } catch { return $false }
}

# =========
# MAIN FORM
# =========
$form = New-Object System.Windows.Forms.Form
$form.Text = "IPU Triage - Service Desk"
$form.Size = New-Object System.Drawing.Size(980, 760)
$form.StartPosition = "CenterScreen"

# Main Results Panel
$outputBox = New-Object System.Windows.Forms.RichTextBox
$outputBox.Size = New-Object System.Drawing.Size(940, 410)
$outputBox.Location = New-Object System.Drawing.Point(10, 10)
$outputBox.ReadOnly = $true
$outputBox.BackColor = "Black"
$outputBox.ForeColor = "White"
$outputBox.Font = "Consolas, 10"
$form.Controls.Add($outputBox)

# Log Trailer Panel (tails WaaS_Triage.log)
$logBox = New-Object System.Windows.Forms.RichTextBox
$logBox.Size = New-Object System.Drawing.Size(940, 150)
$logBox.Location = New-Object System.Drawing.Point(10, 430)
$logBox.ReadOnly = $true
$logBox.BackColor = "DimGray"
$logBox.ForeColor = "White"
$logBox.Font = "Consolas, 9"
$logBox.Text = "Log trailer will update here..."
$logBox.HideSelection = $false
$logBox.DetectUrls   = $false
$form.Controls.Add($logBox)

# Buttons row (top row)
$refreshButton = New-Object System.Windows.Forms.Button
$refreshButton.Text = "Refresh"
$refreshButton.Location = New-Object System.Drawing.Point(10, 600)
$refreshButton.Size = New-Object System.Drawing.Size(120, 30)
$form.Controls.Add($refreshButton)

$cleanupButton = New-Object System.Windows.Forms.Button
$cleanupButton.Text = "Run Software Center Cleanup"
$cleanupButton.Location = New-Object System.Drawing.Point(150, 600)
$cleanupButton.Size = New-Object System.Drawing.Size(210, 30)
$cleanupButton.Enabled = $false
$form.Controls.Add($cleanupButton)

$dcuScanButton = New-Object System.Windows.Forms.Button
$dcuScanButton.Text = "Scan DCU Now"
$dcuScanButton.Location = New-Object System.Drawing.Point(380, 600)
$dcuScanButton.Size = New-Object System.Drawing.Size(160, 30)
$dcuScanButton.Enabled = $false
$form.Controls.Add($dcuScanButton)

$dcuApplyButton = New-Object System.Windows.Forms.Button
$dcuApplyButton.Text = "Apply DCU (Drivers/Firmware/Bios)"
$dcuApplyButton.Location = New-Object System.Drawing.Point(550, 600)
$dcuApplyButton.Size = New-Object System.Drawing.Size(240, 30)
$dcuApplyButton.Enabled = $false
$form.Controls.Add($dcuApplyButton)

$diskCleanupButton = New-Object System.Windows.Forms.Button
$diskCleanupButton.Text = "Run Disk Cleanup"
$diskCleanupButton.Location = New-Object System.Drawing.Point(800, 600)
$diskCleanupButton.Size = New-Object System.Drawing.Size(150, 30)
$form.Controls.Add($diskCleanupButton)

# Tools row (second row)
$healthRepairButton = New-Object System.Windows.Forms.Button
$healthRepairButton.Text = "Run Health Repair (SFC + DISM)"
$healthRepairButton.Location = New-Object System.Drawing.Point(10, 635)
$healthRepairButton.Size = New-Object System.Drawing.Size(260, 30)
$form.Controls.Add($healthRepairButton)

$openLogButton = New-Object System.Windows.Forms.Button
$openLogButton.Text = "Open Log"
$openLogButton.Location = New-Object System.Drawing.Point(280, 635)
$openLogButton.Size = New-Object System.Drawing.Size(160, 30)
$form.Controls.Add($openLogButton)

# Close button (full-width, new bottom row)
$exitButton = New-Object System.Windows.Forms.Button
$exitButton.Text = "Close"
$exitButton.Location = New-Object System.Drawing.Point(10, 690)
$exitButton.Size = New-Object System.Drawing.Size(940, 40)
$form.Controls.Add($exitButton)

# =========
# HELPERS
# =========
function Add-Line {
    param(
        [string]$Text,
        [string]$Color = "White",
        [ValidateSet("1","2","3")] [string]$Severity = "1"
    )
    $outputBox.SelectionColor = [System.Drawing.Color]::$Color
    $outputBox.AppendText("$Text`r`n")
    Write-Log -Message $Text -Severity $Severity
}

function Report-Check {
    param(
        [string]$Name,
        [string]$ValueText,
        [bool]  $Passed,
        [string]$ColorOverride,
        [string]$SeverityOverride  # "1","2","3"
    )
    $status = if ($Passed) { "Passed" } else { "Failed" }
    $colour = if ($ColorOverride) { $ColorOverride } else { if ($Passed) { "LightGreen" } else { "Yellow" } }
    $sev    = if ($SeverityOverride) { $SeverityOverride } else { if ($Passed) { "1" } else { "2" } }
    Add-Line ("CHECK - {0}: {1} - {2}" -f $Name, $ValueText, $status) $colour $sev
}

function Get-BiosReleaseDate {
    $bios = Get-CimInstance -ClassName Win32_BIOS
    $rd = $bios.ReleaseDate
    if ($rd -is [string]) {
        try { return [System.Management.ManagementDateTimeConverter]::ToDateTime($rd) } catch { return $null }
    } else { return $rd }
}

function Find-DCU {
    $candidates = @(
        "C:\Program Files (x86)\Dell\CommandUpdate\dcu-cli.exe",
        "C:\Program Files\Dell\CommandUpdate\dcu-cli.exe"
    )
    foreach ($p in $candidates) { if (Test-Path $p) { return $p } }
    return $null
}

function Get-CMTracePath {
    $candidates = @(
        "C:\Windows\CMTrace.exe",
        "C:\Windows\System32\CMTrace.exe",
        "C:\Windows\CCM\CMTrace.exe",
        "C:\Windows\CCM\CMTrace64.exe"
    )
    foreach ($p in $candidates) { if (Test-Path $p) { return $p } }
    return $null
}

function Get-RegistryValueOrDefault {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Name,
        $Default = 0
    )
    try {
        if (-not (Test-Path $Path)) { return $Default }
        $val = Get-ItemPropertyValue -Path $Path -Name $Name -ErrorAction SilentlyContinue
        if ($null -eq $val) { return $Default } else { return $val }
    } catch { return $Default }
}

# ===========================================
# LOG TRAILER STATE
# ===========================================
$script:isBusyRendering   = $false
$script:lastTrailerText   = ""   # ensure initialised

# ===========================================
# BULLET-PROOF LOG TRAILER FUNCTION
# ===========================================
function Update-LogTrailer {
    try {
        if ($script:isBusyRendering) { return }
        if (-not (Test-Path $logFile)) { return }
        if (-not $logBox.IsHandleCreated) { return }  # wait until handle exists

        $newTail = @()
        try {
            $newTail = Get-Content -Path $logFile -Tail 50 -ReadCount 0 -ErrorAction Stop
            if ($null -eq $newTail) { $newTail = @() }
        } catch {
            # log locked or transient read issue — skip this tick
            return
        }

        $newText = ($newTail -join "`r`n")
        if ($newText -ceq $script:lastTrailerText) { return }

        $script:lastTrailerText = $newText

        $updateAction = {
            $logBox.SuspendLayout()
            $logBox.Clear()
            $logBox.AppendText($script:lastTrailerText)
            $logBox.SelectionStart = $logBox.Text.Length
            $logBox.ScrollToCaret()
            $logBox.ResumeLayout($true)
        }

        if ($logBox.InvokeRequired) {
            [void]$logBox.BeginInvoke([Action]$updateAction)
        } else {
            & $updateAction
        }
    } catch {
        # swallow UI exceptions; next tick will retry
    }
}

# ==========================
# LOG TAIL TIMER (delayed)
# ==========================
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000
$timer.Add_Tick({ Update-LogTrailer })
# IMPORTANT: start the timer only after the form is shown (so controls have handles)
$form.Add_Shown({ 
    $timer.Start()
    Update-LogTrailer
})

# ====================
# DCU RUNNER FUNCTIONS
# ====================
function Invoke-DCU-Scan {
    param([string]$DcuPath)

    $script:isBusyRendering = $true
    try {
        if ($timer) { $timer.Stop() }

        $outLog = Join-Path $LogRoot ("DCU_Scan_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
        Write-Log "Preparing to run DCU Scan via: $DcuPath"
        Write-Log "DCU Scan output log: $outLog"
        Add-Line "Preparing to run DCU Scan via: $DcuPath" "Cyan" "1"
        Add-Line "DCU Scan output log: $outLog" "Cyan" "1"
        $scanArgs = "/scan -updateType=bios,firmware,driver -silent -outputLog=`"$outLog`""
        Add-Line "DCU: Running scan: `"$DcuPath`" $scanArgs" "White" "1"
        try {
            $proc = Start-Process -FilePath $DcuPath -ArgumentList $scanArgs -PassThru -WindowStyle Hidden
            $proc.WaitForExit()
            Add-Line "DCU: /scan completed - ExitCode=$($proc.ExitCode)" ($(if ($proc.ExitCode -eq 0) { "LightGreen" } else { "Yellow" })) ($(if ($proc.ExitCode -eq 0) { "1" } else { "2" }))

            if (Test-Path $outLog) {
                Add-Line "----- DCU SCAN LOG BEGIN ($outLog) -----" "White" "1"
                try { Get-Content -Path $outLog -ErrorAction Stop | ForEach-Object { Add-Line $_ "White" "1" } }
                catch { Add-Line "Failed to read DCU scan log: $($_.Exception.Message)" "Yellow" "2" }
                Add-Line "----- DCU SCAN LOG END -----" "White" "1"
            } else {
                Add-Line "No DCU scan log found at: $outLog" "Yellow" "2"
            }
        } catch {
            Add-Line "DCU: /scan failed - $($_.Exception.Message)" "Yellow" "3"
        }
    } finally {
        if ($timer) { $timer.Start() }
        $script:isBusyRendering = $false
        Update-LogTrailer
    }
}

function Invoke-DCU-Apply {
    param([string]$DcuPath)

    $script:isBusyRendering = $true
    try {
        if ($timer) { $timer.Stop() }

        $outLog = Join-Path $LogRoot ("DCU_Apply_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
        Write-Log "Preparing to run DCU Apply via: $DcuPath"
        Write-Log "DCU Apply output log: $outLog"
        Add-Line "Preparing to run DCU Apply via: $DcuPath" "Cyan" "1"
        Add-Line "DCU Apply output log: $outLog" "Cyan" "1"
        $applyArgs = "/applyUpdates -updateType=bios,firmware,driver -reboot=disable -autoSuspendBitLocker=enable -silent -outputLog=`"$outLog`""
        Add-Line "DCU: Running apply: `"$DcuPath`" $applyArgs" "White" "1"
        try {
            $proc = Start-Process -FilePath $DcuPath -ArgumentList $applyArgs -PassThru -WindowStyle Hidden
            $proc.WaitForExit()
            Add-Line "DCU: /applyUpdates completed - ExitCode=$($proc.ExitCode)" ($(if ($proc.ExitCode -eq 0) { "LightGreen" } else { "Yellow" })) ($(if ($proc.ExitCode -eq 0) { "1" } else { "2" }))

            if (Test-Path $outLog) {
                Add-Line "----- DCU APPLY LOG BEGIN ($outLog) -----" "White" "1"
                try { Get-Content -Path $outLog -ErrorAction Stop | ForEach-Object { Add-Line $_ "White" "1" } }
                catch { Add-Line "Failed to read DCU apply log: $($_.Exception.Message)" "Yellow" "2" }
                Add-Line "----- DCU APPLY LOG END -----" "White" "1"
            } else {
                Add-Line "No DCU apply log found at: $outLog" "Yellow" "2"
            }
        } catch {
            Add-Line "DCU: /applyUpdates failed - $($_.Exception.Message)" "Yellow" "3"
        }
    } finally {
        if ($timer) { $timer.Start() }
        $script:isBusyRendering = $false
        Update-LogTrailer
    }
}

# ===========================
# LONG TOOL / HEALTH REPAIR
# ===========================
function Invoke-LongTool-WithCapture {
    param(
        [Parameter(Mandatory)] [string]$DisplayName,
        [Parameter(Mandatory)] [string]$CommandLine
    )
    if (-not (Test-IsAdmin)) {
        Add-Line "$DisplayName requires administrative rights. Please run PowerShell as Administrator." "Yellow" "3"
        return -1
    }

    $safeName = ($DisplayName -replace '[^\w]+','_')
    $outLog = Join-Path $LogRoot ("{0}_{1}.log" -f $safeName,(Get-Date -Format 'yyyyMMdd_HHmmss'))
    Add-Line "$DisplayName : starting..." "Cyan" "1"
    Add-Line "$DisplayName output log: $outLog" "Cyan" "1"
    Write-Log "$DisplayName command: $CommandLine"

    try {
        $proc = Start-Process -FilePath "$env:SystemRoot\System32\cmd.exe" `
                              -ArgumentList "/c $CommandLine > `"$outLog`" 2>&1" `
                              -WindowStyle Hidden -PassThru
        $proc.WaitForExit()
        $code = $proc.ExitCode
        Add-Line "$DisplayName completed - ExitCode=$code" ($(if ($code -eq 0) { "LightGreen" } else { "Yellow" })) ($(if ($code -eq 0) { "1" } else { "2" }))

        if (Test-Path $outLog) {
            Add-Line "----- $DisplayName LOG BEGIN ($outLog) -----" "White" "1"
            try { Get-Content -Path $outLog -ErrorAction Stop | ForEach-Object { Add-Line $_ "White" "1" } }
            catch { Add-Line "Failed to read tool log: $($_.Exception.Message)" "Yellow" "2" }
            Add-Line "----- $DisplayName LOG END -----" "White" "1"
        } else {
            Add-Line "No output log found at: $outLog" "Yellow" "2"
        }
        return $code
    } catch {
        Add-Line "$DisplayName failed - $($_.Exception.Message)" "Yellow" "3"
        return -1
    }
}

function Invoke-HealthRepair {
    $script:isBusyRendering = $true
    try {
        if ($timer) { $timer.Stop() }

        Add-Line "Starting Health Repair sequence (DISM → SFC)..." "Cyan" "1"

        $dismCode = Invoke-LongTool-WithCapture -DisplayName "DISM_RestoreHealth" -CommandLine "dism.exe /Online /Cleanup-Image /RestoreHealth"
        if ($dismCode -eq -1) { return }  # admin or fatal

        $sfcCode  = Invoke-LongTool-WithCapture -DisplayName "SFC_scannow" -CommandLine "sfc.exe /scannow"
        if ($sfcCode -eq -1) { return }

        $summary = @()
        $summary += "DISM exit code: $dismCode"
        $summary += "SFC  exit code: $sfcCode"
        Add-Line ("Health Repair summary -> {0}" -f ($summary -join '; ')) ($(if ($dismCode -eq 0 -and $sfcCode -eq 0) { "LightGreen" } else { "Yellow" })) "1"
    } finally {
        if ($timer) { $timer.Start() }
        $script:isBusyRendering = $false
        Update-LogTrailer
    }
}

# =================
# CORE TRIAGE LOGIC
# =================
$script:dcuPath = $null
function Run-Triage {
    $script:isBusyRendering = $true
    try {
        if ($timer) { $timer.Stop() }

        $outputBox.Clear()
        Add-Line "===== BEGIN Triage Run $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') =====" "White" "1"

        $production = 1
        $wasStuckSoftwareCenter=0; $hadUserFail=0; $rolledbackReason=0
        $secBootEnabled=1; $UEFIEnabled=1
        $biosAgeText="Unknown"; $biosDate=$null
        $diskFreeGB = $null
        $biosDays = $null

        # Failed Task Sequence entries (stuck Software Center)
        $failedTS = Get-WmiObject -Namespace root\ccm\SoftMgmtAgent -Class CCM_TSExecutionRequest -ErrorAction SilentlyContinue |
            Where-Object {
                ($_.State -eq 'Completed'        -and $_.CompletionState -eq 'Failure') -or
                ($_.State -eq 'Running'          -and $_.CompletionState -eq 'Failure') -or
                ($_.State -eq 'WaitingContent'   -and $_.CompletionState -eq 'Failure') -or
                ($_.State -eq 'AdvancedDownload' -and $_.CompletionState -eq 'Failure')
            }
        $failedCount = ($failedTS | Measure-Object).Count
        $wasStuckSoftwareCenter = [int]($failedCount -gt 0)
        Report-Check -Name "Software Center stuck (failed TS)" -ValueText ($(if ($failedCount -eq 0) { "No failed TS" } else { "$failedCount failed TS" })) -Passed:($failedCount -eq 0)
        $cleanupButton.Enabled = ($failedCount -gt 0)

        # Registry UpgradeTSPreFail (tolerant)
        $regPath = "HKLM:\SOFTWARE\Virgin Australia\WaaS\24H2"
        $regKey  = "UpgradeTSPreFail"
        $hadUserFail = Get-RegistryValueOrDefault -Path $regPath -Name $regKey -Default 0
        Report-Check -Name "User Fail (UpgradeTSPreFail)" -ValueText "$hadUserFail" -Passed:($hadUserFail -eq 0)

        # Rollback log bugcheck
        $rbLog = "C:\`$WINDOWS.~BT\Sources\Rollback\setupact.log"
        if (Test-Path $rbLog) {
            $bug = Get-Content $rbLog -ErrorAction SilentlyContinue | Select-String "LastCrashDumpInfo: BugcheckCode" | Select-Object -Last 1
            if ($bug -and $bug.Line -match "BugcheckCode (\d+)") { $rolledbackReason = "BugcheckCode $($matches[1])" }
        }
        Report-Check -Name "Rollback Bugcheck" -ValueText ($(if ($rolledbackReason) { $rolledbackReason } else { "None" })) -Passed:($rolledbackReason -eq 0)

        # BIOS Age (Yellow if > 30 days; pass if <= 365 days; show days < 1y)
        $biosDate = Get-BiosReleaseDate
        $biosPassed = $false
        $biosColorOverride = $null
        $biosSeverityOverride = $null
        if ($biosDate) {
            $biosDays = [math]::Round(((Get-Date) - $biosDate).TotalDays,0)
            if ($biosDays -lt 365) { $biosAgeText = "$biosDays days" } else { $biosAgeText = "$([math]::Floor($biosDays/365)) years" }
            $biosPassed = ($biosDays -le 365)
            if ($biosDays -gt 30) { $biosColorOverride = "Yellow"; $biosSeverityOverride = "2" } else { $biosColorOverride = "LightGreen"; $biosSeverityOverride = "1" }
        } else {
            $biosAgeText = "Unknown"
            $biosPassed = $false
            $biosColorOverride = "Yellow"
            $biosSeverityOverride = "2"
        }
        Report-Check -Name "BIOS age (years/days)" -ValueText $biosAgeText -Passed:$biosPassed -ColorOverride:$biosColorOverride -SeverityOverride:$biosSeverityOverride

        # Secure Boot
        try { $secBootEnabled = if (Confirm-SecureBootUEFI) { 1 } else { 0 } } catch { $secBootEnabled=0 }
        Report-Check -Name "Secure Boot enabled" -ValueText ($(if ($secBootEnabled -eq 1) { "Enabled" } else { "Disabled" })) -Passed:($secBootEnabled -eq 1)

        # UEFI mode
        $UEFIEnabled = if ($env:firmware_type -eq "UEFI") { 1 } else { 0 }
        Report-Check -Name "UEFI enabled" -ValueText ($(if ($UEFIEnabled -eq 1) { "UEFI" } else { "Legacy/BIOS" })) -Passed:($UEFIEnabled -eq 1)

        # Disk free space on system drive
        try {
            $sysDrive = ($env:SystemDrive).TrimEnd('\')
            $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$sysDrive'"
            $diskFreeGB = [math]::Round($disk.FreeSpace / 1GB, 1)
            if ($diskFreeGB -le 20) {
                Report-Check -Name "Disk free space ($sysDrive)" -ValueText "$diskFreeGB GB" -Passed:$false -ColorOverride:"Red" -SeverityOverride:"3"
            } elseif ($diskFreeGB -le 40) {
                Report-Check -Name "Disk free space ($sysDrive)" -ValueText "$diskFreeGB GB" -Passed:$true -ColorOverride:"Yellow" -SeverityOverride:"2"
            } else {
                Report-Check -Name "Disk free space ($sysDrive)" -ValueText "$diskFreeGB GB" -Passed:$true -ColorOverride:"LightGreen" -SeverityOverride:"1"
            }
        } catch {
            Report-Check -Name "Disk free space (System)" -ValueText "Unknown ($($_.Exception.Message))" -Passed:$false -ColorOverride:"Yellow" -SeverityOverride:"2"
        }

        # DCU presence
        $script:dcuPath = Find-DCU
        if ($script:dcuPath) {
            Report-Check -Name "Dell Command | Update (CLI)" -ValueText "Found: $script:dcuPath" -Passed:$true -ColorOverride:"LightGreen" -SeverityOverride:"1"
            $dcuScanButton.Enabled  = $true
            $dcuApplyButton.Enabled = $true
        } else {
            Report-Check -Name "Dell Command | Update (CLI)" -ValueText "Not Found" -Passed:$false -ColorOverride:"Yellow" -SeverityOverride:"2"
            $dcuScanButton.Enabled  = $false
            $dcuApplyButton.Enabled = $false
        }

        # ACTIONS
        Add-Line "`nACTIONS:" "White" "1"
        $actions = @()

        if ($hadUserFail -ne 0) {
            if ($hadUserFail -like "*Disk*") { $actions += "Clear Disk Space before retry" }
            $actions += "User should retry due to User Fail"
        } elseif ($rolledbackReason -ne 0) {
            $actions += "Rollback case: One retry allowed. If fails again, replace."
        } elseif ($wasStuckSoftwareCenter) {
            $actions += "User can retry now. Software Center was cleared."
        }

        if ($biosDays -ne $null -and $biosDays -gt 30) {
            $actions += "Update BIOS via Dell Command | Update (BIOS age: $biosDays days)"
        }

        if ($diskFreeGB -ne $null) {
            if ($diskFreeGB -le 20) {
                $actions += "Critical: Free disk space on $sysDrive is $diskFreeGB GB. Run Disk Cleanup and remove large files."
            } elseif ($diskFreeGB -le 40) {
                $actions += "Low disk space on $sysDrive ($diskFreeGB GB). Run Disk Cleanup before retry."
            }
        }

        if ($secBootEnabled -ne 1) { $actions += "Enable Secure Boot before retry" }
        if ($UEFIEnabled -ne 1)   { $actions += "Enable UEFI before retry" }

        if ($actions.Count -eq 0) {
            Add-Line "good to go" "LightGreen" "1"
        } else {
            foreach ($a in $actions) { Add-Line $a "Cyan" "1" }
        }

        Add-Line "`nLog file: $logFile" "White" "1"
        Add-Line "===== END Triage Run =====" "White" "1"
    } finally {
        if ($timer) { $timer.Start() }
        $script:isBusyRendering = $false
        Update-LogTrailer
    }
}

# =========
# HANDLERS
# =========
$refreshButton.Add_Click({ Run-Triage })

$cleanupButton.Add_Click({
    $script:isBusyRendering = $true
    try {
        if ($timer) { $timer.Stop() }

        Add-Line "Attempting Software Center cleanup..." "Cyan" "1"
        try {
            Set-Service -Name ccmexec -StartupType Automatic -ErrorAction SilentlyContinue
            if ((Get-Service ccmexec -ErrorAction SilentlyContinue).Status -ne 'Running') {
                Start-Service ccmexec -ErrorAction SilentlyContinue
                Add-Line "ccmexec service started" "Cyan" "1"
            }
            $failedTS = Get-WmiObject -Namespace root\ccm\SoftMgmtAgent -Class CCM_TSExecutionRequest -ErrorAction SilentlyContinue |
                Where-Object { $_.CompletionState -eq 'Failure' }
            $count=0
            $failedTS | ForEach-Object { $_.Delete(); $count++ }
            Add-Line "Deleted $count failed TS entr$(if($count -eq 1){'y'}else{'ies'})" "Cyan" "1"

            Invoke-WmiMethod -Namespace root\ccm -Class SMS_Client -Name SetClientProvisioningMode -ArgumentList $false -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 30
            Restart-Service -Name ccmexec -Force -ErrorAction SilentlyContinue
            Add-Line "ccmexec service restarted" "Cyan" "1"
            Start-Sleep -Seconds 30
            Invoke-WmiMethod -Namespace "root\ccm" -Class SMS_Client -Name TriggerSchedule -ArgumentList "{00000000-0000-0000-0000-000000000021}" -ErrorAction SilentlyContinue
            Add-Line "Triggered Machine Policy Evaluation" "Cyan" "1"
        } catch {
            Add-Line "Cleanup failed: $($_.Exception.Message)" "Yellow" "3"
        }
    } finally {
        if ($timer) { $timer.Start() }
        $script:isBusyRendering = $false
        Update-LogTrailer
    }
})

$dcuScanButton.Add_Click({
    if (-not $script:dcuPath) { Add-Line "DCU not found; cannot scan." "Yellow" "2"; return }
    Invoke-DCU-Scan -DcuPath $script:dcuPath
})

$dcuApplyButton.Add_Click({
    if (-not $script:dcuPath) { Add-Line "DCU not found; cannot apply updates." "Yellow" "2"; return }
    Invoke-DCU-Apply -DcuPath $script:dcuPath
})

$diskCleanupButton.Add_Click({
    $script:isBusyRendering = $true
    try {
        if ($timer) { $timer.Stop() }
        try {
            $drive = $env:SystemDrive
            Add-Line "Launching Disk Cleanup for $drive..." "Cyan" "1"
            Start-Process -FilePath "$env:SystemRoot\System32\cleanmgr.exe" -ArgumentList "/d $drive" -WindowStyle Normal
        } catch {
            Add-Line "Failed to launch Disk Cleanup: $($_.Exception.Message)" "Yellow" "3"
        }
    } finally {
        if ($timer) { $timer.Start() }
        $script:isBusyRendering = $false
        Update-LogTrailer
    }
})

$healthRepairButton.Add_Click({
    Invoke-HealthRepair
})

$openLogButton.Add_Click({
    try { if ($timer) { $timer.Stop() } } catch {}
    try {
        $cmtrace = Get-CMTracePath
        if ($cmtrace) {
            Add-Line "Opening log in CMTrace: $logFile" "Cyan" "1"
            Start-Process -FilePath $cmtrace -ArgumentList "`"$logFile`""
        } else {
            Add-Line "CMTrace not found; opening in Notepad: $logFile" "Yellow" "2"
            Start-Process -FilePath "$env:SystemRoot\System32\notepad.exe" -ArgumentList "`"$logFile`""
        }
    } catch {
        Add-Line "Failed to open log: $($_.Exception.Message)" "Yellow" "3"
    } finally {
        Start-Sleep -Milliseconds 500
        try { if ($timer) { $timer.Start() } } catch {}
    }
})

# Exit button (full-width)
$exitButton.Add_Click({
    try { if ($timer) { $timer.Stop() } } catch {}
    $form.Close()
})

# =========
# BOOTSTRAP
# =========
Run-Triage
[void]$form.ShowDialog()
