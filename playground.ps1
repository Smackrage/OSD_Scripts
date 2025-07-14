<#
.SYNOPSIS
Displays a dropdown menu for selecting an option and sets corresponding Task Sequence variables.

.DESCRIPTION
This script prompts the user to select an image type and automatically closes after 60 seconds.
If no selection is made, the default option "Option 1 - General Maintenance Build" is chosen.
Additional explanatory text and bullet-style dashes are shown below the dropdown.

.NOTES
Author: Marty Smith (Data #3)
Date:   25/06/2025
Version:1.07
#>

# Relaunch in STA if needed
if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne "STA") {
    Start-Process -FilePath "powershell.exe" `
                  -ArgumentList "-STA -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" `
                  -Wait
    Exit
}

# Close TS progress UI
try {
    (New-Object -ComObject Microsoft.SMS.TS.TSProgressUI).CloseProgressDialog()
} catch {}

# Popup notice
try {
    (New-Object -ComObject WScript.Shell).Popup(
        "Please select an image type in the upcoming prompt.", 2,
        "Task Sequence Notification", 0x40
    )
} catch {}

# Load WinForms
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Bring window to front helper
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Foreground {
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
}
"@

# Create the form (taller to fit extra text)
$Form = New-Object System.Windows.Forms.Form
$Form.Text           = "Select Deployment Option"
$Form.Size           = New-Object System.Drawing.Size(300, 250)
$Form.StartPosition  = "CenterScreen"
$Form.TopMost        = $true

# Description label
$Label = New-Object System.Windows.Forms.Label
$Label.Location     = New-Object System.Drawing.Point(20, 10)
$Label.Size         = New-Object System.Drawing.Size(280, 30)
$Label.Text         = "Please select the appropriate deployment option:"
$Label.TextAlign    = 'MiddleLeft'
$Label.AutoSize     = $false
$Form.Controls.Add($Label)

# Dropdown menu
$Dropdown = New-Object System.Windows.Forms.ComboBox
$Dropdown.Location      = New-Object System.Drawing.Point(60, 50)
$Dropdown.Size          = New-Object System.Drawing.Size(200, 22)
$Dropdown.DropDownStyle = "DropDownList"
                "1 - CABS Device",
                "2 - Generic Display Device",
                "3 - Flight Explorer Display Device",
                "4 - GTRAX Device",
                "5 - PSB Device",
                "6 - Kiosk Web Device",
                "7 - Training Device",
                "8 - CCTV Device" |
    ForEach-Object { $Dropdown.Items.Add($_) }
$Dropdown.SelectedIndex = 0
$Form.Controls.Add($Dropdown)

# OK button
$OKButton = New-Object System.Windows.Forms.Button
$OKButton.Location     = New-Object System.Drawing.Point(60, 85)
$OKButton.Size         = New-Object System.Drawing.Size(200, 30)
$OKButton.Text         = "OK"
$OKButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
$Form.Controls.Add($OKButton)

# ——— Explanatory text below the dropdown ———

# “NOTE:” on its own centred line, twice as large
$InfoNote = New-Object System.Windows.Forms.Label
$InfoNote.AutoSize   = $false
$InfoNote.Size       = [System.Drawing.Size]::new($Form.ClientSize.Width - 40, 30)   # leave 20px margin each side
$InfoNote.Location   = [System.Drawing.Point]::new(20, 125)
$InfoNote.Text       = "NOTE:"
$InfoNote.Font       = New-Object System.Drawing.Font(
                         $Form.Font.FontFamily,
                         ($Form.Font.Size * 1),
                         [System.Drawing.FontStyle]::Bold
                     )
$InfoNote.ForeColor  = [System.Drawing.Color]::Red
$InfoNote.TextAlign  = 'Middleleft'
$Form.Controls.Add($InfoNote)

# Now the “Please refer to” + KB on the next line
$lineY = $InfoNote.Bottom + 10

# “Please refer to” in plain black
$InfoText = New-Object System.Windows.Forms.Label
$InfoText.AutoSize   = $true
$InfoText.Text       = "Please refer to"
$InfoText.teztAlign  = 'Middlecenter'
$InfoText.Font       = New-Object System.Drawing.Font(
                         $InfoText.Font.FontFamily,
                         $InfoText.Font.Size,
                         [System.Drawing.FontStyle]::Regular
                     )
$InfoText.ForeColor  = [System.Drawing.Color]::Black
$InfoText.Location   = [System.Drawing.Point]::new(20, $lineY)
$Form.Controls.Add($InfoText)

# “KB0023831” in red, regular weight, immediately after
$InfoKB = New-Object System.Windows.Forms.Label
$InfoKB.AutoSize     = $true
$InfoKB.Text         = "KB0023831"
$InfoKB.Font         = New-Object System.Drawing.Font(
                         $InfoKB.Font.FontFamily,
                         $InfoKB.Font.Size,
                         [System.Drawing.FontStyle]::Regular
                     )
$InfoKB.ForeColor    = [System.Drawing.Color]::Red
$InfoKB.Location     = [System.Drawing.Point]::new(
                         $InfoText.Location.X + $InfoText.PreferredWidth + 5,
                         $lineY
                     )
$Form.Controls.Add($InfoKB)

# “for detailed deployment steps.” on its own line below
$InfoSuffix = New-Object System.Windows.Forms.Label
$InfoSuffix.AutoSize = $true
$InfoSuffix.Text     = "for supported models."
$InfoSuffix.Font     = New-Object System.Drawing.Font(
                         $InfoSuffix.Font.FontFamily,
                         $InfoSuffix.Font.Size,
                         [System.Drawing.FontStyle]::Regular
                     )
$InfoSuffix.ForeColor= [System.Drawing.Color]::Black
$InfoSuffix.Location = [System.Drawing.Point]::new(20, $InfoNote.Bottom + 30)
$Form.Controls.Add($InfoSuffix)

# ——— End explanatory text ———





# Set timer to close after 99 weeks
$Timer = New-Object System.Windows.Forms.Timer
$Timer.Interval = 59940000
$Timer.Add_Tick({
    $Timer.Stop()
    $Form.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $Form.Close()
})
$Timer.Start()

# Force foreground
$Form.Add_Shown({
    $Form.Activate()
    [Foreground]::SetForegroundWindow($Form.Handle)
})

# Show form, capture result
$Result = $Form.ShowDialog()
$Timer.Stop()

# Determine selection
$Selection = if ($Result -eq [System.Windows.Forms.DialogResult]::OK) {
    $Dropdown.SelectedItem
} else {
    "Option 1 - General Maintenance Device"
}
Write-Output "User selected: $Selection"

# Set TS variable
try {
    $TSEnv = New-Object -ComObject Microsoft.SMS.TSEnvironment
    switch ($Selection) {
        "1 - CABS Device"                    { $TSEnv.Value("DeploymentType") = "CABS" }
        "2 - Generic Display Device"         { $TSEnv.Value("DeploymentType") = "GDD" }
        "3 - Flight Explorer Display Device" { $TSEnv.Value("DeploymentType") = "FEDD" }
        "4 - GTRAX Device"                   { $TSEnv.Value("DeploymentType") = "GTRAXDD" }
        "5 - PSB Device"                     { $TSEnv.Value("DeploymentType") = "PSBDD" }
        "6 - Kiosk Web Device"               { $TSEnv.Value("DeploymentType") = "KWDD" }
        "7 - Training Device"                { $TSEnv.Value("DeploymentType") = "TRND" }
        "8 - CCTV Device"                    { $TSEnv.Value("DeploymentType") = "CCTV" }
    }
} catch {}

# Exit cleanly
#Exit 0
