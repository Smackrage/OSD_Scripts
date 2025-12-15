<#
.SYNOPSIS
  Entra ID stale device cleanup (WinForms): preview, export CSV, delete.

.DESCRIPTION
  - Filters devices by ApproximateLastSignInDateTime older than X days
  - Preview button shows count + populates grid
  - Export CSV button exports the current preview set
  - Remove button deletes the preview set from Entra ID (with typed confirmation)
  - CMTrace-compatible logging to C:\Windows\CCM\Logs\EntraDeviceCleanup.log

.REQUIREMENTS
  - Microsoft Graph PowerShell modules:
      Microsoft.Graph.Authentication
      Microsoft.Graph.Identity.DirectoryManagement
  - Permissions (Graph scopes):
      Preview/Export: Device.Read.All (or Directory.Read.All)
      Delete: Device.ReadWrite.All (or Directory.AccessAsUser.All delegated)
    Remove-MgDevice permissions documented by Microsoft. :contentReference[oaicite:1]{index=1}

.NOTES
  Author: Martin Smith (Data #3) + ChatGPT
  Date: 15/12/2025
#>

#region CMTrace Logging
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

        $time = Get-Date
        $timeString = $time.ToString('HH:mm:ss.fff')
        $dateString = $time.ToString('MM-dd-yyyy')
        $pid = $PID
        $thread = [System.Threading.Thread]::CurrentThread.ManagedThreadId

        $line = "<![LOG[$Message]LOG]!><time=""$timeString"" date=""$dateString"" component=""$Component"" context="""" type=""$Severity"" thread=""$thread"" file="""">"
        Add-Content -Path $logPath -Value $line -Encoding UTF8
        Write-Output $Message
    } catch {
        Write-Output "Write-CMLog failed: $($_.Exception.Message)"
    }
}
#endregion CMTrace Logging

#region Ensure STA
if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    Write-CMLog "Not in STA. Relaunching PowerShell in STA..." '2'
    Start-Process -FilePath "powershell.exe" -ArgumentList "-STA -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Wait
    exit
}
#endregion

#region Imports / Prereqs
function Ensure-GraphModules {
    $mods = @(
        'Microsoft.Graph.Authentication',
        'Microsoft.Graph.Identity.DirectoryManagement'
    )
    foreach ($m in $mods) {
        if (-not (Get-Module -ListAvailable -Name $m)) {
            throw "Required module '$m' not found. Install with: Install-Module $m -Scope AllUsers"
        }
    }
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
    Import-Module Microsoft.Graph.Identity.DirectoryManagement -ErrorAction Stop
}

function Ensure-GraphConnection {
    param(
        [switch]$NeedWrite
    )
    $needScopes = if ($NeedWrite) {
        @('Device.ReadWrite.All')
    } else {
        @('Device.Read.All')
    }

    try {
        $ctx = Get-MgContext -ErrorAction SilentlyContinue
        $connected = $ctx -and $ctx.Account -and $ctx.Scopes
        $hasScopes = $false
        if ($connected) {
            $hasScopes = @($needScopes | ForEach-Object { $ctx.Scopes -contains $_ }) -notcontains $false
        }

        if (-not $connected -or -not $hasScopes) {
            Write-CMLog "Connecting to Microsoft Graph with scopes: $($needScopes -join ', ')" '1'
            Connect-MgGraph -Scopes $needScopes -ErrorAction Stop | Out-Null
        } else {
            Write-CMLog "Graph already connected as $($ctx.Account). Scopes OK." '1'
        }
    } catch {
        throw "Graph connection failed: $($_.Exception.Message)"
    }
}
#endregion

#region Data retrieval (server-side filter with fallback)
function Get-StaleEntraDevices {
    param(
        [Parameter(Mandatory)] [int]$OlderThanDays
    )

    $cutoff = (Get-Date).AddDays(-1 * $OlderThanDays)
    Write-CMLog "Cutoff date/time: $cutoff (older than $OlderThanDays days)" '1'

    # Try server-side filter first (faster on large tenants). If it fails, fall back.
    # Microsoft docs recommend using timestamp filters for large directories. :contentReference[oaicite:2]{index=2}
    $iso = $cutoff.ToString("yyyy-MM-ddTHH:mm:ssZ")
    $filter = "approximateLastSignInDateTime le $iso"

    try {
        Write-CMLog "Attempting server-side filter via Graph: $filter" '1'

        # Using Invoke-MgGraphRequest to control headers ($count) and query params.
        $uri = "/devices?`$select=id,deviceId,displayName,accountEnabled,operatingSystem,operatingSystemVersion,trustType,approximateLastSignInDateTime&`$filter=$([uri]::EscapeDataString($filter))&`$top=999"

        $all = New-Object System.Collections.Generic.List[object]
        $next = $uri
        do {
            $resp = Invoke-MgGraphRequest -Method GET -Uri $next -Headers @{ 'ConsistencyLevel'='eventual' } -ErrorAction Stop
            if ($resp.value) { $resp.value | ForEach-Object { [void]$all.Add($_) } }
            $next = $resp.'@odata.nextLink'
            if ($next) {
                # nextLink can be full URL; Invoke-MgGraphRequest accepts it.
                Write-CMLog "Paging nextLink..." '1'
            }
        } while ($next)

        Write-CMLog "Server-side returned $($all.Count) device(s)." '1'
        return ,$all
    } catch {
        Write-CMLog "Server-side filter failed, falling back to Get-MgDevice -All then client-side filter. Error: $($_.Exception.Message)" '2'

        $devices = Get-MgDevice -All -Property "id,deviceId,displayName,accountEnabled,operatingSystem,operatingSystemVersion,trustType,approximateLastSignInDateTime" -ErrorAction Stop
        $stale = $devices | Where-Object {
            $_.ApproximateLastSignInDateTime -and ([datetime]$_.ApproximateLastSignInDateTime -le $cutoff)
        }

        Write-CMLog "Client-side filtered $($stale.Count) stale device(s) out of $($devices.Count) total." '1'
        return ,$stale
    }
}
#endregion

#region UI
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form = New-Object System.Windows.Forms.Form
$form.Text = "Entra ID Device Cleanup (Stale Devices)"
$form.Width = 1050
$form.Height = 650
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
$btnExport.Enabled = $false
$btnExport.Location = New-Object System.Drawing.Point(450, 10)

$btnRemove = New-Object System.Windows.Forms.Button
$btnRemove.Text = "REMOVE from Entra ID"
$btnRemove.Width = 180
$btnRemove.Enabled = $false
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

$grid = New-Object System.Windows.Forms.DataGridView
$grid.Location = New-Object System.Drawing.Point(15, 70)
$grid.Width = 1000
$grid.Height = 520
$grid.ReadOnly = $true
$grid.AllowUserToAddRows = $false
$grid.AllowUserToDeleteRows = $false
$grid.AutoSizeColumnsMode = "Fill"
$grid.SelectionMode = "FullRowSelect"
$grid.MultiSelect = $true

$form.Controls.AddRange(@($lblDays,$numDays,$btnPreview,$btnExport,$btnRemove,$chkWhatIf,$lblStatus,$grid))

# Backing store for current preview
$script:PreviewDevices = @()

function Set-Status([string]$text) {
    $lblStatus.Text = "Status: $text"
    [System.Windows.Forms.Application]::DoEvents() | Out-Null
}

function To-DeviceRowObject($d) {
    # normalise both SDK objects and Invoke-MgGraphRequest hashy objects
    $id = $d.Id
    $deviceId = $d.DeviceId
    $name = $d.DisplayName
    $os = $d.OperatingSystem
    $osv = $d.OperatingSystemVersion
    $trust = $d.TrustType
    $enabled = $d.AccountEnabled
    $last = $d.ApproximateLastSignInDateTime

    [pscustomobject]@{
        DisplayName = $name
        DeviceId    = $deviceId
        ObjectId    = $id
        OS          = $os
        OSVersion   = $osv
        TrustType   = $trust
        Enabled     = $enabled
        LastSignIn  = $last
    }
}

#endregion UI

#region Button Handlers
$btnPreview.Add_Click({
    try {
        Ensure-GraphModules
        Ensure-GraphConnection

        $days = [int]$numDays.Value
        Set-Status "Retrieving devices older than $days days..."
        Write-CMLog "Preview clicked. Days=$days" '1'

        $stale = Get-StaleEntraDevices -OlderThanDays $days
        $script:PreviewDevices = @($stale)

        $rows = $script:PreviewDevices | ForEach-Object { To-DeviceRowObject $_ }
        $grid.DataSource = $rows

        $count = $script:PreviewDevices.Count
        Set-Status "Preview ready. Target count: $count"
        Write-CMLog "Preview complete. Count=$count" '1'

        $btnExport.Enabled = ($count -gt 0)
        $btnRemove.Enabled = ($count -gt 0)
    } catch {
        Set-Status "ERROR: $($_.Exception.Message)"
        Write-CMLog "Preview failed: $($_.Exception.Message)" '3'
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

        $export = $script:PreviewDevices | ForEach-Object { To-DeviceRowObject $_ }
        $export | Export-Csv -Path $sfd.FileName -NoTypeInformation -Encoding UTF8

        Write-CMLog "Exported CSV to $($sfd.FileName) (Count=$($export.Count))" '1'
        Set-Status "Exported CSV: $($sfd.FileName)"
        [System.Windows.Forms.MessageBox]::Show("Export complete:`n$($sfd.FileName)", "Export CSV", "OK", "Information") | Out-Null
    } catch {
        Set-Status "ERROR: $($_.Exception.Message)"
        Write-CMLog "Export failed: $($_.Exception.Message)" '3'
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

        # Confirmation dialog
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

        # Need write scope for deletions
        Ensure-GraphModules
        Ensure-GraphConnection -NeedWrite

        $whatIf = $chkWhatIf.Checked
        Write-CMLog "Remove clicked. Count=$count WhatIf=$whatIf" '2'
        Set-Status "Removing $count device(s)..."

        $removed = 0
        $failed  = 0

        foreach ($d in $script:PreviewDevices) {
            $name = $d.DisplayName
            $objId = $d.Id
            try {
                if ($whatIf) {
                    Write-CMLog "[WhatIf] Would remove: $name ($objId)" '1'
                } else {
                    Remove-MgDevice -DeviceId $objId -ErrorAction Stop
                    Write-CMLog "Removed: $name ($objId)" '1'
                }
                $removed++
            } catch {
                $failed++
                Write-CMLog "FAILED removing $name ($objId): $($_.Exception.Message)" '3'
            }
        }

        if ($whatIf) {
            Set-Status "WhatIf complete. Would remove: $removed. Failed (simulated): $failed"
            [System.Windows.Forms.MessageBox]::Show("WhatIf complete.`nWould remove: $removed`nFailures: $failed", "Remove (WhatIf)", "OK", "Information") | Out-Null
        } else {
            Set-Status "Removal complete. Removed: $removed. Failed: $failed"
            [System.Windows.Forms.MessageBox]::Show("Removal complete.`nRemoved: $removed`nFailures: $failed", "Remove", "OK", "Information") | Out-Null
        }

    } catch {
        Set-Status "ERROR: $($_.Exception.Message)"
        Write-CMLog "Remove failed: $($_.Exception.Message)" '3'
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Remove failed", "OK", "Error") | Out-Null
    }
})
#endregion

try {
    Write-CMLog "Launching UI..." '1'
    Ensure-GraphModules
} catch {
    Write-CMLog "Prereq warning: $($_.Exception.Message)" '2'
    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Prerequisites missing", "OK", "Warning") | Out-Null
}

[void]$form.ShowDialog()
Write-CMLog "UI closed." '1'
