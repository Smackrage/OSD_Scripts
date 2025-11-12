<#
.SYNOPSIS
TCAS / IFE NIC configurator 

.DESCRIPTION
- TCAS: 192.168.111.200/16 + GW 192.168.1.1 + DNS 8.8.8.8, 8.8.4.4
- IFE: If route to 172.19/16 exists, scan for a free IP; else pick a random 172.19.X.Y
- IFE (Fixed option): Apply fixed IP/GW/DNS as provided in UI
- Opens inbound firewall TCP 2022 ("SSH-2022")
- Reset returns adapter to DHCP (and DNS reset)
- Adapter list shows only physical Ethernet adapters
- Inline route indicator (shown only when IFE is selected)
- Close button
- Logs to C:\ProgramData\virginaustralia\IPChanger
- If link is down: Retry/Close prompt to “ensure the network cable is plugged into the Laptop and aircraft”
- If adapter already has an IP in the IFE (172.19/16) range, disable the "Find free IP" button
- Subnet shown as dotted-decimal mask (e.g. 255.255.0.0), not just /prefix
- Layout updated: larger dialog, wider groups, wrapped labels, and no clipped text

.NOTES
Author: Martin Smith (Data #3)
Date: 12/11/2025
Version: 2.4
#>

#region ===== CMTrace-compatible logging =====
$script:LogDir = "C:\ProgramData\virginaustralia\IPChanger"
try {
    if (-not (Test-Path $script:LogDir)) { New-Item -Path $script:LogDir -ItemType Directory -Force | Out-Null }
} catch { }
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
    try { $line | Out-File -FilePath $script:LogPath -Encoding default -Append } catch { }
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
            ($_.Name -match 'Ethernet' -or $_.InterfaceDescription -match 'Ethernet')
        } |
        Sort-Object ifIndex

    $exclude = @('virtual','hyper-v','vmware','bluetooth','wi-fi','wifi','wlan','tunnel','wireless','loopback','container','npcap','docker','wsl','remote','rdp','wan')
    $filtered = $adapters | Where-Object {
        $n = $_.Name.ToLower(); $d = $_.InterfaceDescription.ToLower()
        -not ($exclude | Where-Object { $n -like "*$_*" -or $d -like "*$_*" })
    }
    Write-Log "Found $($filtered.Count) physical Ethernet adapter(s)."
    return $filtered
}

function Remove-ExistingIPv4 { param([Parameter(Mandatory)][string]$Alias)
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
    param([Parameter(Mandatory)][string]$Alias,[Parameter(Mandatory)][string]$IPAddress,[Parameter(Mandatory)][int]$PrefixLength,[string]$DefaultGateway)
    Remove-ExistingIPv4 -Alias $Alias
    try {
        $args = @{ InterfaceAlias = $Alias; IPAddress = $IPAddress; PrefixLength = $PrefixLength }
        if ($DefaultGateway) { $args.DefaultGateway = $DefaultGateway }
        New-NetIPAddress @args -ErrorAction Stop | Out-Null
        Write-Log "Set $Alias to $IPAddress/$PrefixLength GW=$DefaultGateway"
    } catch {
        Write-Log "Failed to set static IP on $Alias : $($_.Exception.Message)" 3
        throw
    }
}

function Reset-AdapterToDHCP { param([Parameter(Mandatory)][string]$Alias)
    try {
        Remove-ExistingIPv4 -Alias $Alias
        Set-NetIPInterface -InterfaceAlias $Alias -Dhcp Enabled -ErrorAction Stop | Out-Null
        Set-DnsClientServerAddress -InterfaceAlias $Alias -ResetServerAddresses -ErrorAction SilentlyContinue
        Write-Log "Reset $Alias to DHCP + cleared DNS"
    } catch { Write-Log "Failed to reset $Alias to DHCP: $($_.Exception.Message)" 3; throw }
}

function Test-IPInUse { param([Parameter(Mandatory)][string]$IPAddress,[int]$TimeoutSeconds=1)
    try {
        $pong = Test-Connection -ComputerName $IPAddress -Count 1 -Quiet -TimeoutSeconds $TimeoutSeconds -ErrorAction SilentlyContinue
        if ($pong) { return $true }
        $arp = arp -a | Select-String -SimpleMatch $IPAddress
        return [bool]$arp
    } catch { Write-Log "IP availability check error for $IPAddress : $($_.Exception.Message)" 2; return $true }
}

function Ensure-FirewallRule2022 {
    $ruleName = "SSH-2022"
    $rule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
    if (-not $rule) { New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Action Allow -Protocol TCP -LocalPort 2022 -Profile Any | Out-Null; Write-Log "Created firewall rule '$ruleName' (TCP 2022)" }
    else { Set-NetFirewallRule -DisplayName $ruleName -Enabled True -Action Allow | Out-Null; Write-Log "Ensured firewall rule '$ruleName' allows TCP 2022" }
}

function Has-RouteTo17219 {
    try {
        $r = Get-NetRoute -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.DestinationPrefix -eq '172.19.0.0/16' -or ($_.DestinationPrefix -like '172.19.*') }
        return [bool]$r
    } catch { return $false }
}

# Convert a prefix length (e.g. 16) to dotted-decimal subnet mask (e.g. 255.255.0.0)
function Convert-PrefixToMask {
    param([Parameter(Mandatory)][ValidateRange(0,32)][int]$PrefixLength)
    $mask = [uint32]0
    if ($PrefixLength -gt 0) { $mask = 0xFFFFFFFF -shl (32 - $PrefixLength) }
    $bytes = [BitConverter]::GetBytes($mask -band 0xFFFFFFFF)
    if ([BitConverter]::IsLittleEndian) { [Array]::Reverse($bytes) }
    return ([System.Net.IPAddress]::new($bytes)).ToString()
}

function Test-IsIFERangeIP {
    param([Parameter(Mandatory)][string]$IPAddress)
    return ($IPAddress -match '^172\.19\.\d{1,3}\.\d{1,3}$')
}

function Get-AdapterIPv4Summary {
    param([Parameter(Mandatory)][string]$Alias)
    $ip = Get-NetIPAddress -InterfaceAlias $Alias -AddressFamily IPv4 -ErrorAction SilentlyContinue | Sort-Object -Property SkipAsSource | Select-Object -First 1
    $gw = Get-NetRoute -InterfaceAlias $Alias -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object -Property RouteMetric | Select-Object -First 1
    $dns = Get-DnsClientServerAddress -InterfaceAlias $Alias -AddressFamily IPv4 -ErrorAction SilentlyContinue
    $mask = if ($ip.PrefixLength) { Convert-PrefixToMask -PrefixLength $ip.PrefixLength } else { $null }
    [pscustomobject]@{
        IP            = $ip.IPAddress
        PrefixLength  = $ip.PrefixLength
        SubnetMask    = $mask
        Gateway       = $gw.NextHop
        DNSServers    = ($dns.ServerAddresses -join ', ')
        IsIFE         = if ($ip.IPAddress) { Test-IsIFERangeIP -IPAddress $ip.IPAddress } else { $false }
    }
}
#endregion

#region ===== GUI =====
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- Larger, roomier dialog ---
$form = New-Object System.Windows.Forms.Form
$form.Text = "TCAS / IFE NIC Configurator"
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(740,470)   # was ~680x425
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)
$form.MaximizeBox = $false
$form.FormBorderStyle = 'FixedDialog'
$form.Topmost = $true

$marginL = 20
$col1X  = 20
$col2X  = 260
$col3X  = 500

$lblAdapter = New-Object System.Windows.Forms.Label
$lblAdapter.Text = "Select physical Ethernet adapter:"
$lblAdapter.Location = New-Object System.Drawing.Point($marginL,20)
$lblAdapter.AutoSize = $true
$form.Controls.Add($lblAdapter)

$cmbAdapter = New-Object System.Windows.Forms.ComboBox
$cmbAdapter.DropDownStyle = 'DropDownList'
$cmbAdapter.Location = New-Object System.Drawing.Point($marginL,45)
$cmbAdapter.Width = 680
$form.Controls.Add($cmbAdapter)

$lblAdapterStatus = New-Object System.Windows.Forms.Label
$lblAdapterStatus.Location = New-Object System.Drawing.Point($marginL,70)
$lblAdapterStatus.AutoSize = $true
$form.Controls.Add($lblAdapterStatus)

# Group 1: Mode (wider/taller)
$grpMode = New-Object System.Windows.Forms.GroupBox
$grpMode.Text = "Mode"
$grpMode.Location = New-Object System.Drawing.Point($col1X,95)
$grpMode.Size = New-Object System.Drawing.Size(220,120)
$form.Controls.Add($grpMode)

$rbTCAS = New-Object System.Windows.Forms.RadioButton
$rbTCAS.Text = "TCAS"
$rbTCAS.Location = New-Object System.Drawing.Point(15,25)
$rbTCAS.Checked = $true
$grpMode.Controls.Add($rbTCAS)

$rbIFE = New-Object System.Windows.Forms.RadioButton
$rbIFE.Text = "IFE"
$rbIFE.Location = New-Object System.Drawing.Point(15,55)
$grpMode.Controls.Add($rbIFE)

# Group 2: IFE Address (wider/taller)
$grpIFE = New-Object System.Windows.Forms.GroupBox
$grpIFE.Text = "IFE Address"
$grpIFE.Location = New-Object System.Drawing.Point($col2X,95)
$grpIFE.Size = New-Object System.Drawing.Size(220,190)
$form.Controls.Add($grpIFE)

$btnFind = New-Object System.Windows.Forms.Button
$btnFind.Text = "Find free IP"
$btnFind.Location = New-Object System.Drawing.Point(15,25)
$btnFind.Size = New-Object System.Drawing.Size(110,30)
$grpIFE.Controls.Add($btnFind)

# Chosen label: fixed width with ellipsis to avoid clipping
$lblChosen = New-Object System.Windows.Forms.Label
$lblChosen.Text = "Chosen IP: (none)"
$lblChosen.Location = New-Object System.Drawing.Point(15,60)
$lblChosen.AutoSize = $false
$lblChosen.AutoEllipsis = $true
$lblChosen.Size = New-Object System.Drawing.Size(190,20)
$grpIFE.Controls.Add($lblChosen)

# Fixed IFE option (summary wraps neatly)
$chkFixed = New-Object System.Windows.Forms.CheckBox
$chkFixed.Text = "Use fixed IFE IP"
$chkFixed.Location = New-Object System.Drawing.Point(15,85)
$chkFixed.AutoSize = $true
$grpIFE.Controls.Add($chkFixed)

$lblFixedSummary = New-Object System.Windows.Forms.Label
$lblFixedSummary.Location = New-Object System.Drawing.Point(32,108)
$lblFixedSummary.MaximumSize = New-Object System.Drawing.Size(175,0)   # wrap to fit
$lblFixedSummary.AutoSize = $true
$lblFixedSummary.Text = "IP 172.19.134.100`r`nMask 255.255.0.0`r`nGW 172.19.134.10`r`nDNS 172.19.134.10"
$grpIFE.Controls.Add($lblFixedSummary)

# Group 3: Current Adapter IP (wider to fit long DNS)
$grpStatus = New-Object System.Windows.Forms.GroupBox
$grpStatus.Text = "Current Adapter IP"
$grpStatus.Location = New-Object System.Drawing.Point($col3X,95)
$grpStatus.Size = New-Object System.Drawing.Size(220,120)
$form.Controls.Add($grpStatus)

$lblCurIP = New-Object System.Windows.Forms.Label
$lblCurIP.Location = New-Object System.Drawing.Point(10,22)
$lblCurIP.Size = New-Object System.Drawing.Size(200,18)
$grpStatus.Controls.Add($lblCurIP)

$lblCurSubnet = New-Object System.Windows.Forms.Label
$lblCurSubnet.Location = New-Object System.Drawing.Point(10,42)
$lblCurSubnet.Size = New-Object System.Drawing.Size(200,18)
$grpStatus.Controls.Add($lblCurSubnet)

$lblCurGW = New-Object System.Windows.Forms.Label
$lblCurGW.Location = New-Object System.Drawing.Point(10,62)
$lblCurGW.Size = New-Object System.Drawing.Size(200,18)
$grpStatus.Controls.Add($lblCurGW)

$lblCurDNS = New-Object System.Windows.Forms.Label
$lblCurDNS.Location = New-Object System.Drawing.Point(10,82)
$lblCurDNS.Size = New-Object System.Drawing.Size(200,18)
$grpStatus.Controls.Add($lblCurDNS)

# Route status (wrap across form; never clipped)
$lblRouteStatus = New-Object System.Windows.Forms.Label
$lblRouteStatus.Location = New-Object System.Drawing.Point($marginL,310)
$lblRouteStatus.MaximumSize = New-Object System.Drawing.Size(700,0)   # allow wrapping
$lblRouteStatus.AutoSize = $true
$lblRouteStatus.Visible = $false
$form.Controls.Add($lblRouteStatus)

# Buttons (repositioned lower, spaced)
$btnApply = New-Object System.Windows.Forms.Button
$btnApply.Text = "Apply"
$btnApply.Location = New-Object System.Drawing.Point(320,300)
$btnApply.Size = New-Object System.Drawing.Size(100,35)
$form.Controls.Add($btnApply)

$btnReset = New-Object System.Windows.Forms.Button
$btnReset.Text = "Reset"
$btnReset.Location = New-Object System.Drawing.Point(440,300)
$btnReset.Size = New-Object System.Drawing.Size(100,35)
$form.Controls.Add($btnReset)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = "Close"
$btnClose.Location = New-Object System.Drawing.Point(560,300)
$btnClose.Size = New-Object System.Drawing.Size(100,35)
$form.Controls.Add($btnClose)

# Log (made taller and wider)
$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Multiline = $true
$txtLog.ReadOnly = $true
$txtLog.ScrollBars = 'Vertical'
$txtLog.Location = New-Object System.Drawing.Point($marginL,345)
$txtLog.Size = New-Object System.Drawing.Size(700,80)
$form.Controls.Add($txtLog)

function Append-UiLog([string]$msg) { $ts = Get-Date -Format "HH:mm:ss"; $txtLog.AppendText("[$ts] $msg`r`n") }
#endregion

#region ===== UI behaviour =====
function Update-IFEEnabled { $grpIFE.Enabled = $rbIFE.Checked }

function Update-RouteStatus {
    if (-not $rbIFE.Checked) { $lblRouteStatus.Visible = $false; return }
    $lblRouteStatus.Visible = $true
    if (Has-RouteTo17219) { $lblRouteStatus.ForeColor = 'Green'; $lblRouteStatus.Text = "172.19/16 route detected: Yes (will scan for free IPs)" }
    else { $lblRouteStatus.ForeColor = 'DarkOrange'; $lblRouteStatus.Text = "172.19/16 route detected: No (will pick random IP)" }
}

# Fixed IFE settings
$FixedIFE = [pscustomobject]@{
    IP           = "172.19.134.100"
    PrefixLength = 16             # 255.255.0.0
    SubnetMask   = "255.255.0.0"
    Gateway      = "172.19.134.10"
    Dns          = @("172.19.134.10")
}

function Test-IsIFERangeIP { param([string]$IPAddress) return ($IPAddress -match '^172\.19\.\d{1,3}\.\d{1,3}$') }

function Get-AdapterIPv4Summary {
    param([Parameter(Mandatory)][string]$Alias)
    $ip = Get-NetIPAddress -InterfaceAlias $Alias -AddressFamily IPv4 -ErrorAction SilentlyContinue | Sort-Object -Property SkipAsSource | Select-Object -First 1
    $gw = Get-NetRoute -InterfaceAlias $Alias -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object -Property RouteMetric | Select-Object -First 1
    $dns = Get-DnsClientServerAddress -InterfaceAlias $Alias -AddressFamily IPv4 -ErrorAction SilentlyContinue
    $mask = if ($ip.PrefixLength) { Convert-PrefixToMask -PrefixLength $ip.PrefixLength } else { $null }
    [pscustomobject]@{
        IP            = $ip.IPAddress
        PrefixLength  = $ip.PrefixLength
        SubnetMask    = $mask
        Gateway       = $gw.NextHop
        DNSServers    = ($dns.ServerAddresses -join ', ')
        IsIFE         = if ($ip.IPAddress) { Test-IsIFERangeIP -IPAddress $ip.IPAddress } else { $false }
    }
}

function Refresh-AdapterStatusUI {
    $alias = $cmbAdapter.SelectedItem
    if (-not $alias) {
        $lblCurIP.Text = "IP: -"
        $lblCurSubnet.Text = "Subnet: -"
        $lblCurGW.Text = "GW: -"
        $lblCurDNS.Text = "DNS: -"
        return
    }
    $s = Get-AdapterIPv4Summary -Alias $alias
    $lblCurIP.Text     = "IP: " + ($(if ($s.IP) { $s.IP } else { '-' }))
    $lblCurSubnet.Text = "Subnet: " + ($(if ($s.SubnetMask) { $s.SubnetMask } else { '-' }))
    $lblCurGW.Text     = "GW: " + ($(if ($s.Gateway) { $s.Gateway } else { '-' }))
    $lblCurDNS.Text    = "DNS: " + ($(if ($s.DNSServers) { $s.DNSServers } else { '-' }))
    Update-IFEScanAvailability
}

function Update-IFEScanAvailability {
    $alias = $cmbAdapter.SelectedItem
    if (-not $alias) { $btnFind.Enabled = $false; return }
    $s = Get-AdapterIPv4Summary -Alias $alias
    if ($s.IsIFE -or $chkFixed.Checked) {
        $btnFind.Enabled = $false
        if ($chkFixed.Checked) {
            $lblChosen.Text = "Chosen IP: (fixed $($FixedIFE.IP))"
        } elseif ($s.IsIFE) {
            $lblChosen.Text = "Chosen IP: (adapter already in IFE range)"
        }
    } else {
        $btnFind.Enabled = $true
        if ($script:IFE_SelectedIP) { $lblChosen.Text = "Chosen IP: $script:IFE_SelectedIP" } else { $lblChosen.Text = "Chosen IP: (none)" }
    }
}
#endregion

#region ===== IFE finder & actions =====
$script:IFE_SelectedIP = $null
function Get-RandomHostIn17219 { $rnd = New-Object System.Random; $x=$rnd.Next(0,256); $y=$rnd.Next(10,251); return "172.19.$x.$y" }
function Get-RandomisedOctets { $arr=0..255; $rand=New-Object System.Random; ,($arr | Sort-Object { $rand.Next() }) }
function Has-RouteTo17219 {
    try {
        $r = Get-NetRoute -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.DestinationPrefix -eq '172.19.0.0/16' -or ($_.DestinationPrefix -like '172.19.*') }
        return [bool]$r
    } catch { return $false }
}
function Find-FreeIFEIP {
    if (-not (Has-RouteTo17219)) { return Get-RandomHostIn17219 }
    $thirds = Get-RandomisedOctets
    foreach ($x in $thirds) { for ($y=10; $y -le 250; $y++) { $candidate="172.19.$x.$y"; if (-not (Test-IPInUse -IPAddress $candidate)) { return $candidate } } }
    return $null
}

$chkFixed.Add_CheckedChanged({ Update-IFEScanAvailability })
$rbTCAS.Add_CheckedChanged({ Update-IFEEnabled; Update-RouteStatus; Update-IFEScanAvailability })
$rbIFE.Add_CheckedChanged({ Update-IFEEnabled; Update-RouteStatus; Update-IFEScanAvailability })

$btnFind.Add_Click({
    if ($chkFixed.Checked) { return }
    $alias = $cmbAdapter.SelectedItem
    if (-not $alias) { Append-UiLog "Select an adapter first."; return }
    Append-UiLog "Searching for IFE IP..."
    Update-RouteStatus
    try {
        $ip = Find-FreeIFEIP
        if ($ip) { $script:IFE_SelectedIP = $ip; $lblChosen.Text = "Chosen IP: $ip"; Append-UiLog "Selected IFE IP: $ip" }
        else { Append-UiLog "No free IP found." }
        Refresh-AdapterStatusUI
    } catch {
        $msg = $_.Exception.Message
        Write-Log "IFE find failed: $msg" 3
        Append-UiLog "Error: $msg"
    }
})
#endregion

#region ===== Populate adapters =====
$adapters = Get-PhysicalEthernetAdapters
if ($adapters) {
    $adapters | ForEach-Object { $cmbAdapter.Items.Add($_.Name) }
    $cmbAdapter.SelectedIndex = 0
    $lblAdapterStatus.ForeColor = 'Gray'
    $lblAdapterStatus.Text = "Adapters detected: " + ($adapters.Name -join ', ')
} else {
    $lblAdapterStatus.ForeColor = 'Red'
    $lblAdapterStatus.Text = "No physical Ethernet adapters found."
    $grpMode.Enabled = $false; $grpIFE.Enabled = $false; $btnApply.Enabled = $false; $btnReset.Enabled = $false
}
$cmbAdapter.Add_SelectedIndexChanged({ Refresh-AdapterStatusUI })
Update-IFEEnabled
Update-RouteStatus
Refresh-AdapterStatusUI
#endregion

#region ===== Apply / Reset / Close =====
$btnApply.Add_Click({
    $alias = $cmbAdapter.SelectedItem
    if (-not $alias) { Append-UiLog "Select an adapter first."; return }
    try {
        if ($rbTCAS.Checked) {
            Append-UiLog "Applying TCAS on $alias..."
            Set-IPv4Static -Alias $alias -IPAddress "192.168.111.200" -PrefixLength 16 -DefaultGateway "192.168.1.1"
            try {
                Set-DnsClientServerAddress -InterfaceAlias $alias -ServerAddresses @("8.8.8.8","8.8.4.4") -ErrorAction Stop
                Write-Log "Set DNS on $alias to 8.8.8.8, 8.8.4.4"; Append-UiLog "DNS set to 8.8.8.8, 8.8.4.4"
            } catch { Write-Log "Failed to set DNS on $alias : $($_.Exception.Message)" 2; Append-UiLog "Warning: failed to set DNS ($($_.Exception.Message))" }
        } else {
            if ($chkFixed.Checked) {
                Append-UiLog "Applying FIXED IFE on $alias..."
                Set-IPv4Static -Alias $alias -IPAddress $FixedIFE.IP -PrefixLength $FixedIFE.PrefixLength -DefaultGateway $FixedIFE.Gateway
                try {
                    Set-DnsClientServerAddress -InterfaceAlias $alias -ServerAddresses $FixedIFE.Dns -ErrorAction Stop
                    Write-Log "Set DNS on $alias to $($FixedIFE.Dns -join ', ')"; Append-UiLog "DNS set to $($FixedIFE.Dns -join ', ')"
                } catch { Write-Log "Failed to set DNS on $alias : $($_.Exception.Message)" 2; Append-UiLog "Warning: failed to set DNS ($($_.Exception.Message))" }
                Ensure-FirewallRule2022
                Append-UiLog "Fixed IFE applied. Firewall TCP 2022 open."
            } else {
                if (-not $script:IFE_SelectedIP) { Append-UiLog "Click 'Find free IP' first or tick 'Use fixed IFE IP'."; return }
                Append-UiLog "Applying IFE on $alias..."
                Set-IPv4Static -Alias $alias -IPAddress $script:IFE_SelectedIP -PrefixLength 16
                Ensure-FirewallRule2022
                Append-UiLog "IFE applied. Firewall TCP 2022 open."
            }
        }
        Update-RouteStatus
        Refresh-AdapterStatusUI
    } catch {
        $msg = $_.Exception.Message
        Write-Log "Apply failed: $msg" 3
        Append-UiLog "Apply failed: $msg"
        Refresh-AdapterStatusUI
    }
})

$btnReset.Add_Click({
    $alias = $cmbAdapter.SelectedItem
    if (-not $alias) { Append-UiLog "Select an adapter first."; return }
    try {
        Reset-AdapterToDHCP -Alias $alias
        Append-UiLog "Adapter reset to DHCP."
        Update-RouteStatus
        $script:IFE_SelectedIP = $null
        Refresh-AdapterStatusUI
    } catch { Append-UiLog "Reset failed: $($_.Exception.Message)"; Refresh-AdapterStatusUI }
})

$btnClose.Add_Click({ Append-UiLog "User closed configurator."; Write-Log "User closed configurator."; $form.Close() })
#endregion

Append-UiLog "Log file: $script:LogPath"
[void]$form.ShowDialog()
