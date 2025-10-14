<#
.SYNOPSIS
TCAS / IFE NIC configurator (SYSTEM context, fixed layout, Find Free/Random IP for IFE)

.DESCRIPTION
- TCAS: 192.168.111.200/16 + GW 192.168.1.1
- IFE: If a route to 172.19.0.0/16 exists, scan for a free IP; if not, pick a random IP in 172.19.X.Y.
- Opens inbound firewall TCP 2022 ("SSH-2022").
- Reset returns adapter to DHCP.
- CMTrace logging; GUI stays open until closed.
- Adapter discovery result is shown IN-FORM (red on error), no message box.

.NOTES
Author: Martin Smith (Data #3) + ChatGPT
Date: 09/10/2025
Version: 1.5
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
        [ValidateSet(1,2,3)][int]$Severity = 1, # 1=Info, 2=Warning, 3=Error
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
    $exclude = @('virtual','hyper-v','vmware','bluetooth','wi-fi','wifi','wlan','tunnel','wireless','loopback','container','npcap','docker','wsl')
    Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
        Where-Object { $_.HardwareInterface -and $_.Status -ne 'Disabled' } |
        Where-Object { $n=$_.Name.ToLower(); -not ($exclude | Where-Object { $n -like "*$_*" }) } |
        Sort-Object ifIndex
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
        $null = Test-Connection -ComputerName $IPAddress -Count 1 -Quiet -TimeoutSeconds $TimeoutSeconds -ErrorAction SilentlyContinue
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
        try { Set-NetFirewallPortFilter -AssociatedNetFirewallRule $rule -Protocol TCP -LocalPort 2022 -ErrorAction SilentlyContinue } catch { }
        Write-Log "Ensured firewall rule '$ruleName' allows TCP 2022"
    }
}

# Route detection
function Has-RouteTo17219 {
    try {
        $r = Get-NetRoute -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.DestinationPrefix -eq '172.19.0.0/16' -or ($_.DestinationPrefix -like '172.19.*') }
        return [bool]$r
    } catch { return $false }
}
#endregion

#region ===== GUI (fixed layout; no octet inputs) =====
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form = New-Object System.Windows.Forms.Form
$form.Text = "TCAS / IFE NIC Configurator"
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(576,365)
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)
$form.MaximizeBox = $false
$form.FormBorderStyle = 'FixedDialog'
$form.Topmost = $true

# Adapter selection
$lblAdapter = New-Object System.Windows.Forms.Label
$lblAdapter.Text = "Select physical Ethernet adapter:"
$lblAdapter.Location = New-Object System.Drawing.Point(20,20)
$lblAdapter.AutoSize = $true
$form.Controls.Add($lblAdapter)

$cmbAdapter = New-Object System.Windows.Forms.ComboBox
$cmbAdapter.DropDownStyle = 'DropDownList'
$cmbAdapter.Location = New-Object System.Drawing.Point(20,45)
$cmbAdapter.Width = 520
$form.Controls.Add($cmbAdapter)

# NEW: inline adapter discovery status (red on error)
$lblAdapterStatus = New-Object System.Windows.Forms.Label
$lblAdapterStatus.Text = ""
$lblAdapterStatus.Location = New-Object System.Drawing.Point(20,70)
$lblAdapterStatus.AutoSize = $true
$lblAdapterStatus.ForeColor = [System.Drawing.Color]::Gray
$form.Controls.Add($lblAdapterStatus)

# Mode group
$grpMode = New-Object System.Windows.Forms.GroupBox
$grpMode.Text = "Mode"
$grpMode.Location = New-Object System.Drawing.Point(20,95)
$grpMode.Size = New-Object System.Drawing.Size(270,110)
$form.Controls.Add($grpMode)

$rbTCAS = New-Object System.Windows.Forms.RadioButton
$rbTCAS.Text = "TCAS"
$rbTCAS.Location = New-Object System.Drawing.Point(15,25)
$rbTCAS.AutoSize = $true
$rbTCAS.Checked = $true
$grpMode.Controls.Add($rbTCAS)

$rbIFE = New-Object System.Windows.Forms.RadioButton
$rbIFE.Text = "IFE"
$rbIFE.Location = New-Object System.Drawing.Point(15,60)
$rbIFE.AutoSize = $true
$grpMode.Controls.Add($rbIFE)

# IFE helpers
$grpIFE = New-Object System.Windows.Forms.GroupBox
$grpIFE.Text = "IFE Address"
$grpIFE.Location = New-Object System.Drawing.Point(310,95)
$grpIFE.Size = New-Object System.Drawing.Size(230,110)
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

# Action buttons
$btnApply = New-Object System.Windows.Forms.Button
$btnApply.Text = "Apply"
$btnApply.Location = New-Object System.Drawing.Point(310,230)
$btnApply.Size = New-Object System.Drawing.Size(100,35)
$form.Controls.Add($btnApply)

$btnReset = New-Object System.Windows.Forms.Button
$btnReset.Text = "Reset"
$btnReset.Location = New-Object System.Drawing.Point(420,230)
$btnReset.Size = New-Object System.Drawing.Size(100,35)
$form.Controls.Add($btnReset)

# Log output
$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Multiline = $true
$txtLog.ReadOnly = $true
$txtLog.ScrollBars = 'Vertical'
$txtLog.Location = New-Object System.Drawing.Point(20,280)
$txtLog.Size = New-Object System.Drawing.Size(520,50)
$form.Controls.Add($txtLog)

function Append-UiLog([string]$msg) {
    $ts = Get-Date -Format "HH:mm:ss"
    $txtLog.AppendText("[$ts] $msg`r`n")
}

function Update-IFEEnabled { $grpIFE.Enabled = $rbIFE.Checked }
$rbTCAS.Add_CheckedChanged({ Update-IFEEnabled })
$rbIFE.Add_CheckedChanged({ Update-IFEEnabled })
Update-IFEEnabled

# Populate adapters and update inline status (no popups)
$adapters = Get-PhysicalEthernetAdapters
if ($adapters -and $adapters.Count -gt 0) {
    $adapters | ForEach-Object { [void]$cmbAdapter.Items.Add($_.Name) }
    $cmbAdapter.SelectedIndex = 0
    $lblAdapterStatus.ForeColor = [System.Drawing.Color]::Gray
    $lblAdapterStatus.Text = "Adapters detected: " + ($adapters.Name -join ', ')
    $grpMode.Enabled = $true; $grpIFE.Enabled = $true; $btnApply.Enabled = $true; $btnReset.Enabled = $true
    Append-UiLog ("Adapters found: " + ($adapters.Name -join ', '))
} else {
    $lblAdapterStatus.ForeColor = [System.Drawing.Color]::Red
    $lblAdapterStatus.Text = "No suitable physical Ethernet adapters found."
    $grpMode.Enabled = $false; $grpIFE.Enabled = $false; $btnApply.Enabled = $false; $btnReset.Enabled = $false
    Write-Log "No physical Ethernet adapters found" 3
    Append-UiLog "No suitable adapters."
}
#endregion

#region ===== IFE IP Finder =====
$script:IFE_SelectedIP = $null

function Get-RandomHostIn17219 {
    $rnd = New-Object System.Random
    $x = $rnd.Next(0,256)
    $y = $rnd.Next(10,251)  # 10..250 inclusive
    return "172.19.$x.$y"
}

function Get-RandomisedOctets {
    $arr = 0..255
    $rand = New-Object System.Random
    ,($arr | Sort-Object { $rand.Next() })
}

function Find-FreeIFEIP {
    if (-not (Has-RouteTo17219)) {
        Write-Log "No route to 172.19.0.0/16 detected; selecting random IP from range"
        return Get-RandomHostIn17219
    }
    # Route exists: try to find an actually free address
    $thirds = Get-RandomisedOctets
    foreach ($x in $thirds) {
        for ($y = 10; $y -le 250; $y++) {
            $candidate = "172.19.$x.$y"
            if (-not (Test-IPInUse -IPAddress $candidate)) {
                return $candidate
            }
        }
    }
    return $null
}

$btnFind.Add_Click({
    try {
        if (-not $cmbAdapter.SelectedItem) { return }
        Append-UiLog "Determining IFE address..."
        $ip = Find-FreeIFEIP
        if (-not $ip) {
            Append-UiLog "No free IP found in 172.19.0.0/16"
            return
        }
        $mode = if (Has-RouteTo17219) { "proposed free" } else { "random (no route)" }
        $res = [System.Windows.Forms.MessageBox]::Show("Use IP $ip for IFE ($mode)?","Confirm IFE IP","OKCancel","Question")
        if ($res -eq 'OK') {
            $script:IFE_SelectedIP = $ip
            $lblChosen.Text = "Chosen IP: $ip"
            Append-UiLog "Selected IFE IP: $ip ($mode)"
        } else {
            Append-UiLog "User cancelled chosen IP: $ip"
        }
    } catch {
        Write-Log "Find free/random IP error: $($_.Exception.Message)" 3
        Append-UiLog "Error finding IP: $($_.Exception.Message)"
    }
})
#endregion

#region ===== Button events =====
$btnApply.Add_Click({
    $alias = $cmbAdapter.SelectedItem
    if (-not $alias) {
        Append-UiLog "Select an adapter first."
        return
    }
    try {
        if ($rbTCAS.Checked) {
            Append-UiLog "Applying TCAS on $alias..."
            Write-Log "Applying TCAS on $alias"
            Set-IPv4Static -Alias $alias -IPAddress "192.168.111.200" -PrefixLength 16 -DefaultGateway "192.168.1.1"
            Ensure-FirewallRule2022
            Append-UiLog "TCAS applied. Firewall TCP 2022 open."
        } else {
            if (-not $script:IFE_SelectedIP) {
                Append-UiLog "Click 'Find free IP' first to choose an IFE address."
                return
            }
            $ip = $script:IFE_SelectedIP
            if (Has-RouteTo17219) {
                Append-UiLog "Verifying $ip is still free..."
                if (Test-IPInUse -IPAddress $ip) {
                    Append-UiLog "$ip now appears in use; please find another."
                    return
                }
            } else {
                Append-UiLog "No route to 172.19.0.0/16; proceeding with selected random IP ($ip)."
                Write-Log "No route present; skipping availability re-check"
            }
            Append-UiLog "Applying IFE ($ip/16) on $alias..."
            Write-Log "Applying IFE on $alias with $ip/16"
            Set-IPv4Static -Alias $alias -IPAddress $ip -PrefixLength 16   # No gateway per spec
            Ensure-FirewallRule2022
            Append-UiLog "IFE applied. Firewall TCP 2022 open."
        }
    } catch {
        Write-Log "Apply failed: $($_.Exception.Message)" 3
        Append-UiLog "Failed: $($_.Exception.Message)"
    }
})

$btnReset.Add_Click({
    $alias = $cmbAdapter.SelectedItem
    if (-not $alias) {
        Append-UiLog "Select an adapter first."
        return
    }
    try {
        Append-UiLog "Resetting $alias to DHCP..."
        Write-Log "Resetting $alias to DHCP"
        Reset-AdapterToDHCP -Alias $alias
        Append-UiLog "Reset complete."
    } catch {
        Write-Log "Reset failed: $($_.Exception.Message)" 3
        Append-UiLog "Reset failed: $($_.Exception.Message)"
    }
})
#endregion

Append-UiLog "Log file: $script:LogPath"

# Keep window open until the user closes it.
[void]$form.ShowDialog()
