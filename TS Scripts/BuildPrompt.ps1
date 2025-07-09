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
Version:1.06
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
$Form.Size           = New-Object System.Drawing.Size(300, 320)
$Form.StartPosition  = "CenterScreen"
$Form.TopMost        = $true

# Description label
$Label = New-Object System.Windows.Forms.Label
$Label.Location  = New-Object System.Drawing.Point(20, 10)
$Label.Size      = New-Object System.Drawing.Size(260, 30)
$Label.Text      = "Please select the appropriate deployment option:"
$Label.TextAlign = 'MiddleLeft'
$Label.AutoSize  = $false
$Form.Controls.Add($Label)

# Dropdown menu
$Dropdown = New-Object System.Windows.Forms.ComboBox
$Dropdown.Location      = New-Object System.Drawing.Point(50, 45)
$Dropdown.Size          = New-Object System.Drawing.Size(200, 20)
$Dropdown.DropDownStyle = "DropDownList"
"1 - CABS Device","2 - Generic Display Device","3 - Flight Explorer Display Device",
"4 - GTRAX Device","5 - PSB Device","6 - Kiosk Web Device","7 - Training Device" |
    ForEach-Object { $Dropdown.Items.Add($_) }
$Dropdown.SelectedIndex = 0
$Form.Controls.Add($Dropdown)

# OK button
$OKButton = New-Object System.Windows.Forms.Button
$OKButton.Location     = New-Object System.Drawing.Point(50, 75)
$OKButton.Size         = New-Object System.Drawing.Size(200, 30)
$OKButton.Text         = "OK"
$OKButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
$Form.Controls.Add($OKButton)

# ——— Explanatory text below the dropdown ———

# Main text line (full height)
$Info1 = New-Object System.Windows.Forms.Label
$Info1.Location = New-Object System.Drawing.Point(20, 115)
$Info1.Size     = New-Object System.Drawing.Size(260, 30)
$Info1.Text     = "Please ensure that kiosks are only run on the following models"
$Info1.AutoSize = $false
$Form.Controls.Add($Info1)

# Bullet 1 (dash)
$Bullet1 = New-Object System.Windows.Forms.Label
$Bullet1.Location  = New-Object System.Drawing.Point(30, 155)
$Bullet1.AutoSize  = $true
$Bullet1.Font      = New-Object System.Drawing.Font(
                       $Bullet1.Font.FontFamily,
                       $Bullet1.Font.Size,
                       [System.Drawing.FontStyle]::Regular
                   )
$Bullet1.ForeColor = [System.Drawing.Color]::Black
$Bullet1.Text      = "-"
$Form.Controls.Add($Bullet1)

$Text1 = New-Object System.Windows.Forms.Label
$Text1.Location = New-Object System.Drawing.Point(45, 155)
$Text1.Size     = New-Object System.Drawing.Size(235, 15)
$Text1.Text     = '"Dell - Model1"'
$Text1.Font     = New-Object System.Drawing.Font(
                    $Text1.Font.FontFamily,
                    $Text1.Font.Size,
                    [System.Drawing.FontStyle]::Bold
                  )
$Form.Controls.Add($Text1)

# Bullet 2 (dash)
$Bullet2 = New-Object System.Windows.Forms.Label
$Bullet2.Location  = New-Object System.Drawing.Point(30, 175)
$Bullet2.AutoSize  = $true
$Bullet2.Font      = New-Object System.Drawing.Font(
                       $Bullet2.Font.FontFamily,
                       $Bullet2.Font.Size,
                       [System.Drawing.FontStyle]::Regular
                   )
$Bullet2.ForeColor = [System.Drawing.Color]::Black
$Bullet2.Text      = "-"
$Form.Controls.Add($Bullet2)

$Text2 = New-Object System.Windows.Forms.Label
$Text2.Location = New-Object System.Drawing.Point(45, 175)
$Text2.Size     = New-Object System.Drawing.Size(235, 15)
$Text2.Text     = '"Dell - Model 2"'
$Text2.Font     = New-Object System.Drawing.Font(
                    $Text2.Font.FontFamily,
                    $Text2.Font.Size,
                    [System.Drawing.FontStyle]::Bold
                  )
$Form.Controls.Add($Text2)

# Bullet 3 (dash)
$Bullet3 = New-Object System.Windows.Forms.Label
$Bullet3.Location  = New-Object System.Drawing.Point(30, 195)
$Bullet3.AutoSize  = $true
$Bullet3.Font      = New-Object System.Drawing.Font(
                       $Bullet3.Font.FontFamily,
                       $Bullet3.Font.Size,
                       [System.Drawing.FontStyle]::Regular
                   )
$Bullet3.ForeColor = [System.Drawing.Color]::Black
$Bullet3.Text      = "-"
$Form.Controls.Add($Bullet3)

$Text3 = New-Object System.Windows.Forms.Label
$Text3.Location = New-Object System.Drawing.Point(45, 195)
$Text3.Size     = New-Object System.Drawing.Size(235, 15)
$Text3.Text     = '"HP - Model 2"'
$Text3.Font     = New-Object System.Drawing.Font(
                    $Text3.Font.FontFamily,
                    $Text3.Font.Size,
                    [System.Drawing.FontStyle]::Bold
                  )
$Form.Controls.Add($Text3)

# Bullet 4 (dash)
$Bullet4 = New-Object System.Windows.Forms.Label
$Bullet4.Location  = New-Object System.Drawing.Point(30, 215)
$Bullet4.AutoSize  = $true
$Bullet4.Font      = New-Object System.Drawing.Font(
                       $Bullet4.Font.FontFamily,
                       $Bullet4.Font.Size,
                       [System.Drawing.FontStyle]::Regular
                   )
$Bullet4.ForeColor = [System.Drawing.Color]::Black
$Bullet4.Text      = "-"
$Form.Controls.Add($Bullet4)

$Text4 = New-Object System.Windows.Forms.Label
$Text4.Location = New-Object System.Drawing.Point(45, 215)
$Text4.Size     = New-Object System.Drawing.Size(235, 15)
$Text4.Text     = '"SOME RANDOM THING FROM THE DEVILS IT BIN"'
$Text4.Font     = New-Object System.Drawing.Font(
                    $Text4.Font.FontFamily,
                    $Text4.Font.Size,
                    [System.Drawing.FontStyle]::Bold
                  )
$Form.Controls.Add($Text4)

# ——— End explanatory text ———

# 60-second close timer
$Timer = New-Object System.Windows.Forms.Timer
$Timer.Interval = 60000
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
        "1 - CABS Device"                   { $TSEnv.Value("DeploymentType") = "CABS" }
        "2 - Generic Display Device"        { $TSEnv.Value("DeploymentType") = "GDD" }
        "3 - Flight Explorer Display Device"{ $TSEnv.Value("DeploymentType") = "FEDD" }
        "4 - GTRAX Device"                  { $TSEnv.Value("DeploymentType") = "GTRAXDD" }
        "5 - PSB Device"                    { $TSEnv.Value("DeploymentType") = "PSBDD" }
        "6 - Kiosk Web Device"              { $TSEnv.Value("DeploymentType") = "KWDD" }
        "7 - Training Device"               { $TSEnv.Value("DeploymentType") = "TRND" }
    }
} catch {}

Exit 0
