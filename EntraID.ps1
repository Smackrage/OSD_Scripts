<#
.SYNOPSIS
  Entra ID device cleanup (WinForms): preview devices older than X days, export CSV, remove devices.

.REQUIREMENTS
  Microsoft.Graph.Authentication
  Microsoft.Graph.Identity.DirectoryManagement

  Baseline connect (per request):
    Connect-MgGraph -Scopes "User.Read.All","Group.ReadWrite.All"

  Device preview query (per request):
    Get-MgDevice -All | Where {$_.ApproximateLastSignInDateTime -le $dt} | select-object -Property ...

.NOTES
  Date: 15/12/2025
#>

#region CMTrace Logging (CMTrace time format fixed)
function Get-LogPath {
    $logDir = 'C:\Windows\CCM\Logs'
    if (-not (Test-Path $logDir)) { $logDir = "$env:WINDIR\Temp" }
    return (Join-Path $logDir 'EntraDeviceCleanup.log')
}

function Write-CMLog {
    param(
        [Parameter(Mandatory)] [string]$Message,
        [ValidateSet('1','2','3')] [string]$Severity = '1', # 1=Info,2=Warning,3=Error
        [string]$Component = 'EntraDeviceCleanup'
    )
    try {
        $logPath = Get-LogPath
        $now = Get-Date

        # CMTrace wants timezone offset appended to time (minutes)
        $offsetMinutes = [int]([System.TimeZoneInfo]::Local.GetUtcOffset($now).TotalMinutes)
        $offsetSign = if ($offsetMinutes -ge 0) { '+' } else { '-' }
        $offsetAbs = [math]::Abs($offsetMinutes)

        $timeString = "{0}{1}{2:000}" -f $now.ToString('HH:mm:ss.fff'), $offsetSign, $offsetAbs
        $dateString = $now.ToString('MM-dd-yyyy')

        $processId = $PID
        $thread    = [System.Threading.Thread]::CurrentThread.ManagedThreadId

        $line = "<![LOG[$Message]LOG]!><time=""$timeString"" date=""$dateString"" component=""$Component"" context=""PID:$processId"" type=""$Severity"" thread=""$thread"" file="""">"
        Add-Content -Path $logPath -Value $line -Encoding UTF8
        Write-Output $Message
    }
    catch {
        Write-Output "Write-CMLog failed: $($_.Exception.Message)"
    }
}

function Invoke-Logged {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [switch]$VerboseToLog
    )

    Write-CMLog "COMMAND START: $Name" '1'
    Write-CMLog "COMMAND TEXT: $($ScriptBlock.ToString())" '1'

    try {
        if ($VerboseToLog) {
            $out = & $ScriptBlock 4>&1
            foreach ($line in $out) {
                if ($null -ne $line -and $line.ToString().Trim().Length -gt 0) {
                    Write-CMLog "OUTPUT: $($line.ToString())" '1'
                }
            }
            Write-CMLog "COMMAND END: $Name (OK)" '1'
            return $out
        } else {
            $result = & $ScriptBlock
            Write-CMLog "COMMAND END: $Name (OK)" '1'
            return $result
        }
    }
    catch {
        Write-CMLog "COMMAND END: $Name (FAILED) $($_.Exception.Message)" '3'
        throw
    }
}
#endregion

#region Ensure STA
if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    Write-CMLog "Not in STA. Relaunching PowerShell in STA..." '2'
    Start-Process -FilePath "powershell.exe" -ArgumentList "-STA -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Wait
    exit
}
#endregion

$VerbosePreference = 'Continue'

#region UI + Helpers
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Test-IsAdmin {
    try {
        $wp = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        return $wp.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Add-UiLog {
    param(
        [Parameter(Mandatory)][string]$Text,
        [ValidateSet('1','2','3')][string]$Severity = '1'
    )

    $line = "[{0}] {1}" -f (Get-Date).ToString("HH:mm:ss"), $Text
    Write-CMLog $Text $Severity

    if ($script:Form -and $script:Form.IsHandleCreated) {
        $script:Form.BeginInvoke([Action]{
            $script:TxtLog.AppendText($line + [Environment]::NewLine)
        }) | Out-Null
    } else {
        $script:UiLogBuffer.Add($line) | Out-Null
    }
}

function Set-Status([string]$text) {
    $script:LblStatus.Text = "Status: $text"
    [System.Windows.Forms.Application]::DoEvents() | Out-Null
}
#endregion

#region Graph prerequisites + connect (per your command)
function Get-MissingGraphModules {
    $required = @(
        'Microsoft.Graph.Authentication',
        'Microsoft.Graph.Identity.DirectoryManagement'
    )
    $missing = @()
    foreach ($m in $required) {
        if (-not (Get-Module -ListAvailable -Name $m)) { $missing += $m }
    }
    return $missing
}

function Import-GraphModules {
    Invoke-Logged -Name "Import Graph modules" -ScriptBlock {
        Import-Module Microsoft.Graph.Authentication -ErrorAction Stop | Out-Null
        Import-Module Microsoft.Graph.Identity.DirectoryManagement -ErrorAction Stop | Out-Null
    } | Out-Null
}

# Baseline scopes as requested
$script:BaseScopes = @("User.Read.All","Group.ReadWrite.All")

function Connect-GraphWithScopes {
    param(
        [Parameter(Mandatory)][string[]]$Scopes
    )

    $scopeText = ($Scopes | Sort-Object -Unique) -join '","'
    $cmdText = 'Connect-MgGraph -Scopes "{0}"' -f $scopeText

    Add-UiLog "Connecting to Graph with scopes: $($Scopes -join ', ')" '1'
    Invoke-Logged -Name "Connect-MgGraph" -VerboseToLog -ScriptBlock ([scriptblock]::Create($cmdText)) | Out-Null
}

function Ensure-GraphConnected {
    param(
        [string[]]$RequiredScopes
    )

    $want = @($script:BaseScopes + $RequiredScopes) | Sort-Object -Unique

    $ctx = $null
    try { $ctx = Get-MgContext -ErrorAction SilentlyContinue } catch {}

    $connected = $ctx -and $ctx.Account -and $ctx.Scopes
    $hasScopes = $false
    if ($connected) {
        $hasScopes = @($want | ForEach-Object { $ctx.Scopes -contains $_ }) -notcontains $false
    }

    if (-not $connected -or -not $hasScopes) {
        Connect-GraphWithScopes -Scopes $want
    } else {
        Add-UiLog "Graph already connected as $($ctx.Account). Scopes OK." '1'
    }
}
#endregion

#region Non-blocking module install (child PowerShell + Timer)
$script:InstallProcess = $null
$script:InstallTimer   = New-Object System.Windows.Forms.Timer
$script:InstallTimer.Interval = 250

$script:InstallTimer.Add_Tick({
    if (-not $script:InstallProcess) { return }

    try {
        while (-not $script:InstallProcess.StandardOutput.EndOfStream) {
            $line = $script:InstallProcess.StandardOutput.ReadLine()
            if ($line) { Add-UiLog "[INSTALL] $line" '1' }
        }
    } catch { Add-UiLog "StdOut read error: $($_.Exception.Message)" '2' }

    try {
        while (-not $script:InstallProcess.StandardError.EndOfStream) {
            $err = $script:InstallProcess.StandardError.ReadLine()
            if ($err) { Add-UiLog "[INSTALL-ERR] $err" '3' }
        }
    } catch { Add-UiLog "StdErr read error: $($_.Exception.Message)" '2' }

    if ($script:InstallProcess.HasExited) {
        $script:InstallTimer.Stop()

        $exitCode = $script:InstallProcess.ExitCode
        $script:InstallProcess.Dispose()
        $script:InstallProcess = $null

        $script:PrgInstall.Style = 'Blocks'

        if ($exitCode -ne 0) {
            Add-UiLog "Module install failed (exit code $exitCode)" '3'
            $script:BtnInstallModules.Enabled = $true
            $script:PrgInstall.Value = 0
            Set-Status "Ready (modules missing)"
            return
        }

        Add-UiLog "Graph module installation completed successfully." '1'
        try {
            Import-GraphModules
            Add-UiLog "Graph modules imported." '1'

            $script:BtnInstallModules.Enabled = $false
            $script:PrgInstall.Value = 100

            $script:BtnPreview.Enabled = $true
            Set-Status "Ready (Graph installed)"
        } catch {
            Add-UiLog "Install succeeded but import failed: $($_.Exception.Message)" '3'
            $script:BtnInstallModules.Enabled = $true
            $script:PrgInstall.Value = 0
            Set-Status "Ready (modules missing)"
        }
    }
})
#endregion

#region Device operations (per your Get-MgDevice pipeline)
function Get-StaleDevicesByPipeline {
    param(
        [Parameter(Mandatory)][datetime]$dt
    )

    # Exactly your requested pipeline + properties
    Invoke-Logged -Name "Get-MgDevice stale device query" -ScriptBlock {
        Get-MgDevice -All |
            Where-Object { $_.ApproximateLastSignInDateTime -le $dt } |
            Select-Object -Property AccountEnabled, DeviceId, OperatingSystem, OperatingSystemVersion, DisplayName, TrustType, ApproximateLastSignInDateTime, Id
    }
}

function Remove-DeviceById {
    param([Parameter(Mandatory)][string]$Id)

    Invoke-Logged -Name "Remove-MgDevice -DeviceId $Id" -VerboseToLog -ScriptBlock {
        Remove-MgDevice -DeviceId $Id -ErrorAction Stop -Verbose
    } | Out-Null
}
#endregion

#region UI Build
$script:UiLogBuffer = New-Object System.Collections.Generic.List[string]

$script:Form = New-Object System.Windows.Forms.Form
$script:Form.Text = "Entra ID Device Cleanup (Stale Devices)"
$script:Form.Width = 1050
$script:Form.Height = 820
$script:Form.StartPosition = "CenterScreen"
$script:Form.TopMost = $true

$lblDays = New-Object System.Windows.Forms.Label
$lblDays.Text = "Devices older than (days):"
$lblDays.AutoSize = $true
$lblDays.Location = New-Object System.Drawing.Point(15, 15)

$numDays = New-Object System.Windows.Forms.NumericUpDown
$numDays.Minimum = 1
$numDays.Maximum = 3650
$numDays.Value = 90
$numDays.Width = 90
$numDays.Location = New-Object System.Drawing.Point(190, 12)

$script:BtnPreview = New-Object System.Windows.Forms.Button
$script:BtnPreview.Text = "Preview / Count"
$script:BtnPreview.Width = 140
$script:BtnPreview.Location = New-Object System.Drawing.Point(300, 10)

$btnExport = New-Object System.Windows.Forms.Button
$btnExport.Text = "Export CSV"
$btnExport.Width = 120
$btnExport.Location = New-Object System.Drawing.Point(450, 10)

$btnRemove = New-Object System.Windows.Forms.Button
$btnRemove.Text = "REMOVE from Entra ID"
$btnRemove.Width = 180
$btnRemove.Location = New-Object System.Drawing.Point(580, 10)

$chkWhatIf = New-Object System.Windows.Forms.CheckBox
$chkWhatIf.Text = "WhatIf (no deletions)"
$chkWhatIf.AutoSize = $true
$chkWhatIf.Checked = $true
$chkWhatIf.Location = New-Object System.Drawing.Point(780, 13)

$script:LblStatus = New-Object System.Windows.Forms.Label
$script:LblStatus.Text = "Status: Ready"
$script:LblStatus.AutoSize = $true
$script:LblStatus.Location = New-Object System.Drawing.Point(15, 45)

$script:BtnInstallModules = New-Object System.Windows.Forms.Button
$script:BtnInstallModules.Text = "Install Graph Modules"
$script:BtnInstallModules.Width = 170
$script:BtnInstallModules.Location = New-Object System.Drawing.Point(300, 42)

$btnElevate = New-Object System.Windows.Forms.Button
$btnElevate.Text = "Restart as Administrator"
$btnElevate.Width = 190
$btnElevate.Location = New-Object System.Drawing.Point(900, 42)

$script:PrgInstall = New-Object System.Windows.Forms.ProgressBar
$script:PrgInstall.Width = 420
$script:PrgInstall.Height = 18
$script:PrgInstall.Location = New-Object System.Drawing.Point(480, 45)
$script:PrgInstall.Minimum = 0
$script:PrgInstall.Maximum = 100
$script:PrgInstall.Value = 0

$grid = New-Object System.Windows.Forms.DataGridView
$grid.Location = New-Object System.Drawing.Point(15, 70)
$grid.Width = 1000
$grid.Height = 500
$grid.ReadOnly = $true
$grid.AllowUserToAddRows = $false
$grid.AllowUserToDeleteRows = $false
$grid.AutoSizeColumnsMode = "Fill"
$grid.SelectionMode = "FullRowSelect"
$grid.MultiSelect = $true

$script:TxtLog = New-Object System.Windows.Forms.TextBox
$script:TxtLog.Multiline = $true
$script:TxtLog.ScrollBars = "Vertical"
$script:TxtLog.ReadOnly = $true
$script:TxtLog.WordWrap = $false
$script:TxtLog.Width = 1000
$script:TxtLog.Height = 200
$script:TxtLog.Location = New-Object System.Drawing.Point(15, 585)

$script:Form.Controls.AddRange(@(
    $lblDays,$numDays,$script:BtnPreview,$btnExport,$btnRemove,$chkWhatIf,
    $script:LblStatus,$script:BtnInstallModules,$script:PrgInstall,$btnElevate,$grid,$script:TxtLog
))

$script:Form.Add_Shown({
    if ($script:UiLogBuffer.Count -gt 0) {
        foreach ($l in $script:UiLogBuffer) { $script:TxtLog.AppendText($l + [Environment]::NewLine) }
        $script:UiLogBuffer.Clear()
    }
})
#endregion

#region Button wiring
$script:PreviewDevices = @()

function Set-ButtonsAfterPreview {
    $btnExport.Enabled = ($script:PreviewDevices.Count -gt 0)
    $btnRemove.Enabled = ($script:PreviewDevices.Count -gt 0)
}

$btnElevate.Add_Click({
    try {
        Add-UiLog "Elevation requested. Relaunching as Administrator..." '2'
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "powershell.exe"
        $psi.Arguments = "-STA -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        $psi.Verb = "runas"
        $psi.UseShellExecute = $true
        [System.Diagnostics.Process]::Start($psi) | Out-Null
        $script:Form.Close()
    } catch {
        Add-UiLog "Elevation cancelled or failed: $($_.Exception.Message)" '2'
    }
})

$script:BtnInstallModules.Add_Click({
    try {
        if ($script:InstallProcess) { Add-UiLog "Install already running..." '2'; return }

        $missing = Get-MissingGraphModules
        if (-not $missing -or $missing.Count -eq 0) {
            Add-UiLog "Graph modules already installed." '1'
            $script:BtnInstallModules.Enabled = $false
            $script:BtnPreview.Enabled = $true
            Set-Status "Ready (Graph already installed)"
            return
        }

        if (-not (Test-IsAdmin)) {
            Add-UiLog "Module install requires elevation. Click 'Restart as Administrator'." '2'
            [System.Windows.Forms.MessageBox]::Show(
                "Installing Graph modules requires administrator privileges.`n`nClick 'Restart as Administrator' and try again.",
                "Elevation required","OK","Warning"
            ) | Out-Null
            return
        }

        Add-UiLog ("Missing modules: " + ($missing -join ", ")) '2'
        Add-UiLog "Starting module install process (non-blocking)..." '1'

        $script:BtnInstallModules.Enabled = $false
        $script:BtnPreview.Enabled = $false
        $btnExport.Enabled = $false
        $btnRemove.Enabled = $false

        $script:PrgInstall.Style = 'Marquee'
        $script:PrgInstall.MarqueeAnimationSpeed = 30
        Set-Status "Installing Graph modules..."

        $modulesCsv = ($missing -join ',')

        $cmd = @"
`$ErrorActionPreference = 'Stop'
`$VerbosePreference = 'Continue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Write-Output "Ensuring NuGet provider..."
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null

Write-Output "Setting PSGallery trust (best effort)..."
try { Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue } catch {}

Write-Output "Installing modules: $modulesCsv"
Install-Module -Name $modulesCsv -Repository PSGallery -Scope AllUsers -Force -AllowClobber -Verbose

Write-Output "Install complete."
"@

        Write-CMLog "COMMAND START: Module install child process" '1'
        Write-CMLog "COMMAND TEXT: $cmd" '1'

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "powershell.exe"
        $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -Command `"& { $cmd }`""
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow  = $true

        $script:InstallProcess = [System.Diagnostics.Process]::Start($psi)
        $script:InstallTimer.Start()
    } catch {
        Add-UiLog "Failed to start install: $($_.Exception.Message)" '3'
        $script:BtnInstallModules.Enabled = $true
        $script:PrgInstall.Style = 'Blocks'
        $script:PrgInstall.Value = 0
        Set-Status "Ready (modules missing)"
    }
})

$script:BtnPreview.Add_Click({
    try {
        Import-GraphModules

        $days = [int]$numDays.Value
        $dt = (Get-Date).AddDays(-1 * $days)  # <- required for your requested pipeline
        Add-UiLog "Preview clicked. Days=$days Cutoff(dt)=$dt" '1'

        # Baseline connect (per request). If device read fails, retry with Device.Read.All.
        try {
            Ensure-GraphConnected -RequiredScopes @()   # baseline only
            $devices = Get-StaleDevicesByPipeline -dt $dt
        } catch {
            Add-UiLog "Device query failed with baseline scopes. Retrying with Device.Read.All..." '2'
            Ensure-GraphConnected -RequiredScopes @("Device.Read.All")
            $devices = Get-StaleDevicesByPipeline -dt $dt
        }

        $script:PreviewDevices = @($devices)

        $grid.DataSource = $script:PreviewDevices
        Add-UiLog "Preview complete. Count=$($script:PreviewDevices.Count)" '1'
        Set-Status "Preview ready. Target count: $($script:PreviewDevices.Count)"
        Set-ButtonsAfterPreview
    }
    catch {
        Add-UiLog "Preview failed: $($_.Exception.Message)" '3'
        Set-Status "ERROR: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Preview failed", "OK", "Error") | Out-Null
    }
})

$btnExport.Add_Click({
    try {
        if (-not $script:PreviewDevices -or $script:PreviewDevices.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("Nothing to export. Run Preview first.", "Export CSV", "OK", "Warning") | Out-Null
            return
        }

        $sfd = New-Object System.Windows.Forms.SaveFileDialog
        $sfd.Filter = "CSV (*.csv)|*.csv"
        $sfd.FileName = "entra-stale-devices-$((Get-Date).ToString('yyyyMMdd-HHmmss')).csv"
        if ($sfd.ShowDialog() -ne 'OK') { return }

        Invoke-Logged -Name "Export-Csv $($sfd.FileName)" -ScriptBlock {
            $script:PreviewDevices | Export-Csv -Path $sfd.FileName -NoTypeInformation -Encoding UTF8
        } | Out-Null

        Add-UiLog "Exported CSV: $($sfd.FileName)" '1'
        Set-Status "Exported CSV"
    }
    catch {
        Add-UiLog "Export failed: $($_.Exception.Message)" '3'
        Set-Status "ERROR: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Export failed", "OK", "Error") | Out-Null
    }
})

$btnRemove.Add_Click({
    try {
        if (-not $script:PreviewDevices -or $script:PreviewDevices.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("Nothing to remove. Run Preview first.", "Remove", "OK", "Warning") | Out-Null
            return
        }

        $count = $script:PreviewDevices.Count
        $whatIf = $chkWhatIf.Checked

        # Confirmation
        $confirm = New-Object System.Windows.Forms.Form
        $confirm.Text = "Confirm deletion"
        $confirm.Width = 520
        $confirm.Height = 240
        $confirm.StartPosition = "CenterParent"
        $confirm.TopMost = $true

        $msg = New-Object System.Windows.Forms.Label
        $msg.AutoSize = $true
        $msg.Location = New-Object System.Drawing.Point(15, 15)
        $msg.Text = "You are about to delete $count device(s) from Entra ID.`nThis is destructive.`n`nType DELETE to continue:"

        $txt = New-Object System.Windows.Forms.TextBox
        $txt.Width = 200
        $txt.Location = New-Object System.Drawing.Point(15, 95)

        $ack = New-Object System.Windows.Forms.CheckBox
        $ack.AutoSize = $true
        $ack.Location = New-Object System.Drawing.Point(15, 130)
        $ack.Text = "I understand this will remove devices from Entra ID"

        $ok = New-Object System.Windows.Forms.Button
        $ok.Text = "Proceed"
        $ok.Width = 120
        $ok.Location = New-Object System.Drawing.Point(250, 160)
        $ok.DialogResult = "OK"

        $cancel = New-Object System.Windows.Forms.Button
        $cancel.Text = "Cancel"
        $cancel.Width = 120
        $cancel.Location = New-Object System.Drawing.Point(380, 160)
        $cancel.DialogResult = "Cancel"

        $confirm.Controls.AddRange(@($msg,$txt,$ack,$ok,$cancel))
        $confirm.AcceptButton = $ok
        $confirm.CancelButton = $cancel

        $dr = $confirm.ShowDialog($script:Form)
        if ($dr -ne 'OK') { return }
        if ($txt.Text -ne 'DELETE' -or -not $ack.Checked) {
            [System.Windows.Forms.MessageBox]::Show("Confirmation failed. No devices were removed.", "Remove", "OK", "Warning") | Out-Null
            return
        }

        Import-GraphModules

        # Baseline connect first (per request). If delete fails, retry with Device.ReadWrite.All.
        Ensure-GraphConnected -RequiredScopes @() # baseline only

        Add-UiLog "Remove clicked. Count=$count WhatIf=$whatIf" '2'
        Set-Status "Removing $count device(s)..."

        $removed = 0
        $failed  = 0

        foreach ($d in $script:PreviewDevices) {
            $name = $d.DisplayName
            $id   = $d.Id

            try {
                if ($whatIf) {
                    Write-CMLog "COMMAND TEXT: [WhatIf] Remove-MgDevice -DeviceId $id" '1'
                    Add-UiLog "[WhatIf] Would remove: $name ($id)" '1'
                } else {
                    try {
                        Remove-DeviceById -Id $id
                    } catch {
                        Add-UiLog "Delete failed with baseline scopes. Retrying with Device.ReadWrite.All..." '2'
                        Ensure-GraphConnected -RequiredScopes @("Device.ReadWrite.All")
                        Remove-DeviceById -Id $id
                    }
                    Add-UiLog "Removed: $name ($id)" '1'
                }
                $removed++
            } catch {
                $failed++
                Add-UiLog "FAILED removing $name ($id): $($_.Exception.Message)" '3'
            }
        }

        if ($whatIf) {
            Set-Status "WhatIf complete. Would remove: $removed. Failed: $failed"
        } else {
            Set-Status "Removal complete. Removed: $removed. Failed: $failed"
        }
    }
    catch {
        Add-UiLog "Remove failed: $($_.Exception.Message)" '3'
        Set-Status "ERROR: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Remove failed", "OK", "Error") | Out-Null
    }
})
#endregion

#region Initial state
Add-UiLog "Launching UI..." '1'
Add-UiLog "Log file: $(Get-LogPath)" '1'

# Disable until ready
$btnExport.Enabled = $false
$btnRemove.Enabled = $false

if (Test-IsAdmin) {
    $btnElevate.Enabled = $false
    $btnElevate.Text = "Running as Administrator"
    Add-UiLog "Process is running elevated." '1'
} else {
    $btnElevate.Enabled = $true
    Add-UiLog "Process is NOT running elevated. Module install will require elevation." '2'
}

$missingAtStart = Get-MissingGraphModules
if ($missingAtStart.Count -gt 0) {
    Add-UiLog ("Graph modules missing: " + ($missingAtStart -join ", ")) '2'
    $script:BtnInstallModules.Enabled = $true
    $script:BtnPreview.Enabled = $false
    Set-Status "Ready (modules missing)"
} else {
    try {
        Import-GraphModules
        Add-UiLog "Graph modules present and imported." '1'
        $script:BtnInstallModules.Enabled = $false
        $script:BtnPreview.Enabled = $true
        Set-Status "Ready"
    } catch {
        Add-UiLog "Graph import failed: $($_.Exception.Message)" '3'
        $script:BtnInstallModules.Enabled = $true
        $script:BtnPreview.Enabled = $false
        Set-Status "Ready (modules missing)"
    }
}
#endregion

[void]$script:Form.ShowDialog()
Write-CMLog "UI closed." '1'
