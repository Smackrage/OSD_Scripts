<#
.SYNOPSIS
  Entra ID stale device cleanup (WinForms): install Graph modules, preview/count, export CSV, delete.

.NOTES
  Author: Martin Smith (Data #3) + ChatGPT
  Date: 15/12/2025
#>

#region CMTrace Logging (FIXED time format for CMTrace parsing)
function Write-CMLog {
    param(
        [Parameter(Mandatory)] [string]$Message,
        [ValidateSet('1','2','3')] [string]$Severity = '1', # 1=Info,2=Warning,3=Error
        [string]$Component = 'EntraDeviceCleanup'
    )
    try {
        $logDir = 'C:\Windows\CCM\Logs'
        if (-not (Test-Path $logDir)) { $logDir = "$env:WINDIR\Temp" }
        $logPath = Join-Path $logDir 'EntraDeviceCleanup.log'

        $now = Get-Date

        # CMTrace is fussy: time needs timezone offset
        # Example: 16:44:12.123+600  (Brisbane is +10 hours => +600 minutes)
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
Add-Type -AssemblyName System.ComponentModel

function Test-IsAdmin {
    try {
        $wp = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        return $wp.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "Entra ID Device Cleanup (Stale Devices)"
$form.Width = 1050
$form.Height = 820
$form.StartPosition = "CenterScreen"
$form.TopMost = $true

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

$btnPreview = New-Object System.Windows.Forms.Button
$btnPreview.Text = "Preview / Count"
$btnPreview.Width = 140
$btnPreview.Location = New-Object System.Drawing.Point(300, 10)

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

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "Status: Ready"
$lblStatus.AutoSize = $true
$lblStatus.Location = New-Object System.Drawing.Point(15, 45)

$btnInstallModules = New-Object System.Windows.Forms.Button
$btnInstallModules.Text = "Install Graph Modules"
$btnInstallModules.Width = 170
$btnInstallModules.Location = New-Object System.Drawing.Point(300, 42)

$btnElevate = New-Object System.Windows.Forms.Button
$btnElevate.Text = "Restart as Administrator"
$btnElevate.Width = 190
$btnElevate.Location = New-Object System.Drawing.Point(900, 42)

$prgInstall = New-Object System.Windows.Forms.ProgressBar
$prgInstall.Width = 420
$prgInstall.Height = 18
$prgInstall.Location = New-Object System.Drawing.Point(480, 45)
$prgInstall.Minimum = 0
$prgInstall.Maximum = 100
$prgInstall.Value = 0

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

$txtInstallLog = New-Object System.Windows.Forms.TextBox
$txtInstallLog.Multiline = $true
$txtInstallLog.ScrollBars = "Vertical"
$txtInstallLog.ReadOnly = $true
$txtInstallLog.WordWrap = $false
$txtInstallLog.Width = 1000
$txtInstallLog.Height = 200
$txtInstallLog.Location = New-Object System.Drawing.Point(15, 585)

$form.Controls.AddRange(@(
    $lblDays,$numDays,$btnPreview,$btnExport,$btnRemove,$chkWhatIf,
    $lblStatus,$btnInstallModules,$prgInstall,$btnElevate,$grid,$txtInstallLog
))

function Set-Status([string]$text) {
    $lblStatus.Text = "Status: $text"
    [System.Windows.Forms.Application]::DoEvents() | Out-Null
}

# Buffer log lines until handle exists
$script:UiLogBuffer = New-Object System.Collections.Generic.List[string]

function Add-UiLog {
    param(
        [Parameter(Mandatory)][string]$Text,
        [ValidateSet('1','2','3')][string]$Severity = '1'
    )
    $line = "[{0}] {1}" -f (Get-Date).ToString("HH:mm:ss"), $Text
    Write-CMLog $Text $Severity

    if ($form.IsHandleCreated) {
        $form.BeginInvoke([Action]{
            $txtInstallLog.AppendText($line + [Environment]::NewLine)
        }) | Out-Null
    } else {
        [void]$script:UiLogBuffer.Add($line)
    }
}

$form.Add_Shown({
    if ($script:UiLogBuffer.Count -gt 0) {
        foreach ($l in $script:UiLogBuffer) {
            $txtInstallLog.AppendText($l + [Environment]::NewLine)
        }
        $script:UiLogBuffer.Clear()
    }
})
#endregion

#region Graph helpers
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
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop | Out-Null
    Import-Module Microsoft.Graph.Identity.DirectoryManagement -ErrorAction Stop | Out-Null
}
#endregion

#region BackgroundWorker install (FIXED: native .NET event handlers)
$worker = New-Object System.ComponentModel.BackgroundWorker
$worker.WorkerReportsProgress = $true
$worker.WorkerSupportsCancellation = $false

# DoWork
$worker.add_DoWork([System.ComponentModel.DoWorkEventHandler]{
    param($sender, $e)

    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

    $missing = $e.Argument
    if (-not $missing -or $missing.Count -eq 0) {
        $sender.ReportProgress(100, "Nothing to install.")
        return
    }

    # NuGet provider
    if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
        $sender.ReportProgress(1, "Installing NuGet provider (verbose follows)...")
        $out = (Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction Stop -Verbose 4>&1)
        foreach ($o in $out) { if ($o) { $sender.ReportProgress(1, "[VERBOSE] " + $o.ToString()) } }
    }

    # Trust PSGallery (avoid prompts)
    try {
        $repo = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
        if ($repo -and $repo.InstallationPolicy -ne 'Trusted') {
            $sender.ReportProgress(2, "Setting PSGallery InstallationPolicy to Trusted (verbose follows)...")
            $out = (Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction Stop -Verbose 4>&1)
            foreach ($o in $out) { if ($o) { $sender.ReportProgress(2, "[VERBOSE] " + $o.ToString()) } }
        }
    } catch {
        $sender.ReportProgress(2, "Could not set PSGallery trust (continuing): $($_.Exception.Message)")
    }

    $total = $missing.Count
    $i = 0

    foreach ($module in $missing) {
        $i++
        $pctBase = [int](($i - 1) / $total * 100)
        $sender.ReportProgress($pctBase, "Installing $module ($i of $total)...")

        $out = (Install-Module -Name $module -Repository PSGallery -Scope AllUsers -Force -AllowClobber -ErrorAction Stop -Verbose 4>&1)
        foreach ($o in $out) { if ($o) { $sender.ReportProgress($pctBase, "$module [VERBOSE] " + $o.ToString()) } }

        $sender.ReportProgress([int]($i / $total * 100), "Installed $module")
    }
})

# ProgressChanged
$worker.add_ProgressChanged([System.ComponentModel.ProgressChangedEventHandler]{
    param($sender, $e)
    $msg = [string]$e.UserState
    if ($msg) { Add-UiLog $msg '1' }

    $val = [int]$e.ProgressPercentage
    if ($val -lt 0) { $val = 0 }
    if ($val -gt 100) { $val = 100 }
    $prgInstall.Value = $val
})

# RunWorkerCompleted
$worker.add_RunWorkerCompleted([System.ComponentModel.RunWorkerCompletedEventHandler]{
    param($sender, $e)

    if ($e.Error) {
        Add-UiLog ("Install failed: " + $e.Error.Message) '3'
        [System.Windows.Forms.MessageBox]::Show($e.Error.Message, "Module install failed", "OK", "Error") | Out-Null
        $prgInstall.Value = 0
        $btnInstallModules.Enabled = $true
        Set-Status "Ready (modules missing)"
        return
    }

    Add-UiLog "Install complete. Importing modules..." '1'
    try {
        Import-GraphModules
        Add-UiLog "Modules imported successfully." '1'
    } catch {
        Add-UiLog ("Import failed: " + $_.Exception.Message) '3'
    }

    $btnInstallModules.Enabled = $false
    $prgInstall.Value = 100
    Set-Status "Ready (Graph installed)"
})
#endregion

#region Main buttons
$script:PreviewDevices = @()

$btnElevate.Add_Click({
    try {
        Add-UiLog "Elevation requested. Relaunching as Administrator..." '2'

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "powershell.exe"
        $psi.Arguments = "-STA -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        $psi.Verb = "runas"
        $psi.UseShellExecute = $true

        [System.Diagnostics.Process]::Start($psi) | Out-Null
        $form.Close()
    } catch {
        Add-UiLog "Elevation cancelled or failed: $($_.Exception.Message)" '2'
    }
})

$btnInstallModules.Add_Click({
    try {
        $missing = Get-MissingGraphModules
        if (-not $missing -or $missing.Count -eq 0) {
            Add-UiLog "Graph modules already installed." '1'
            $btnInstallModules.Enabled = $false
            Set-Status "Ready (Graph already installed)"
            return
        }

        if (-not (Test-IsAdmin)) {
            [System.Windows.Forms.MessageBox]::Show(
                "Installing Graph modules requires administrator privileges.`n`nClick 'Restart as Administrator' first.",
                "Elevation required",
                "OK",
                "Warning"
            ) | Out-Null
            return
        }

        $btnInstallModules.Enabled = $false
        $prgInstall.Style = 'Marquee'
        Set-Status "Installing Graph modules..."
        Add-UiLog "Starting Graph module install in separate PowerShell process..." '1'

        $modules = $missing -join ','

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "powershell.exe"
        $psi.Arguments = @"
-NoProfile -ExecutionPolicy Bypass -Command `
`"[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction Stop;
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue;
Install-Module -Name $modules -Repository PSGallery -Scope AllUsers -Force -AllowClobber -Verbose;
`"
"@
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow  = $true

        $proc = [System.Diagnostics.Process]::Start($psi)

        while (-not $proc.HasExited) {
            Start-Sleep -Milliseconds 200
            if (-not $proc.StandardOutput.EndOfStream) {
                $line = $proc.StandardOutput.ReadLine()
                if ($line) { Add-UiLog "[VERBOSE] $line" '1' }
            }
            if (-not $proc.StandardError.EndOfStream) {
                $err = $proc.StandardError.ReadLine()
                if ($err) { Add-UiLog "[ERROR] $err" '3' }
            }
        }

        if ($proc.ExitCode -ne 0) {
            throw "Module install process failed with exit code $($proc.ExitCode)"
        }

        Add-UiLog "Graph module installation completed successfully." '1'
        Import-GraphModules
        Add-UiLog "Graph modules imported." '1'

        $prgInstall.Style = 'Blocks'
        $prgInstall.Value = 100
        Set-Status "Ready (Graph installed)"
    }
    catch {
        Add-UiLog "Module install failed: $($_.Exception.Message)" '3'
        $btnInstallModules.Enabled = $true
        $prgInstall.Style = 'Blocks'
        $prgInstall.Value = 0
        Set-Status "Ready (modules missing)"
        [System.Windows.Forms.MessageBox]::Show(
            $_.Exception.Message,
            "Module install failed",
            "OK",
            "Error"
        ) | Out-Null
    }
})
#endregion

#region Initial state
Add-UiLog "Launching UI..." '1'

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
    $btnInstallModules.Enabled = $true
    Set-Status "Ready (modules missing)"
} else {
    try {
        Import-GraphModules
        Add-UiLog "Graph modules present and imported." '1'
    } catch {
        Add-UiLog ("Graph import error: " + $_.Exception.Message) '2'
    }
    $btnInstallModules.Enabled = $false
    Set-Status "Ready"
}

#endregion

[void]$form.ShowDialog()
Write-CMLog "UI closed." '1'
