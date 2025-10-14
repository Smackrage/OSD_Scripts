<#
.SYNOPSIS
TCAS / IFE NIC configurator (SYSTEM context, fixed layout, Find Free/Random IP for IFE)

.DESCRIPTION
- TCAS: 192.168.111.200/16 + GW 192.168.1.1
- IFE: If a route to 172.19.0.0/16 exists, scan for a free IP; if not, pick a random IP in 172.19.X.Y.
- Opens inbound firewall TCP 2022 ("SSH-2022").
- Reset returns adapter to DHCP.
- CMTrace logging; GUI stays open until closed.
- Inline status for route detection and adapter list.
- Close button added to exit cleanly.
- **Only physical Ethernet adapters** are listed.

.NOTES
Author: Martin Smith (Data #3)
Date: 13/10/2025
Version: 1.8
#>

#region ===== CMTrace-compatible logging =====
$script:LogDir = $env:_SMSTSLogPath
if ([string]::IsNullOrWhiteSpace($script:LogDir)) { $script:LogDir = $env:LOGPATH }
if ([string]::IsNullOrWhiteSpace($script:LogDir)) { $script:LogDir = "C:\Windows\CCM\Logs" }
if (-not (Test-Path $script:LogDir)) { $script:LogDir = "C:\Windows\Temp" }

$scriptName = if ($PSCommandPath) { [IO.Path]::GetFileNameWithoutExtension($PSCommandPath) } else { 'TCAS_IFE_Config' }
$script:LogPath = Join-Path $script:LogDir ("$scriptName.log")

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet(1,2,3)][int]$Severity = 1,
        [string]$Component = $scriptName
    )
    $ts = Get-Date
    $line = "<![LOG[$Message]LOG]!><time=""{0}"" date=""{1}"" component=""{2}"" context="""" type=""{3}"" thread="""" file="""">" -f $ts.ToString("HH:mm:ss.fff"), $ts.ToString("dd-MM-yyyy"), $Component, $Severity
    $line | Out-File -FilePath $script:LogPath -Encoding default -Append
    $line | Write-Host
}
Write-Log "==== Script start ===="
Write-Log "Log file: $script:LogPath"
#endregion

#region ===== Networking helpers =====
function Get-PhysicalEthernetAdapters {
    Write-Log "Enumerating physical Ethernet adapters..."
    $adapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Status -ne 'Disabled' -and
            $_.HardwareInterface -and
            (
                $_.Name -match 'Ethernet' -or
                $_.InterfaceDescription -match 'Ethernet'
            )
        } |
        Sort-Object ifIndex

    # Exclude junk and virtuals
    $exclude = @('virtual','hyper-v','vmware','bluetooth','wi-fi','wifi','wlan','tunnel','wireless','loopback','container','npcap','docker','wsl','remote','rdp','wan')
    $filtered = $adapters | Where-Object {
        $n = $_.Name.ToLower()
        $d = $_.InterfaceDescription.ToLower()
        -not ($exclude | Where-Object { $n -like "*$_*" -or $d -like "*$_*" })
    }

    Write-Log "Found $($filtered.Count) physical Ethernet adapter(s)."
    return $filtered
}

function Remove-ExistingIPv4 {
    param([Parameter(Mandatory)][string]$Alias)
    Get-NetIPAddress -InterfaceAlias $Alias -AddressFamily IPv4 -ErrorAction SilentlyContinue | ForEach-Object {
        try { Remove-NetIPAddress -InputObject $_ -Confirm:$false -ErrorAction Stop; Write-Log "Removed IP $($_.IPAddress)/$($_.PrefixLength) on $Alias" }
        catch { Write-Log "Failed removing IP $($_.IPAddress) on $Alias : $($_.Exception.Message)" 3 }
    }
    try {
        Get-NetRoute -InterfaceAlias $Alias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.NextHop -ne '0.0.0.0' } |
            Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
    } catch { }
}

function Set-IPv4Static {
    param(
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$IPAddress,
        [Parameter(Mandatory)][int]$PrefixLength,
        [string]$DefaultGateway
    )
    Remove-ExistingIPv4 -Alias $Alias
    try {
        $args = @{
            InterfaceAlias = $Alias
            IPAddress      = $IPAddress
            PrefixLength   = $PrefixLength
        }
        if ($DefaultGateway) { $args.DefaultGateway = $DefaultGateway }
        New-NetIPAddress @args -ErrorAction Stop | Out-Null
        Write-Log "Set $Alias to $IPAddress/$PrefixLength GW=$DefaultGateway"
    } catch {
        Write-Log "Failed to set static IP on $Alias : $($_.Exception.Message)" 3
        throw
    }
}

function Reset-AdapterToDHCP {
    param([Parameter(Mandatory)][string]$Alias)
    try {
        Remove-ExistingIPv4 -Alias $Alias
        Set-NetIPInterface -InterfaceAlias $Alias -Dhcp Enabled -ErrorAction Stop | Out-Null
        Set-DnsClientServerAddress -InterfaceAlias $Alias -ResetServerAddresses -ErrorAction SilentlyContinue
        Write-Log "Reset $Alias to DHCP + cleared DNS"
    } catch {
        Write-Log "Failed to reset $Alias to DHCP: $($_.Exception.Message)" 3
        throw
    }
}

function Test-IPInUse {
    param([Parameter(Mandatory)][string]$IPAddress, [int]$TimeoutSeconds = 1)
    try {
        $pong = Test-Connection -ComputerName $IPAddress -Count 1 -Quiet -TimeoutSeconds $TimeoutSeconds -ErrorAction SilentlyContinue
        if ($pong) { return $true }
        $arp = arp -a | Select-String -SimpleMatch $IPAddress
        return [bool]$arp
    } catch {
        Write-Log "IP availability check error for $IPAddress : $($_.Exception.Message)" 2
        return $true
    }
}

function Ensure-FirewallRule2022 {
    $ruleName = "SSH-2022"
    $rule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
    if (-not $rule) {
        New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Action Allow -Protocol TCP -LocalPort 2022 -Profile Any | Out-Null
        Write-Log "Created firewall rule '$ruleName' (TCP 2022)"
    } else {
        Set-NetFirewallRule -DisplayName $ruleName -Enabled True -Action Allow | Out-Null
        Write-Log "Ensured firewall rule '$ruleName' allows TCP 2022"
    }
}

function Has-RouteTo17219 {
    try {
        $r = Get-NetRoute -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.DestinationPrefix -eq '172.19.0.0/16' -or ($_.DestinationPrefix -like '172.19.*') }
        return [bool]$r
    } catch { return $false }
}
#endregion

#region ===== GUI =====
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form = New-Object System.Windows.Forms.Form
$form.Text = "TCAS / IFE NIC Configurator"
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(680,395)
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)
$form.MaximizeBox = $false
$form.FormBorderStyle = 'FixedDialog'
$form.Topmost = $true

$lblAdapter = New-Object System.Windows.Forms.Label
$lblAdapter.Text = "Select physical Ethernet adapter:"
$lblAdapter.Location = New-Object System.Drawing.Point(20,20)
$lblAdapter.AutoSize = $true
$form.Controls.Add($lblAdapter)

$cmbAdapter = New-Object System.Windows.Forms.ComboBox
$cmbAdapter.DropDownStyle = 'DropDownList'
$cmbAdapter.Location = New-Object System.Drawing.Point(20,45)
$cmbAdapter.Width = 620
$form.Controls.Add($cmbAdapter)

$lblAdapterStatus = New-Object System.Windows.Forms.Label
$lblAdapterStatus.Location = New-Object System.Drawing.Point(20,70)
$lblAdapterStatus.AutoSize = $true
$form.Controls.Add($lblAdapterStatus)

$grpMode = New-Object System.Windows.Forms.GroupBox
$grpMode.Text = "Mode"
$grpMode.Location = New-Object System.Drawing.Point(20,95)
$grpMode.Size = New-Object System.Drawing.Size(280,120)
$form.Controls.Add($grpMode)

$rbTCAS = New-Object System.Windows.Forms.RadioButton
$rbTCAS.Text = "TCAS"
$rbTCAS.Location = New-Object System.Drawing.Point(15,25)
$rbTCAS.Checked = $true
$grpMode.Controls.Add($rbTCAS)

$rbIFE = New-Object System.Windows.Forms.RadioButton
$rbIFE.Text = "IFE"
$rbIFE.Location = New-Object System.Drawing.Point(15,60)
$grpMode.Controls.Add($rbIFE)

$grpIFE = New-Object System.Windows.Forms.GroupBox
$grpIFE.Text = "IFE Address"
$grpIFE.Location = New-Object System.Drawing.Point(320,95)
$grpIFE.Size = New-Object System.Drawing.Size(320,120)
$form.Controls.Add($grpIFE)

$btnFind = New-Object System.Windows.Forms.Button
$btnFind.Text = "Find free IP"
$btnFind.Location = New-Object System.Drawing.Point(15,25)
$btnFind.Size = New-Object System.Drawing.Size(100,30)
$grpIFE.Controls.Add($btnFind)

$lblChosen = New-Object System.Windows.Forms.Label
$lblChosen.Text = "Chosen IP: (none)"
$lblChosen.Location = New-Object System.Drawing.Point(15,70)
$lblChosen.AutoSize = $true
$grpIFE.Controls.Add($lblChosen)

$lblRouteStatus = New-Object System.Windows.Forms.Label
$lblRouteStatus.Location = New-Object System.Drawing.Point(20,220)
$lblRouteStatus.AutoSize = $true
$form.Controls.Add($lblRouteStatus)

$btnApply = New-Object System.Windows.Forms.Button
$btnApply.Text = "Apply"
$btnApply.Location = New-Object System.Drawing.Point(320,230)
$btnApply.Size = New-Object System.Drawing.Size(100,35)
$form.Controls.Add($btnApply)

$btnReset = New-Object System.Windows.Forms.Button
$btnReset.Text = "Reset"
$btnReset.Location = New-Object System.Drawing.Point(440,230)
$btnReset.Size = New-Object System.Drawing.Size(100,35)
$form.Controls.Add($btnReset)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = "Close"
$btnClose.Location = New-Object System.Drawing.Point(560,230)
$btnClose.Size = New-Object System.Drawing.Size(80,35)
$form.Controls.Add($btnClose)

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Multiline = $true
$txtLog.ReadOnly = $true
$txtLog.ScrollBars = 'Vertical'
$txtLog.Location = New-Object System.Drawing.Point(20,280)
$txtLog.Size = New-Object System.Drawing.Size(640,70)
$form.Controls.Add($txtLog)

function Append-UiLog([string]$msg) {
    $ts = Get-Date -Format "HH:mm:ss"
    $txtLog.AppendText("[$ts] $msg`r`n")
}

function Update-IFEEnabled { $grpIFE.Enabled = $rbIFE.Checked }
$rbTCAS.Add_CheckedChanged({ Update-IFEEnabled })
$rbIFE.Add_CheckedChanged({ Update-IFEEnabled })
Update-IFEEnabled

function Update-RouteStatus {
    if (Has-RouteTo17219) {
        $lblRouteStatus.ForeColor = 'Green'
        $lblRouteStatus.Text = "172.19/16 route detected: Yes (will scan for free IPs)"
    } else {
        $lblRouteStatus.ForeColor = 'DarkOrange'
        $lblRouteStatus.Text = "172.19/16 route detected: No (will pick random IP)"
    }
}

$adapters = Get-PhysicalEthernetAdapters
if ($adapters) {
    $adapters | ForEach-Object { $cmbAdapter.Items.Add($_.Name) }
    $cmbAdapter.SelectedIndex = 0
    $lblAdapterStatus.ForeColor = 'Gray'
    $lblAdapterStatus.Text = "Adapters detected: " + ($adapters.Name -join ', ')
} else {
    $lblAdapterStatus.ForeColor = 'Red'
    $lblAdapterStatus.Text = "No physical Ethernet adapters found."
    $grpMode.Enabled = $false
    $grpIFE.Enabled = $false
    $btnApply.Enabled = $false
    $btnReset.Enabled = $false
}
Update-RouteStatus
#endregion

#region ===== Button logic =====
$script:IFE_SelectedIP = $null

function Get-RandomHostIn17219 {
    $rnd = New-Object System.Random
    $x = $rnd.Next(0,256)
    $y = $rnd.Next(10,251)
    return "172.19.$x.$y"
}

function Get-RandomisedOctets {
    $arr = 0..255
    $rand = New-Object System.Random
    ,($arr | Sort-Object { $rand.Next() })
}

function Find-FreeIFEIP {
    if (-not (Has-RouteTo17219)) { return Get-RandomHostIn17219 }
    $thirds = Get-RandomisedOctets
    foreach ($x in $thirds) {
        for ($y = 10; $y -le 250; $y++) {
            $candidate = "172.19.$x.$y"
            if (-not (Test-IPInUse -IPAddress $candidate)) { return $candidate }
        }
    }
    return $null
}

$btnFind.Add_Click({
    Append-UiLog "Searching for IFE IP..."
    Update-RouteStatus
    $ip = Find-FreeIFEIP
    if ($ip) {
        $script:IFE_SelectedIP = $ip
        $lblChosen.Text = "Chosen IP: $ip"
        Append-UiLog "Selected IFE IP: $ip"
    } else {
        Append-UiLog "No free IP found."
    }
})

$btnApply.Add_Click({
    $alias = $cmbAdapter.SelectedItem
    if (-not $alias) { Append-UiLog "Select an adapter first."; return }
    try {
        if ($rbTCAS.Checked) {
            Set-IPv4Static -Alias $alias -IPAddress "192.168.111.200" -PrefixLength 16 -DefaultGateway "192.168.1.1"
            Ensure-FirewallRule2022
            Append-UiLog "TCAS applied. Firewall TCP 2022 open."
        } else {
            if (-not $script:IFE_SelectedIP) { Append-UiLog "Click 'Find free IP' first."; return }
            Set-IPv4Static -Alias $alias -IPAddress $script:IFE_SelectedIP -PrefixLength 16
            Ensure-FirewallRule2022
            Append-UiLog "IFE applied. Firewall TCP 2022 open."
        }
    } catch { Append-UiLog "Apply failed: $($_.Exception.Message)" }
})

$btnReset.Add_Click({
    $alias = $cmbAdapter.SelectedItem
    if (-not $alias) { Append-UiLog "Select an adapter first."; return }
    try {
        Reset-AdapterToDHCP -Alias $alias
        Append-UiLog "Adapter reset to DHCP."
        Update-RouteStatus
    } catch { Append-UiLog "Reset failed: $($_.Exception.Message)" }
})

$btnClose.Add_Click({
    Append-UiLog "User closed configurator."
    Write-Log "User closed configurator."
    $form.Close()
})
#endregion

Append-UiLog "Log file: $script:LogPath"
[void]$form.ShowDialog()
