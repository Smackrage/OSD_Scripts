<#
.SYNOPSIS
Prompts the operator in WinPE or Full OS to select whether the device is a Shared PC or a Non-Shared PC.

.DESCRIPTION
Displays a GUI with radio button options for Shared or Non-Shared devices, preselecting Non-Shared as the default.
User can choose and press OK to continue immediately. If no selection is made within 60 seconds, the UI will auto close
and Non-Shared will be used. The final selection is written to the Task Sequence variable 'PCType', and a CMTrace-compatible
log file is created in the same location as smsts.log.

.NOTES
Author: Martin Smith (Data #3)
Date: 10/12/2025
Version: 1.2
#>

# Get TS Environment
try {
    $TSEnv = New-Object -ComObject Microsoft.SMS.TSEnvironment
    $tsDetected = $true
} catch {
    $tsDetected = $false
}

# Resolve Log Path (same folder as smsts.log if available)
if ($tsDetected -and $TSEnv.Value("_SMSTSLogPath")) {
    $LogPath = $TSEnv.Value("_SMSTSLogPath")
} elseif (Test-Path "C:\Windows\CCM\Logs") {
    $LogPath = "C:\Windows\CCM\Logs"
} else {
    $LogPath = "C:\Windows\Temp"
}

New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
$LogFile = Join-Path $LogPath "PCTypeSelection.log"

function Write-Log {
    param([string]$Message)
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff")
    $formatted = "$timestamp PCTypeSelection: $Message"
    Write-Output $formatted
    Add-Content -Path $LogFile -Value $formatted
}

Write-Log "Logging started at $LogFile"
Write-Log "Task Sequence Environment Detected: $tsDetected"

# Default value
$script:PCType = "NonShared"
Write-Log "Default PCType set to NonShared"

# Create UI
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form = New-Object System.Windows.Forms.Form
$form.Text = "PC Usage Type"
$form.Width = 350
$form.Height = 230
$form.StartPosition = "CenterScreen"
$form.TopMost = $true

# Instruction Text
$label = New-Object System.Windows.Forms.Label
$label.Text = "Select Shared PC for devices being used in lounges, hangers,`n"
$label.Text += "or any other device which multiple users will log into.`n"
$label.Text += "`n"
$label.Text += "This option is designed for multi-user environments."
$label.AutoSize = $false
$label.Left = 20
$label.Top = 20
$label.Width = 300   # trimmed to fit inside 350px form
$label.Height = 70
$label.TextAlign = 'TopLeft'
$form.Controls.Add($label)

# Radio Buttons (side-by-side)
$rbNonShared = New-Object System.Windows.Forms.RadioButton
$rbNonShared.Text = "Non-Shared PC"
$rbNonShared.Left = 40
$rbNonShared.Top = 100
$rbNonShared.Checked = $true

$rbShared = New-Object System.Windows.Forms.RadioButton
$rbShared.Text = "Shared PC"
$rbShared.Left = 200
$rbShared.Top = 100

$form.Controls.Add($rbNonShared)
$form.Controls.Add($rbShared)

# OK Button
$okButton = New-Object System.Windows.Forms.Button
$okButton.Text = "OK"
$okButton.Width = 80
$okButton.Height = 30
$okButton.Left = 120
$okButton.Top = 140
$okButton.Add_Click({
    if ($rbShared.Checked) {
        $script:PCType = "Shared"
    } else {
        $script:PCType = "NonShared"
    }
    Write-Log "User pressed OK. Selection: $script:PCType"
    $form.Tag = "UserClicked"
    $form.Close()
})
$form.Controls.Add($okButton)

# Show form non-modally and handle our own timeout loop
$timeoutSeconds = 60
$endTime = (Get-Date).AddSeconds($timeoutSeconds)

Write-Log "Displaying UI with $timeoutSeconds second timeout."
$form.Show()

while ($form.Visible -and (Get-Date) -lt $endTime) {
    $remaining = [int]([Math]::Ceiling(($endTime - (Get-Date)).TotalSeconds))
    if ($remaining -lt 0) { $remaining = 0 }
    $form.Text = "PC Usage Type)" # (Closing in $remaining seconds)"
    [System.Windows.Forms.Application]::DoEvents()
    Start-Sleep -Milliseconds 250
}

# If still visible after timeout, close and keep default
if ($form.Visible) {
    Write-Log "Timeout reached. Defaulting to NonShared."
    $script:PCType = "NonShared"
    $form.Tag = "Timeout"
    $form.Close()
}

Write-Log "Final PCType value: $script:PCType"

# Write TS Variable
if ($tsDetected) {
    $TSEnv.Value("PCType") = $script:PCType
    Write-Log "PCType stored in Task Sequence as '$script:PCType'"
} else {
    Write-Log "No Task Sequence environment found. Variable not stored."
}

Write-Log "Script complete."
