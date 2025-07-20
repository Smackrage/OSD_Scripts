
<#

.SYNOPSIS
  Runs a series of checks to see if a machine is able to be built 
.DESCRIPTION
    

	This script will be displayed if the any of the following task sequence variables are set to true 
	'IS_LAN_Connected'
	'Is_USB_Connected'
    'Is_Approved'
    'Is_Free_Disk_Space'
    'Is_Nomad_Check'
    'IS_Power_Connected'
    

    The following exit codes are produced to indicate what check failed

    1000 --> USB plugged in
    2000 --> Device on wireless
    4000 --> Not enough free disk space
    8000 --> Device not in approved build collection (determined by collection variable)
    16000--> PBA Host
    500  --> Nomad not installed or not licensed
    75   --> Is Device on AC Power


 The asset tag has been entered into the BIOS this will also be displayed.

 Two options button are presented, open CmTrace.exe or restart

.PARAMETER <Parameter_Name>
    not paramters required
.INPUTS
  No imputs required.
.OUTPUTS
  Not outputs are generated
.NOTES
    Version: 1.0
    Author: Martin Smith
    11:37 02/07/2018

.EXAMPLE
  OSD_CHecks.ps1

#>

##### Customize FrontEnd title and logo #####


function GetScriptDirectory {
     $invocation = (Get-Variable MyInvocation -Scope 1).Value
     Split-Path $invocation.MyCommand.Path
} 
    
$VerboseLogging = "true"
[bool]$Global:Verbose = [System.Convert]::ToBoolean($VerboseLogging)
$Global:LogFile = Join-Path (GetScriptDirectory) '.\SMSTS_OSD_Checks.log' 
$Global:MaxLogSizeInKB = 10240
$Global:ScriptName = 'OSD_Checks.ps1' 
$Global:ScriptStatus = 'Success'
    
Function Logwrite () {
     Param ([String]$logstring)
     $time = Get-Date
     $logname = 'SMSTS_OSD_Checks.log'
     $logpath = $tsenv.Value("_SMSTSLogPath")
    # $logfile = '.\SMSTS_OSD_Checks.log'
     $logfile = Join-Path -Path $logPath -ChildPath $logname
    Add-Content $logfile -Value "$time - $logstring"
    Write-Host "$time - $logstring"
}

$TSEnv = New-Object -ComObject Microsoft.SMS.TSEnvironment   
    
Logwrite " Exit Codes for each check are listed below" 
Logwrite " Exit code values are combined into a single value if more than one check does not pass" 
Logwrite " USB drive attached to device: Exit Code 1000" 
Logwrite " Device is Connected via Wireless: Exit Code 2000" 
Logwrite " Insufficient Disk space for build to complete: Exit Code 3000" 
Logwrite " Device is not in approved build collection: Exit Code 8000" 
Logwrite " Nomad is not installed or licensed: Exit Code 500" 
Logwrite "-----" 
Logwrite " Example -- if device has a USB plugged in, insufficent disk space and Nomad is not installed Exit Code will be: 5500" 
Logwrite " Example -- No checks pass, Exit Code will be: 15500" 
Logwrite "-----" 



#region FormSetup
$title = 'OSD Build Questions'
$iconfile = '.\PowerShell.ico'

[void] [System.Reflection.Assembly]::LoadWithPartialName('System.Drawing')
[void] [System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms')
[System.Windows.Forms.Application]::EnableVisualStyles();
#region TabSetup
#Draw the base form
$objForm = New-Object System.Windows.Forms.Form
$objForm.Text = $title
$objForm.Size = New-Object System.Drawing.Size(740, 450)
$objForm.DataBindings.DefaultDataSourceUpdateMode = 0
$objForm.StartPosition = 'CenterScreen'
$objForm.AutoSize = $true
$objForm.AutoSize = 'GrowAndShrink'
$objForm.MinimizeBox = $False
$objForm.MaximizeBox = $False
$objForm.ControlBox = $False
$objform.FormBorderStyle = 'Fixed3D'
$objForm.Topmost = $True
#$Icon = New-Object system.drawing.icon($iconfile)
#$ObjForm.Icon = $Icon


#Draw tab structure and determine number of tabs
$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.DataBindings.DefaultDataSourceUpdateMode = 0
$tabControl.Location = New-Object System.Drawing.Size(10, 10)
$tabControl.Name = 'TabControl'
$tabControl.SelectedIndex = 0
$tabControl.ShowToolTips = $True
$tabControl.Size = New-Object System.Drawing.Size(700, 320)
$tabControl.AutoSize = $true
$tabControl.AutoSize = 'GrowAndShrink'
$tabControl.TabIndex = 4
$ObjForm.Controls.Add($tabControl)

#Add General tab
$GeneralTab = New-Object System.Windows.Forms.TabPage
$GeneralTab.DataBindings.DefaultDataSourceUpdateMode = 0
$System_Drawing_Point = New-Object System.Drawing.Point
$GeneralTab.Location = New-Object System.Drawing.Size(10, 10)
$GeneralTab.Name = 'Machine Name, Loction and Build Type'
$GeneralTab.Size = New-Object System.Drawing.Size(250, 15)
$GeneralTab.TabIndex = 1
$GeneralTab.Text = 'OSD Build Checks'
$tabControl.Controls.Add($GeneralTab)
 
#Endregion

$TSEnv.Value("Is_USB_Connected")
$TSEnv.Value("Is_LAN_Connected")
$TSEnv.Value("IS_Safe_Deployment")
$TSEnv.Value("Is_Free_Space")
$TSEnv.Value("Is_Nomad")
$TSEnv.Value("IS_Power_Connected")

$OSDPreCheckExitCode = 0

#region USB_Check
# $testUSB = 'False'
#$TSEnv.Value("Is_USB_Connected")

$DefaultUSB_Text = New-Object System.Windows.Forms.Label
$DefaultUSB_Text.AutoSize = $True
$DefaultUSB_Text.AutoSize = 'GrowAndShrink'
$DefaultUSB_Text.Font = New-Object System.Drawing.Font('Arial', 16, [System.Drawing.FontStyle]::Bold)
$DefaultUSB_Text.Location = New-Object System.Drawing.Size(5, 5)
$DefaultUSB_Text.Size = New-Object System.Drawing.Size(180, 30)
$DefaultUSB_Text.Text = "USB Ports Empty:"

$DefaultUSB_Text.Text.controls
$GeneralTab.Controls.Add($DefaultUSB_Text)

$USBCheck = New-Object System.Windows.Forms.Label
$USBCheck.AutoSize = $True
$USBCheck.AutoSize = 'GrowAndShrink'
$USBCheck.Font = New-Object System.Drawing.Font('Arial', 16, [System.Drawing.FontStyle]::Bold)
$USBCheck.Location = New-Object System.Drawing.Size(5, 5)
$USBCheck.Size = New-Object System.Drawing.Size(180, 30)

$USBcheckValue = $TSEnv.Value("Is_USB_Connected") 
Logwrite "USB Check has returned a value of $USBCheckValue" 
Logwrite "The value for Is_USB_Connected is produced by USBCheck.ps1 which must run prior to the OSD_Checks script" 

#$TSEnv.Value("Is_USB_Connected"

if ($TSEnv.Value("Is_USB_Connected") -eq 'True') {
     $USBCheck.Location = New-Object System.Drawing.Size(400, 5)
     $USBCheck.Text = "Failed" 
     $USBCheck.ForeColor = 'Red' 
     Logwrite "USB Check = Fail" 
     Logwrite "USB is Plugged into system this can cause issues with OSD process" 
     Logwrite "Exit code: 1000"
     $OSDPreCheckExitCode = 1000
}      
else {
     $USBCheck.Location = New-Object System.Drawing.Size(400, 5)
     $USBCheck.Text = "Pass" 
     $USBCheck.ForeColor = 'Green'     
     Logwrite "USB Check = Pass" 
     Logwrite "No USB has been detected"
            
}
$USBCheck.Text.controls
$GeneralTab.Controls.Add($USBCheck)

#endregion        
    
#Region LAN_Check 

#$TSEnv.Value("Is_LAN_Connected")   
# $LANCHECKs = 'False'

$DefaultLAN_Text = New-Object System.Windows.Forms.Label
$DefaultLAN_Text.AutoSize = $True
$DefaultLAN_Text.AutoSize = 'GrowAndShrink'
$DefaultLAN_Text.Font = New-Object System.Drawing.Font('Arial', 16, [System.Drawing.FontStyle]::Bold)
$DefaultLAN_Text.Location = New-Object System.Drawing.Size(5, 35)
$DefaultLAN_Text.Size = New-Object System.Drawing.Size(180, 30)
$DefaultLAN_Text.Text = "Device on LAN:"

$DefaultLAN_Text.Text.controls
$GeneralTab.Controls.Add($DefaultLAN_Text)

$LANCheck = New-Object System.Windows.Forms.Label
$LANCheck.AutoSize = $True
$LANCheck.AutoSize = 'GrowAndShrink'
$LANCheck.Font = New-Object System.Drawing.Font('Arial', 16, [System.Drawing.FontStyle]::Bold)
$LANCheck.Location = New-Object System.Drawing.Size(5, 35)
$LANCheck.Size = New-Object System.Drawing.Size(180, 30)
   
$LANCHECKVALUE = $TSEnv.Value("Is_LAN_Connected")
Logwrite "LAN_Check has returned a value of $LANCHECKVALUE" 

if ($TSEnv.Value("Is_LAN_Connected") -eq 'False') {
     $LANCheck.Location = New-Object System.Drawing.Size(400, 35)
     $LANCheck.Text = "Failed" 
     $LANCheck.ForeColor = 'Red' 
     Logwrite "LAN Check = Fail"
     Logwrite "Machine is connected to wireless. Plug LAN cable in before continuing" 
     Logwrite "Exit code: 2000"
     $OSDPreCheckExitCode = $OSDPreCheckExitCode + 2000
            
}      
else {
     $LANCheck.Location = New-Object System.Drawing.Size(400, 35)
     $LANCheck.Text = "Pass" 
     $LANCheck.ForeColor = 'Green'    
     Logwrite "LAN Check = Pass"  
     Logwrite "Machine is not connected to wireless" 

}

$LANCheck.Text.controls
$GeneralTab.Controls.Add($LANCheck)

#EndRegion    

#Region Free_Space

#$FreeSpaces= 'True'
     
$FreeSpace_Text = New-Object System.Windows.Forms.Label
$FreeSpace_Text.AutoSize = $True
$FreeSpace_Text.AutoSize = 'GrowAndShrink'
$FreeSpace_Text.Font = New-Object System.Drawing.Font('Arial', 16, [System.Drawing.FontStyle]::Bold)
$FreeSpace_Text.Location = New-Object System.Drawing.Size(5, 65)
$FreeSpace_Text.Size = New-Object System.Drawing.Size(180, 30)
$FreeSpace_Text.Text = "Free Disk Space:"

$FreeSpace_Text.Text.controls
$GeneralTab.Controls.Add($FreeSpace_Text)

$FreeSpaceCheck = New-Object System.Windows.Forms.Label
$FreeSpaceCheck.AutoSize = $True
$FreeSpaceCheck.AutoSize = 'GrowAndShrink'
$FreeSpaceCheck.Font = New-Object System.Drawing.Font('Arial', 16, [System.Drawing.FontStyle]::Bold)
$FreeSpaceCheck.Location = New-Object System.Drawing.Size(5, 65)
$FreeSpaceCheck.Size = New-Object System.Drawing.Size(180, 30)
 
$FreeSpaceCheckValue = $TSEnv.Value("Is_LAN_Connected")   
Logwrite "Free Space Check has returned a value of $FreeSpaceCheckValue"

# $free Spaces $TSEnv.Value("Is_Free_Space")
if ($TSEnv.Value("Is_Free_Space") -eq 'False') {
     $FreeSpaceCheck.Location = New-Object System.Drawing.Size(400, 65)
     $FreeSpaceCheck.Text = "Failed" 
     $FreeSpaceCheck.ForeColor = 'Red' 
     Logwrite "Free Space = Fail"
     Logwrite "Machine does not have enough free space to continue re-image"
     Logwrite "Exit code: 4000"
     $OSDPreCheckExitCode = $OSDPreCheckExitCode + 4000
}      
else {         
     $FreeSpaceCheck.Location = New-Object System.Drawing.Size(400, 65)
     $FreeSpaceCheck.Text = "Pass" 
     $FreeSpaceCheck.ForeColor = 'Green'
     Logwrite "Free Space Check = Pass" 
     Logwrite "Machine has enough free space to continue re-image"
}

$FreeSpaceCheck.Text.controls
$GeneralTab.Controls.Add($FreeSpaceCheck)

#endregion

#Region Approved_Build   #Checks to ensure to that Device is on AC Power.

#$Appoved= 'False' 

$Approved_Text = New-Object System.Windows.Forms.Label
$Approved_Text.AutoSize = $True
$Approved_Text.AutoSize = 'GrowAndShrink'
$Approved_Text.Font = New-Object System.Drawing.Font('Arial', 16, [System.Drawing.FontStyle]::Bold)
$Approved_Text.Location = New-Object System.Drawing.Size(5, 95)
$Approved_Text.Size = New-Object System.Drawing.Size(180, 30)
$Approved_Text.Text = "Approved Build:"

$Approved_Text.Text.controls
$GeneralTab.Controls.Add($Approved_Text)

$Approved_Check = New-Object System.Windows.Forms.Label
$Approved_Check.AutoSize = $True
$Approved_Check.AutoSize = 'GrowAndShrink'
$Approved_Check.Font = New-Object System.Drawing.Font('Arial', 16, [System.Drawing.FontStyle]::Bold)
$Approved_Check.Location = New-Object System.Drawing.Size(5, 95)
$Approved_Check.Size = New-Object System.Drawing.Size(180, 30)
  
$ApprovedValue =  $TSEnv.Value("IS_Safe_Deployment")
Logwrite "Approved build variable value returned $approvedvalue"

if ($TSEnv.Value("IS_Safe_Deployment") -eq 'False') {
     $Approved_Check.Location = New-Object System.Drawing.Size(400, 95)
     $Approved_Check.Text = "Failed" 
     $Approved_Check.ForeColor = 'Red' 
     Logwrite -message  "Is build approved = Fail"
     Logwrite "Machine is not a member of an approved build collection" 
     Logwrite "Exit code: 8000"
     $OSDPreCheckExitCode = $OSDPreCheckExitCode + 8000
}      
else {
     $Approved_Check.Location = New-Object System.Drawing.Size(400, 95)
     $Approved_Check.Text = "Pass" 
     $Approved_Check.ForeColor = 'Green'     
     Logwrite "Is build approved = Pass" 
     Logwrite "Machine is in an approved build collection"
}

$Approved_Check.Text.controls
$GeneralTab.Controls.Add($Approved_Check)

#endregion

#Region Nomad_check  #Checks to ensure to that nomad is installed and current.

#$Nomad = 'false'
 
$Nomad_Text = New-Object System.Windows.Forms.Label
$Nomad_Text.AutoSize = $True
$Nomad_Text.AutoSize = 'GrowAndShrink'
$Nomad_Text.Font = New-Object System.Drawing.Font('Arial', 16, [System.Drawing.FontStyle]::Bold)
$Nomad_Text.Location = New-Object System.Drawing.Size(5, 125)
$Nomad_Text.Size = New-Object System.Drawing.Size(180, 30)
$Nomad_Text.Text = "Nomad Installed:"

$Nomad_Text.Text.controls
$GeneralTab.Controls.Add($Nomad_Text)

$Nomad_Check = New-Object System.Windows.Forms.Label
$Nomad_Check.AutoSize = $True
$Nomad_Check.AutoSize = 'GrowAndShrink'
$Nomad_Check.Font = New-Object System.Drawing.Font('Arial', 16, [System.Drawing.FontStyle]::Bold)
$Nomad_Check.Location = New-Object System.Drawing.Size(5, 125)
$Nomad_Check.Size = New-Object System.Drawing.Size(180, 30)
   
$nomadCheckValue = $TSEnv.Value("Is_Nomad")   
Logwrite "Approved build variable value returned $nomadCheckValue"

if ($TSEnv.Value("Is_Nomad") -eq 'False') {
     $Nomad_Check.Location = New-Object System.Drawing.Size(400, 125)
     $Nomad_Check.Text = "Failed" 
     $Nomad_Check.ForeColor = 'Red' 
     Logwrite "Nomad Check = Fail"
     Logwrite "The Nomad Client is not current or licensed on this machine, it must be remediated before build can continue"
     Logwrite "Exit code: 500"
     $OSDPreCheckExitCode = $OSDPreCheckExitCode + 500
}      
else {
     $Nomad_Check.Location = New-Object System.Drawing.Size(400, 125)
     $Nomad_Check.Text = "Pass" 
     $Nomad_Check.ForeColor = 'Green'
     Logwrite "Nomad Check = Pass" 
     Logwrite "The Nomad client current and licensed, build can continue."     
}

$Nomad_Check.Text.controls
$GeneralTab.Controls.Add($Nomad_Check)

#Endregion

#Region PowerCheck   #Checks to ensure to that Device is on AC Power.

#$Power = 'false'
 
$Power_Text = New-Object System.Windows.Forms.Label
$Power_Text.AutoSize = $True
$Power_Text.AutoSize = 'GrowAndShrink'
$Power_Text.Font = New-Object System.Drawing.Font('Arial', 16, [System.Drawing.FontStyle]::Bold)
$Power_Text.Location = New-Object System.Drawing.Size(5, 155)
$Power_Text.Size = New-Object System.Drawing.Size(180, 30)
$Power_Text.Text = "AC Power Connected:"
$Power_Text.Text.controls
$GeneralTab.Controls.Add($Power_Text)

$Power_Check = New-Object System.Windows.Forms.Label
$Power_Check.AutoSize = $True
$Power_Check.AutoSize = 'GrowAndShrink'
$Power_Check.Font = New-Object System.Drawing.Font('Arial', 16, [System.Drawing.FontStyle]::Bold)
$Power_Check.Location = New-Object System.Drawing.Size(5, 155)
$Power_Check.Size = New-Object System.Drawing.Size(180, 30)
   
#$PowerCheckValue = $TSEnv.Value("Is_Power_Connected")   
Logwrite "Approved build variable value returned $PowerCheckValue"

if ($TSEnv.Value("Is_Power_Connected") -eq 'False') {
     $Power_Check.Location = New-Object System.Drawing.Size(400, 155)
     $Power_Check.Text = "Failed" 
     $Power_Check.ForeColor = 'Red' 
     Logwrite "Power Check = Not Passed"
     Logwrite "The Device is currently running on Battery Power, AC power must be plugged in for the build to continue"
     Logwrite "Exit code: 75"
     $OSDPreCheckExitCode = $OSDPreCheckExitCode + 75
}      
else {
     $Power_Check.Location = New-Object System.Drawing.Size(400, 155)
     $Power_Check.Text = "Pass" 
     $Power_Check.ForeColor = 'Green'
     Logwrite "Power Check = Pass"
     Logwrite "The device is currently on AC power."
}

$Nomad_Check.Text.controls
$GeneralTab.Controls.Add($Power_Check)

#endregion

$PBA_Text = New-Object System.Windows.Forms.Label
$PBA_Text.AutoSize = $True
$PBA_Text.AutoSize = 'GrowAndShrink'
$PBA_Text.Font = New-Object System.Drawing.Font('Arial', 16, [System.Drawing.FontStyle]::Bold)
$PBA_Text.Location = New-Object System.Drawing.Size(5, 185)
$PBA_Text.Size = New-Object System.Drawing.Size(180, 30)
$PBA_Text.Text = "PBA Data Located:"
$PBA_Text.Text.controls
$GeneralTab.Controls.Add($PBA_Text)

$PBA_Check = New-Object System.Windows.Forms.Label
$PBA_Check.AutoSize = $True
$PBA_Check.AutoSize = 'GrowAndShrink'
$PBA_Check.Font = New-Object System.Drawing.Font('Arial', 16, [System.Drawing.FontStyle]::Bold)
$PBA_Check.Location = New-Object System.Drawing.Size(5, 185)
$PBA_Check.Size = New-Object System.Drawing.Size(180, 30)
   
$PBACheckValue = $TSEnv.Value("IS_PBA_HOST")   
Logwrite "Approved build variable value returned $PBACheckValue"

if ($TSEnv.Value("IS_PBA_HOST") -eq 'True') {
     $PBA_Check.Location = New-Object System.Drawing.Size(400, 185)
     $PBA_Check.Text = "Failed" 
     $PBA_Check.ForeColor = 'Red' 
     Logwrite "Power Check = Not Passed"
     Logwrite "The Device is currently hosting PBA data, the build will not continue to prevent possible data loss."
     Logwrite "Exit code: 16000"
     $OSDPreCheckExitCode = $OSDPreCheckExitCode + 16000
}      
else {
     $PBA_Check.Location = New-Object System.Drawing.Size(400, 185)
     $PBA_Check.Text = "Pass" 
     $PBA_Check.ForeColor = 'Green'
     Logwrite "Power Check = Pass"
     Logwrite "The device is not currently a Nomad host."
}

$Nomad_Check.Text.controls
$GeneralTab.Controls.Add($PBA_Check)







#Region Combine Error Codes

Logwrite "FINAL EXIT CODE:$OSDPreCheckExitCode"

#If Error Code is not equal to 0 than change timeout on error dialog

if ($OSDPreCheckExitCode -ne '0') {
     $TSEnv = New-Object -ComObject Microsoft.SMS.TSEnvironment
     $TSEnv.Value("SMSTSErrorDialogTimeout") = 1
}
 

#region Asset Tag 
#Get Asset tag from BIOS     
$assettag = (Get-WmiObject -Class win32_systemenclosure).SMBIOSAssetTag
$serial = (Get-CimInstance -classname win32_bios).serialnumber
Logwrite "Asset Tag = $assettag" 
if ($assettag -eq $null) {
     $compname = $serial
}
Else {
     $compname = $assettag
}
$assettag = New-Object System.Windows.Forms.Label
$assettag.Location = New-Object System.Drawing.Size(10, 255)
$assettag.Size = New-Object System.Drawing.Size(180, 30)
$assettag.Font = New-Object System.Drawing.Font('Arial', 10)
$assettag.text = 'Asset Tag, as shown in BIOS, if available'
$GeneralTab.Controls.Add($assettag)

$objTextBox = New-Object System.Windows.Forms.TextBox
$objTextBox.Location = New-Object System.Drawing.Size(10, 230)
$objTextBox.Size = New-Object System.Drawing.Size(180, 40)
$objTextBox.Font = New-Object System.Drawing.Font('Arial', 10)
$objTextbox.MaxLength = 11
#$objTextBox.Text = "$($OSDAssetTag)"
#$objTextBox.Top = $true
$objTextBox.Text = $compname

$GeneralTab.Controls.Add($objTextBox)

#Tooltip for computer name 
$compTooltip = New-Object System.Windows.Forms.ToolTip
$compToolTip.AutomaticDelay = 0
$compToolTip.AutoPopDelay = '10000'
$compToolTip.ToolTipTitle = 'Sample Computer Names:'
#$compToolTip.SetToolTip($custom, 'WK' + $global:serial.toupper() + �`nWK1" + $global:serial.toupper() + "`nWK2" + $global:serial.toupper() + "`nWK3" + $global:serial.toupper())

#endregion

       
#region CmdPrompt button
#Note about cmd prompt/PowerShell access
$cmdprompt = New-Object System.Windows.Forms.Label
$cmdprompt.Location = New-Object System.Drawing.Size(20, 350)
$cmdprompt.Size = New-Object System.Drawing.Size(250, 15)
$cmdprompt.Font = New-Object System.Drawing.Font ('Arial', 10, [System.Drawing.FontStyle]::BOLD)
$cmdprompt.ForeColor = [System.Drawing.Color]::'Green'

$cmdprompt.Text = 'Press F8 for `ncmd prompt/PowerShell access.'


#Region CMTrace    
#Function to open smsts.log with CMTrace, useful for troubleshooting
function SMSTSLogButton {
     $smstslogButton = New-Object System.Windows.Forms.Button
     $smstslogButton.Location = New-Object System.Drawing.Size(270, 350)
     $smstslogButton.Size = New-Object System.Drawing.Size(180, 28)
     $smstslogButton.Text = 'CMTrace - smsts.log'
     $smstslogButton.Add_Click( {
               x:\sms\bin\x64\CMTrace.exe x:\windows\temp\smstslog\smsts.log
          })
     $objForm.Controls.Add($smstslogButton)

     $cmtraceTooltip = New-Object System.Windows.Forms.ToolTip
     $cmtraceToolTip.AutomaticDelay = 0
     $cmtraceToolTip.AutoPopDelay = '10000'
     $cmtraceToolTip.ToolTipTitle = 'ConfigMgr Trace Log Viewer'
     # $cmtraceToolTip.SetToolTip($smstslogButton, �This button opens the task sequence log in CMTrace,`nauto-scrolls, and highlights errors red and warnings yellow.�)
}

# SMSTSLogButton
#endregion

#Region Restart
#Function to restart the computer if necessary
function Restart-Button {
     $RestartButton = New-Object System.Windows.Forms.Button
     $RestartButton.Location = New-Object System.Drawing.Size(50, 350)
     $RestartButton.Size = New-Object System.Drawing.Size(120, 28)
     $RestartButton.Text = 'Restart Computer'
     $RestartButton.Add_Click( {
               $restartconfirm = [System.Windows.Forms.MessageBox]::Show('Are you sure you want to restart?', 'Confirm Restart!' , 4, 'Exclamation')
               if ($restartconfirm -eq 'YES') {
                    Restart-Computer -Delay 30
               }
          })
     $objForm.Controls.Add($RestartButton)

     $RestartButtonTooltip = New-Object System.Windows.Forms.ToolTip
     $RestartButtonTooltip.AutomaticDelay = 0
     $RestartButtonTooltip.ToolTipTitle = 'Restart Winpe'
     $RestartButtonTooltip.SetToolTip($Restartbutton, 'This will reboot the device out of WINPE')

}

Restart-Button
#EndRegion

#region OKButton
#Continue button to confirm all choices and process to the task sequence wizard
$OKButton = New-Object System.Windows.Forms.Button
$OKButton.Location = New-Object System.Drawing.Size(570, 350)
$OKButton.Size = New-Object System.Drawing.Size(75, 28)
#$OKButton.BackColor = 'CornflowerBlue'
$OKButton.Text = 'OK...'

if ($OSDPreCheckExitCode -eq '0') {
     Logwrite "JW $OSDPreCheckExitCode"
     $objForm.Close()
     [System.Environment]::Exit($OSDPreCheckExitCode)
}
else {
          Logwrite "JW $OSDPreCheckExitCode - In the else"
          if ($TSEnv.Value("_SMSTSUserStarted") -eq 'False') {
            Logwrite "JW $OSDPreCheckExitCode - Where the exitcode should be set"
            [System.Environment]::Exit($OSDPreCheckExitCode)
            }
          $FormConfirmation = New-Object System.Windows.Forms.Form
          $FormConfirmation.TopMost = $True
          $Timer = New-Object -TypeName System.Windows.Forms.Timer
          $Timer.Interval = 60000
          $Timer.Add_Tick({$FormConfirmation.DialogResult = "OK";$FormConfirmation.Dispose();Timer$.Stop([System.Environment]::Exit($OSDPreCheckExitCode))})
          $timer.Start()
         # $Confirmation = [System.Windows.Forms.MessageBox]::Show($FormConfirmation,"Asset Tag is set to $ComputerAssetTag `nIs this correct?","Asset Tag Confirmation",4,32)
          $OKButton.Add_Click( {
            $objForm.Close()
          [System.Environment]::Exit($OSDPreCheckExitCode)
            })
     
} 
 
#region finishup
#$OKbutton.add_Click($objForm.Close())
$objForm.Controls.Add($OKButton)

$OKButtonTooltip = New-Object System.Windows.Forms.ToolTip
$OKButtonTooltip.AutomaticDelay = 0
$OKButtonTooltip.AutoPopDelay = '10000'
$OKButtonTooltip.ToolTipTitle = 'OK button'
$OKButtonTooltip.SetToolTip($OKButton, "Clicking OK will validate the selected options,`nif the Computername and build type have been entered `ncorrectly a confirmation box will appear")


$objForm.Add_Shown( {$objForm.Activate()})


if ($TSEnv.Value("_SMSTSUserStarted") -ne 'False') {
    [void] $objForm.ShowDialog()
}
#endregion
