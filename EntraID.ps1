<#
.SYNOPSIS
  Entra ID stale device cleanup (WinForms): install Graph modules, preview/count, export CSV, delete.

.NOTES
  Author: Martin Smith (Data #3) + ChatGPT
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
    <#
      Logs the command text and captures output/errors, logging each line.
      Usage:
        Invoke-Logged -Name "Connect Graph" -ScriptBlock { Connect-MgGraph ... } -VerboseToLog
    #>
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

# Buffer UI log lines until form handle exists
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
#endregion UI + Helpers

#region Graph helpers (with command logging)
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
    }
}

function Ensure-GraphConnection {
    param([switch]$NeedWrite)

    $needScopes = if ($NeedWrite) { @('Device.ReadWrite.All') } else { @('Device.Read.All') }

    $ctx = $null
    try { $ctx = Get-MgContext -ErrorAction SilentlyContinue } catch {}

    $connected = $ctx -and $ctx.Account -and $ctx.Scopes
    $hasScopes = $false

    if ($connected) {
        $hasScopes = @($needScopes | ForEach-Object { $ctx.Scopes -contains $_ }) -notcontains $false
    }

    if (-not $connected -or -not $hasScopes) {
        Add-UiLog ("Connecting to Microsoft Graph with scopes: " + ($needScopes -join ", ")) '1'
        Invoke-Logged -Name "Connect-MgGraph" -VerboseToLog -ScriptBlock {
            Connect-MgGraph -Scopes $needScopes -ErrorAction Stop -Verbose
        } | Out-Null
    } else {
        Add-UiLog "Graph already connected as $($ctx.Account). Scopes OK." '1'
    }
}

function To-DeviceRowObject($d) {
    [pscustomobject]@{
        DisplayName = $d.DisplayName
        DeviceId    = $d.DeviceId
        ObjectId    = $d.Id
        OS          = $d.OperatingSystem
        OSVersion   = $d.OperatingSystemVersion
        TrustType   = $d.TrustType
        Enabled     = $d.AccountEnabled
        LastSignIn  = $d.ApproximateLastSignInDateTime
    }
}

function Get-StaleEntraDevices {
    param([Parameter(Mandatory)][int]$OlderThanDays)

    $cutoff = (Get-Date).AddDays(-1 * $OlderThanDays)
    Add-UiLog "Cutoff date/time: $cutoff (older than $OlderThanDays days)" '1'

    # Use server-side paging request (works reliably and is fast)
    $iso = $cutoff.ToString("yyyy-MM-ddTHH:mm:ssZ")
    $filter = "approximateLastSignInDateTime le $iso"
    Add-UiLog "Graph filter: $filter" '1'
    Write-CMLog "COMMAND TEXT (Graph Request): Invoke-MgGraphRequest GET /devices?... filter=$filter" '1'

    $uri = "/devices?`$select=id,deviceId,displayName,accountEnabled,operatingSystem,operatingSystemVersion,trustType,approximateLastSignInDateTime&`$filter=$([uri]::EscapeDataString($filter))&`$top=999"

    $all  = New-Object System.Collections.Generic.List[object]
    $next = $uri

    do {
        $resp = Invoke-Logged -Name "Invoke-MgGraphRequest (paged devices)" -ScriptBlock {
            Invoke-MgGraphRequest -Method GET -Uri $next -Headers @{ 'ConsistencyLevel'='eventual' } -ErrorAction Stop
        }
        if ($resp.value) { $resp.value | ForEach-Object { [void]$all.Add($_) } }
        $next = $resp.'@odata.nextLink'
        if ($next) { Add-UiLog "Paging nextLink..." '1' }
    } while ($next)

    Add-UiLog "Returned $($all.Count) device(s) matching filter." '1'
    return ,$all
}
#endregion

#region Non-blocking module install via child PowerShell process + Timer polling
$script:InstallProcess = $null
$script:InstallTimer   = New-Object System.Windows.Forms.Timer
$script:InstallTimer.Interval = 250

$script:InstallTimer.Add_Tick({
    if (-not $script:InstallProcess) { return }

    # Drain stdout
    try {
        while (-not $script:InstallProcess.StandardOutput.EndOfStream) {
            $line = $script:InstallProcess.StandardOutput.ReadLine()
            if ($line) { Add-UiLog "[INSTALL] $line" '1' }
        }
    } catch {
        Add-UiLog "StdOut read error: $($_.Exception.Message)" '2'
    }

    # Drain stderr
    try {
        while (-not $script:InstallProcess.StandardError.EndOfStream) {
            $err = $script:InstallProcess.StandardError.ReadLine()
            if ($err) { Add-UiLog "[INSTALL-ERR] $err" '3' }
        }
    } catch {
        Add-UiLog "StdErr read error: $($_.Exception.Message)" '2'
    }

    if ($script:InstallProcess.HasExited) {
        $script:InstallTimer.Stop()

        $exitCode = $script:InstallProcess.ExitCode
        $script:InstallProcess.Dispose()
        $script:InstallProcess = $null

        $prgInstall.Style = 'Blocks'

        if ($exitCode -ne 0) {
            Add-UiLog "Module install failed (exit code $exitCode)" '3'
            $btnInstallModules.Enabled = $true
            $prgInstall.Value = 0
            Set-Status "Ready (modules missing)"
            return
        }

        Add-UiLog "Graph module installation completed successfully." '1'
        try {
            Import-GraphModules
            Add-UiLog "Graph modules imported." '1'
            $btnInstallModules.Enabled = $false
            $prgInstall.Value = 100
            Set-GraphButtonsEnabled $true
            Set-Status "Ready (Graph installed)"
        } catch {
            Add-UiLog "Install succeeded but import failed: $($_.Exception.Message)" '3'
            $btnInstallModules.Enabled = $true
            $prgInstall.Value = 0
            Set-GraphButtonsEnabled $false
            Set-Status "Ready (modules missing)"
        }
    }
})
#endregion

#region App logic buttons (Preview/Export/Remove)
$script:PreviewDevices = @()

function Set-GraphButtonsEnabled([bool]$enabled) {
    $btnPreview.Enabled = $enabled
    $btnExport.Enabled  = $enabled -and ($script:PreviewDevices.Count -gt 0)
    $btnRemove.Enabled  = $enabled -and ($script:PreviewDevices.Count -gt 0)
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
        $form.Close()
    } catch {
        Add-UiLog "Elevation cancelled or failed: $($_.Exception.Message)" '2'
    }
})

$btnInstallModules.Add_Click({
    try {
        if ($script:InstallProcess) {
            Add-UiLog "Install already running..." '2'
            return
        }

        $missing = Get-MissingGraphModules
        if (-not $missing -or $missing.Count -eq 0) {
            Add-UiLog "Graph modules already installed." '1'
            $btnInstallModules.Enabled = $false
            Set-GraphButtonsEnabled $true
            Set-Status "Ready (Graph already installed)"
            return
        }

        if (-not (Test-IsAdmin)) {
            Add-UiLog "Module install requires elevation. Click 'Restart as Administrator'." '2'
            [System.Windows.Forms.MessageBox]::Show(
                "Installing Graph modules requires administrator privileges.`n`nClick 'Restart as Administrator' and try again.",
                "Elevation required",
                "OK",
                "Warning"
            ) | Out-Null
            return
        }

        Add-UiLog ("Missing modules: " + ($missing -join ", ")) '2'
        Add-UiLog "Starting module install process (non-blocking)..." '1'

        $btnInstallModules.Enabled = $false
        Set-GraphButtonsEnabled $false

        $prgInstall.Style = 'Marquee'
        $prgInstall.MarqueeAnimationSpeed = 30
        $prgInstall.Value = 0
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
    }
    catch {
        Add-UiLog "Failed to start install: $($_.Exception.Message)" '3'
        $btnInstallModules.Enabled = $true
        $prgInstall.Style = 'Blocks'
        $prgInstall.Value = 0
        Set-Status "Ready (modules missing)"
    }
})

$btnPreview.Add_Click({
    try {
        Import-GraphModules
        Ensure-GraphConnection

        $days = [int]$numDays.Value
        Set-Status "Retrieving devices older than $days days..."
        Add-UiLog "Preview clicked. Days=$days" '1'

        $stale = Get-StaleEntraDevices -OlderThanDays $days
        $script:PreviewDevices = @($stale)

        $rows = $script:PreviewDevices | ForEach-Object { To-DeviceRowObject $_ }
        $grid.DataSource = $rows

        $count = $script:PreviewDevices.Count
        Set-Status "Preview ready. Target count: $count"
        Add-UiLog "Preview complete. Count=$count" '1'

        $btnExport.Enabled = ($count -gt 0)
        $btnRemove.Enabled = ($count -gt 0)
    }
    catch {
        Set-Status "ERROR: $($_.Exception.Message)"
        Add-UiLog ("Preview failed: " + $_.Exception.Message) '3'
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

        Write-CMLog "COMMAND START: Export-Csv to $($sfd.FileName)" '1'
        $export = $script:PreviewDevices | ForEach-Object { To-DeviceRowObject $_ }
        $export | Export-Csv -Path $sfd.FileName -NoTypeInformation -Encoding UTF8
        Write-CMLog "COMMAND END: Export-Csv (OK) Count=$($export.Count)" '1'

        Add-UiLog "Exported CSV to $($sfd.FileName) (Count=$($export.Count))" '1'
        Set-Status "Exported CSV"
        [System.Windows.Forms.MessageBox]::Show("Export complete:`n$($sfd.FileName)", "Export CSV", "OK", "Information") | Out-Null
    }
    catch {
        Set-Status "ERROR: $($_.Exception.Message)"
        Add-UiLog ("Export failed: " + $_.Exception.Message) '3'
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

        $dr = $confirm.ShowDialog($form)
        if ($dr -ne 'OK') { return }

        if ($txt.Text -ne 'DELETE' -or -not $ack.Checked) {
            [System.Windows.Forms.MessageBox]::Show("Confirmation failed. No devices were removed.", "Remove", "OK", "Warning") | Out-Null
            return
        }

        Import-GraphModules
        Ensure-GraphConnection -NeedWrite

        $whatIf = $chkWhatIf.Checked
        Add-UiLog "Remove clicked. Count=$count WhatIf=$whatIf" '2'
        Set-Status "Removing $count device(s)..."

        $removed = 0
        $failed  = 0

        foreach ($d in $script:PreviewDevices) {
            $name  = $d.DisplayName
            $objId = $d.Id

            try {
                if ($whatIf) {
                    Write-CMLog "COMMAND TEXT: [WhatIf] Remove-MgDevice -DeviceId $objId" '1'
                    Add-UiLog "[WhatIf] Would remove: $name ($objId)" '1'
                } else {
                    Invoke-Logged -Name "Remove-MgDevice ($name)" -VerboseToLog -ScriptBlock {
                        Remove-MgDevice -DeviceId $objId -ErrorAction Stop -Verbose
                    } | Out-Null
                    Add-UiLog "Removed: $name ($objId)" '1'
                }
                $removed++
            }
            catch {
                $failed++
                Add-UiLog ("FAILED removing $name ($objId): " + $_.Exception.Message) '3'
            }
        }

        if ($whatIf) {
            Set-Status "WhatIf complete. Would remove: $removed. Failed: $failed"
            [System.Windows.Forms.MessageBox]::Show("WhatIf complete.`nWould remove: $removed`nFailures: $failed", "Remove (WhatIf)", "OK", "Information") | Out-Null
        } else {
            Set-Status "Removal complete. Removed: $removed. Failed: $failed"
            [System.Windows.Forms.MessageBox]::Show("Removal complete.`nRemoved: $removed`nFailures: $failed", "Remove", "OK", "Information") | Out-Null
        }
    }
    catch {
        Set-Status "ERROR: $($_.Exception.Message)"
        Add-UiLog ("Remove failed: " + $_.Exception.Message) '3'
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Remove failed", "OK", "Error") | Out-Null
    }
})
#endregion

#region Initial state
Add-UiLog "Launching UI..." '1'
Add-UiLog "Log file: $(Get-LogPath)" '1'

$script:PreviewDevices = @()
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
    $btnInstallModules.Enabled = $true
    Set-GraphButtonsEnabled $false
    Set-Status "Ready (modules missing)"
} else {
    try {
        Import-GraphModules
        Add-UiLog "Graph modules present and imported." '1'
    } catch {
        Add-UiLog ("Graph import error: " + $_.Exception.Message) '2'
    }
    $btnInstallModules.Enabled = $false
    Set-GraphButtonsEnabled $true
    Set-Status "Ready"
}
#endregion

[void]$form.ShowDialog()
Write-CMLog "UI closed." '1'
