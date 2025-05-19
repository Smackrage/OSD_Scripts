
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
    500  --> Nomad not installed or not licensed
    50   --> Is Device on AC Power


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
    function Logwrite
    {
      param (
      [Parameter(Mandatory=$true)]
      $message,
      [Parameter(Mandatory=$true)]
      $component,
      [Parameter(Mandatory=$true)]
      $type )
    
      switch ($type)
      {
        1 { $type = "Info" }
        2 { $type = "Warning" }
        3 { $type = "Error" }
        4 { $type = "Verbose" }
      }
    
      if (($type -eq "Verbose") -and ($Global:Verbose))
      {
        $toLog = "{0} `$$<{1}><{2} {3}><thread={4}>" -f ($type + ":" + $message), ($Global:ScriptName + ":" + $component), (Get-Date -Format "MM-dd-yyyy"), (Get-Date -Format "HH:mm:ss.ffffff"), $pid
        $toLog | Out-File -Append -Encoding UTF8 -FilePath ("filesystem::{0}" -f $Global:LogFile)
        Write-Host $message
      }
      elseif ($type -ne "Verbose")
      {
        $toLog = "{0} `$$<{1}><{2} {3}><thread={4}>" -f ($type + ":" + $message), ($Global:ScriptName + ":" + $component), (Get-Date -Format "MM-dd-yyyy"), (Get-Date -Format "HH:mm:ss.ffffff"), $pid
        $toLog | Out-File -Append -Encoding UTF8 -FilePath ("filesystem::{0}" -f $Global:LogFile)
        Write-Host $message
      }
      if (($type -eq 'Warning') -and ($Global:ScriptStatus -ne 'Error')) { $Global:ScriptStatus = $type }
      if ($type -eq 'Error') { $Global:ScriptStatus = $type }
    
      if ((Get-Item $Global:LogFile).Length/1KB -gt $Global:MaxLogSizeInKB)
      {
        $log = $Global:LogFile
        Remove-Item ($log.Replace(".log", ".lo_"))
        Rename-Item $Global:LogFile ($log.Replace(".log", ".lo_")) -Force
      }
    } 
    
    function GetScriptDirectory
    {
      $invocation = (Get-Variable MyInvocation -Scope 1).Value
      Split-Path $invocation.MyCommand.Path
    } 
    
    $VerboseLogging = "true"
    [bool]$Global:Verbose = [System.Convert]::ToBoolean($VerboseLogging)
    $Global:LogFile = Join-Path (GetScriptDirectory) 'c:\windows\ccm\logs\smstslog\SMSTS_OSD_Checks.log' 
    $Global:MaxLogSizeInKB = 10240
    $Global:ScriptName = 'OSD_Checks.ps1' 
    $Global:ScriptStatus = 'Success'
    
Logwrite -message (" Exit Codes for each check are listed below") -component "Main()" -type 1
Logwrite -message (" Exit code values are combined into a single value if more than one check does not pass") -component "Main()" -type 1
Logwrite -message (" USB drive attached to device: Exit Code 1000") -component "Main()" -type 1
Logwrite -message (" Device is Connected via Wireless: Exit Code 2000") -component "Main()" -type 1
Logwrite -message (" Insufficient Disk space for build to complete: Exit Code 3000") -component "Main()" -type 1
Logwrite -message (" Device is not in approved build collection: Exit Code 8000") -component "Main()" -type 1
Logwrite -message (" Nomad is not installed or licensed: Exit Code 500") -component "Main()" -type 1
Logwrite -message ("-----") -component "Main()" -type 1
Logwrite -message (" Example -- if device has a USB plugged in, insufficent disk space and Nomad is not installed Exit Code will be: 5500") -component "Main()" -type 1
Logwrite -message (" Example -- No checks pass, Exit Code will be: 15500") -component "Main()" -type 1
Logwrite -message ("-----") -component "Main()" -type 1

    $TSEnv = New-Object -ComObject Microsoft.SMS.TSEnvironment
    $TSEnv.Value("SMSTSErrorDialogTimeout") = 1


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
    $objForm.Size = New-Object System.Drawing.Size(740,450)
    $objForm.DataBindings.DefaultDataSourceUpdateMode = 0
    $objForm.StartPosition = 'CenterScreen'
    $objForm.AutoSize = $true
    $objForm.AutoSize = 'GrowAndShrink'
    $objForm.MinimizeBox = $False
    $objForm.MaximizeBox = $False
    $objForm.ControlBox = $True
    $objform.FormBorderStyle = 'Fixed3D'
    $objForm.Topmost = $True
    #$Icon = New-Object system.drawing.icon($iconfile)
    #$ObjForm.Icon = $Icon


    #Draw tab structure and determine number of tabs
    $tabControl = New-Object System.Windows.Forms.TabControl
    $tabControl.DataBindings.DefaultDataSourceUpdateMode = 0
    $tabControl.Location = New-Object System.Drawing.Size(10,10)
    $tabControl.Name = 'TabControl'
    $tabControl.SelectedIndex = 0
    $tabControl.ShowToolTips = $True
    $tabControl.Size = New-Object System.Drawing.Size(700,320)
    $tabControl.AutoSize = $true
    $tabControl.AutoSize = 'GrowAndShrink'
    $tabControl.TabIndex = 4
    $ObjForm.Controls.Add($tabControl)

    #Add General tab
    $GeneralTab = New-Object System.Windows.Forms.TabPage
    $GeneralTab.DataBindings.DefaultDataSourceUpdateMode = 0
    $System_Drawing_Point = New-Object System.Drawing.Point
    $GeneralTab.Location = New-Object System.Drawing.Size(10,10)
    $GeneralTab.Name = 'Machine Name, Loction and Build Type'
    $GeneralTab.Size = New-Object System.Drawing.Size(250,15)
    $GeneralTab.TabIndex = 1
    $GeneralTab.Text = 'OSD Build Checks'
    $tabControl.Controls.Add($GeneralTab)
 
#Endregion

$TSEnv = New-Object -ComObject Microsoft.SMS.TSEnvironment
$TSEnv.Value("Is_USB_Connected")
$TSEnv.Value("Is_LAN_Connected")
$TSEnv.Value("IS_Safe_Deployment")
$TSEnv.Value("Is_Free_Space")
$TSEnv.Value("Is_Nomad")
$TSEnv.Value("IS_Power_Connected")


#$Countdowntimer = New-Object System.Windows.Forms.label
#$Countdowntimer.AutoSize = $True
#$Countdowntimer.AutoSize =  'GrowAndShrink'
#$Countdowntimer.Font = New-Object System.Drawing.Font('Arial',10)
#$Countdowntimer.Location = New-Object System.Drawing.Size(270,230)
#$Countdowntimer.Size = New-Object System.Drawing.Size(180,30)
#$Countdowntimer.Text = "Aasdssadsadsdsadsd wn in BIOS, if available:"


Function ClearAndClose()
{
   $Timer.Stop(); 
   #$objForm.Close(); 
   #$objForm.Dispose();
   $Timer.Dispose();
   #$Countdowntimer.Dispose();
   #$Button.Dispose();
  # $Script:CountDown=6
}
Function Button_Click()
{
   ClearAndClose
}
Function Timer_Tick()
    {
      
        $Countdowntimer.Text = "Your system will reboot in $Script:CountDown seconds"
            --$Script:CountDown
            if ($Script:CountDown -lt 0)
            {  
                #$Timer.Stop();
                #$Timer.Dispose();
                #$Countdowntimer.Close(); 
                #$Countdowntimer.Dispose();
              #  [System.Environment]::Exit(119) 
               
            }
    }

   # Timer_Tick

$Countdowntimer = New-Object System.Windows.Forms.label
$Countdowntimer.AutoSize = $True
$Countdowntimer.AutoSize =  'GrowAndShrink'
$Countdowntimer.Font = New-Object System.Drawing.Font('Arial',10)
$Countdowntimer.Location = New-Object System.Drawing.Size(270,350)
$Countdowntimer.Size = New-Object System.Drawing.Size(180,30)
$objForm.Controls.Add($Countdowntimer)

#$Countdownform = New-Object system.windows.forms.forms

$Script:CountDown = 6

$Timer = New-Object System.Windows.Forms.Timer
$Timer.Interval = 1000
#$Timer.Add_Tick({Timer_Tick;$Countdownform.DialogResult = 'OK';$Countdowntimer.Dispose();$Timer.Stop()})
$timer.start()

#$Countdownform = [System.Windows.Forms.MessageBox]::Show($Countdownform,"Asset Tag is set to  `nIs this correct?","Asset Tag Confirmation",4,32)

#$Timer = New-Object System.Windows.Forms.Timer
#$Timer.Interval = 1000
#$timer.Location = New-Object System.Drawing.Size (270,280)
#$GeneralTab.controls.Add($timer)

#Create exit code variable of 0 so PoSH doesn't complain
$OSDPreCheckExitCode = 0

#region USB_Check
   # $testUSB = 'False'
    #$TSEnv.Value("Is_USB_Connected")

    $DefaultUSB_Text = New-Object System.Windows.Forms.Label
    $DefaultUSB_Text.AutoSize = $True
    $DefaultUSB_Text.AutoSize =  'GrowAndShrink'
    $DefaultUSB_Text.Font = New-Object System.Drawing.Font('Arial',16,[System.Drawing.FontStyle]::Bold)
    $DefaultUSB_Text.Location = New-Object System.Drawing.Size(5,5)
    $DefaultUSB_Text.Size = New-Object System.Drawing.Size(180,30)
    $DefaultUSB_Text.Text = "USB Plugged in:"

    $DefaultUSB_Text.Text.controls
    $GeneralTab.Controls.Add($DefaultUSB_Text)

    $USBCheck = New-Object System.Windows.Forms.Label
    $USBCheck.AutoSize = $True
    $USBCheck.AutoSize =  'GrowAndShrink'
    $USBCheck.Font = New-Object System.Drawing.Font('Arial',16,[System.Drawing.FontStyle]::Bold)
    $USBCheck.Location = New-Object System.Drawing.Size(5,5)
    $USBCheck.Size = New-Object System.Drawing.Size(180,30)

 $USBcheckValue =  $TSEnv.Value("Is_USB_Connected")  
Logwrite -message ("USB Check has returned a value of $USBCheckValue") -component "Main()" -type 1
Logwrite -message ("The value for Is_USB_Connected is produced by USBCheck.ps1 which must run prior to the OSD_Checks script") -component "Main()" -type 1

    #$TSEnv.Value("Is_USB_Connected"
        if ($TSEnv.Value("Is_USB_Connected") -eq 'True') {
            $USBCheck.Location = New-Object System.Drawing.Size(400,5)
            $USBCheck.Text = "Failed" 
            $USBCheck.ForeColor = 'Red' 
            Logwrite -message ("USB Check = Fail") -component "Main()" -type 4
            Logwrite -message ("USB is Plugged into system this can cause issues with OSD process") -component "Main()" -type 1
            Logwrite -message ("Exit code: 1000") -component -type 1
            $OSDPreCheckExitCode = 1000
        }      
        else {
            $USBCheck.Location = New-Object System.Drawing.Size(400,5)
            $USBCheck.Text = "Pass" 
            $USBCheck.ForeColor = 'Green'     
            Logwrite -message ("USB Check = Pass") -component "Main()" -type 1
            Logwrite -message ("No USB has been detected") -component "Main()" -type 1
            
        }
        $USBCheck.Text.controls
        $GeneralTab.Controls.Add($USBCheck)

#endregion        
    
#Region LAN_Check 

#$TSEnv.Value("Is_LAN_Connected")   
   # $LANCHECKs = 'False'

    $DefaultLAN_Text = New-Object System.Windows.Forms.Label
    $DefaultLAN_Text.AutoSize = $True
    $DefaultLAN_Text.AutoSize =  'GrowAndShrink'
    $DefaultLAN_Text.Font = New-Object System.Drawing.Font('Arial',16,[System.Drawing.FontStyle]::Bold)
    $DefaultLAN_Text.Location = New-Object System.Drawing.Size(5,35)
    $DefaultLAN_Text.Size = New-Object System.Drawing.Size(180,30)
    $DefaultLAN_Text.Text = "Device on Wireless:"

    $DefaultLAN_Text.Text.controls
    $GeneralTab.Controls.Add($DefaultLAN_Text)

    $LANCheck = New-Object System.Windows.Forms.Label
    $LANCheck.AutoSize = $True
    $LANCheck.AutoSize =  'GrowAndShrink'
    $LANCheck.Font = New-Object System.Drawing.Font('Arial',16,[System.Drawing.FontStyle]::Bold)
    $LANCheck.Location = New-Object System.Drawing.Size(5,35)
    $LANCheck.Size = New-Object System.Drawing.Size(180,30)
   
    #$LANCHECKVALUE = $TSEnv.Value("Is_LAN_Connected")
Logwrite -message ("LAN_Check has returned a value of $LANCHECKVALUE") -component "Main()" -type 1

        if ($TSEnv.Value("Is_LAN_Connected") -eq 'True') {
            $LANCheck.Location = New-Object System.Drawing.Size(400,35)
            $LANCheck.Text = "Failed" 
            $LANCheck.ForeColor = 'Red' 
            Logwrite -message ("LAN Check = Fail") -component "Main()" -type 4
            Logwrite -message ("Machine is connected to wireless. Plug LAN cable in before continuing") -component "Main()" -type 1
            Logwrite -message ("Exit code: 2000") -component -type 1
            $OSDPreCheckExitCode = $OSDPreCheckExitCode + 2000
            
        }      
        else {
            $LANCheck.Location = New-Object System.Drawing.Size(400,35)
            $LANCheck.Text = "Pass" 
            $LANCheck.ForeColor = 'Green'    
            Logwrite -message ("LAN Check = Pass") -component "Main()" -type 1 
            Logwrite -message ("Machine is not connected to wireless") -component "Main()" -type 1

        }

    $LANCheck.Text.controls
    $GeneralTab.Controls.Add($LANCheck)

#EndRegion    

#Region Free_Space

    #$FreeSpaces= 'True'
     
    $FreeSpace_Text = New-Object System.Windows.Forms.Label
    $FreeSpace_Text.AutoSize = $True
    $FreeSpace_Text.AutoSize =  'GrowAndShrink'
    $FreeSpace_Text.Font = New-Object System.Drawing.Font('Arial',16,[System.Drawing.FontStyle]::Bold)
    $FreeSpace_Text.Location = New-Object System.Drawing.Size(5,65)
    $FreeSpace_Text.Size = New-Object System.Drawing.Size(180,30)
    $FreeSpace_Text.Text = "Free Disk Space:"

    $FreeSpace_Text.Text.controls
    $GeneralTab.Controls.Add($FreeSpace_Text)

    $FreeSpaceCheck= New-Object System.Windows.Forms.Label
    $FreeSpaceCheck.AutoSize = $True
    $FreeSpaceCheck.AutoSize =  'GrowAndShrink'
    $FreeSpaceCheck.Font = New-Object System.Drawing.Font('Arial',16,[System.Drawing.FontStyle]::Bold)
    $FreeSpaceCheck.Location = New-Object System.Drawing.Size(5,65)
    $FreeSpaceCheck.Size = New-Object System.Drawing.Size(180,30)
 
$FreeSpaceCheck = $TSEnv.Value("Is_LAN_Connected")   
Logwrite -message ("Free Space Check has returned a value of $FreeSpaceCheck") -component "Main()" -type 1

# $free Spaces $TSEnv.Value("Is_Free_Space")
<#
        if ($TSEnv.Value("Is_Free_Space") -eq 'True') {
            $FreeSpaceCheck.Location = New-Object System.Drawing.Size(400,65)
            $FreeSpaceCheck.Text = "Failed" 
            $FreeSpaceCheck.ForeColor = 'Red' 
            Logwrite -message ("Free Space = Fail") -component "Main()" -type 4 
            Logwrite -message ("Machine does not have enough free space to continue re-image") -component "Main()" -type 1
            Logwrite -message ("Exit code: 4000") -component -type 1
            $OSDPreCheckExitCode = $OSDPreCheckExitCode + 4000
        }      
        else {         
            $FreeSpaceCheck.Location = New-Object System.Drawing.Size(400,65)
            $FreeSpaceCheck.Text = "Pass" 
            $FreeSpaceCheck.ForeColor = 'Green'
            Logwrite -message ("Free Space Check = Pass") -component "Main()" -type 1
            Logwrite -message ("Machine has enough free space to continue re-image") -component "Main()" -type 1
        }
#>
    $FreeSpaceCheck.Text.controls
    $GeneralTab.Controls.Add($FreeSpaceCheck)

#endregion

#Region Approved_Build   #Checks to ensure to that Device is on AC Power.

    #$Appoved= 'False' 

    $Approved_Text = New-Object System.Windows.Forms.Label
    $Approved_Text.AutoSize = $True
    $Approved_Text.AutoSize =  'GrowAndShrink'
    $Approved_Text.Font = New-Object System.Drawing.Font('Arial',16,[System.Drawing.FontStyle]::Bold)
    $Approved_Text.Location = New-Object System.Drawing.Size(5,95)
    $Approved_Text.Size = New-Object System.Drawing.Size(180,30)
    $Approved_Text.Text = "Approved Build:"

    $Approved_Text.Text.controls
    $GeneralTab.Controls.Add($Approved_Text)

    $Approved_Check= New-Object System.Windows.Forms.Label
    $Approved_Check.AutoSize = $True
    $Approved_Check.AutoSize =  'GrowAndShrink'
    $Approved_Check.Font = New-Object System.Drawing.Font('Arial',16,[System.Drawing.FontStyle]::Bold)
    $Approved_Check.Location = New-Object System.Drawing.Size(5,95)
    $Approved_Check.Size = New-Object System.Drawing.Size(180,30)
  
 #$ApprovedValue =  $TSEnv.Value("Is_Approved")
    Logwrite -message ("Approved build variable value returned $approvedvalue") -component "Main()" -type 1

        if ($TSEnv.Value("Is_Approved") -eq 'True') {
            $Approved_Check.Location = New-Object System.Drawing.Size(400,95)
            $Approved_Check.Text = "Failed" 
            $Approved_Check.ForeColor = 'Red' 
            Logwrite -message  ("Is build approved = Fail") -component "Main()" -type 4
            Logwrite -message ("Machine is not a member of an approved build collection") -component "Main()" -type 1
            Logwrite -message ("Exit code: 8000") -component -type 1
            $OSDPreCheckExitCode = $OSDPreCheckExitCode + 8000
        }      
        else {
            $Approved_Check.Location = New-Object System.Drawing.Size(400,95)
            $Approved_Check.Text = "Pass" 
            $Approved_Check.ForeColor = 'Green'     
            Logwrite -message ("Is build approved = Pass") -component "Main()" -type 1
            Logwrite -message ("Machine is in an approved build collection") -component "Main()" -type 1
        }

    $Approved_Check.Text.controls
    $GeneralTab.Controls.Add($Approved_Check)

#endregion

#Region Nomad_check  #Checks to ensure to that nomad is installed and current.

    #$Nomad = 'false'
 
    $Nomad_Text = New-Object System.Windows.Forms.Label
    $Nomad_Text.AutoSize = $True
    $Nomad_Text.AutoSize =  'GrowAndShrink'
    $Nomad_Text.Font = New-Object System.Drawing.Font('Arial',16,[System.Drawing.FontStyle]::Bold)
    $Nomad_Text.Location = New-Object System.Drawing.Size(5,125)
    $Nomad_Text.Size = New-Object System.Drawing.Size(180,30)
    $Nomad_Text.Text = "Nomad Installed:"

    $Nomad_Text.Text.controls
    $GeneralTab.Controls.Add($Nomad_Text)

    $Nomad_Check= New-Object System.Windows.Forms.Label
    $Nomad_Check.AutoSize = $True
    $Nomad_Check.AutoSize =  'GrowAndShrink'
    $Nomad_Check.Font = New-Object System.Drawing.Font('Arial',16,[System.Drawing.FontStyle]::Bold)
    $Nomad_Check.Location = New-Object System.Drawing.Size(5,125)
    $Nomad_Check.Size = New-Object System.Drawing.Size(180,30)
   
 #$nomadCheckValue = $TSEnv.Value("Is_Nomad")   
    Logwrite -message ("Approved build variable value returned $nomadCheckValue") -component "Main()" -type 1

        if ($TSEnv.Value("Is_Nomad")   -eq 'True') {
            $Nomad_Check.Location = New-Object System.Drawing.Size(400,125)
            $Nomad_Check.Text = "Failed" 
            $Nomad_Check.ForeColor = 'Red' 
            Logwrite -message ("Nomad Check = Fail") -component "Main()" -type 4
            Logwrite -message ("The Nomad Client is not current or licensed on this machine, it must be remediated before build can continue") -component "Main()" -type 1
            Logwrite -message ("Exit code: 500") -component -type 1
            $OSDPreCheckExitCode = $OSDPreCheckExitCode + 500
        }      
        else {
            $Nomad_Check.Location = New-Object System.Drawing.Size(400,125)
            $Nomad_Check.Text = "Pass" 
            $Nomad_Check.ForeColor = 'Green'
            Logwrite -message ("Nomad Check = Pass") -component "Main()" -type 1
            Logwrite -message ("The Nomad client current and licensed, build can continue.") -component "Main()" -type 1     
        }

    $Nomad_Check.Text.controls
    $GeneralTab.Controls.Add($Nomad_Check)

#Endregion

#Region PowerCheck   #Checks to ensure to that Device is on AC Power.

    #$Power = 'false'
 
    $Power_Text = New-Object System.Windows.Forms.Label
    $Power_Text.AutoSize = $True
    $Power_Text.AutoSize =  'GrowAndShrink'
    $Power_Text.Font = New-Object System.Drawing.Font('Arial',16,[System.Drawing.FontStyle]::Bold)
    $Power_Text.Location = New-Object System.Drawing.Size(5,155)
    $Power_Text.Size = New-Object System.Drawing.Size(180,30)
    $Power_Text.Text = "AC Power:"
    $Power_Text.Text.controls
    $GeneralTab.Controls.Add($Power_Text)

    $Power_Check= New-Object System.Windows.Forms.Label
    $Power_Check.AutoSize = $True
    $Power_Check.AutoSize =  'GrowAndShrink'
    $Power_Check.Font = New-Object System.Drawing.Font('Arial',16,[System.Drawing.FontStyle]::Bold)
    $Power_Check.Location = New-Object System.Drawing.Size(5,155)
    $Power_Check.Size = New-Object System.Drawing.Size(180,30)
   
    #$PowerCheckValue = $TSEnv.Value("Is_Power_Connected")   
    Logwrite -message ("Approved build variable value returned $PowerCheckValue") -component "Main()" -type 1

        if ($TSEnv.Value("Is_Power_Connected") -eq 'True') {
            $Power_Check.Location = New-Object System.Drawing.Size(400,155)
            $Power_Check.Text = "Failed" 
            $Power_Check.ForeColor = 'Red' 
            Logwrite -message ("Power Check = Not Passed") -component "Main()" -type 4
            Logwrite -message ("The Device is currently running on Battery Power, AC power must be plugged in for the build to continue") -component "Main()" -type 1
            Logwrite -message ("Exit code: 50") -component -type 1
            $OSDPreCheckExitCode = $OSDPreCheckExitCode + 50
        }      
        else {
            $Power_Check.Location = New-Object System.Drawing.Size(400,155)
            $Power_Check.Text = "Pass" 
            $Power_Check.ForeColor = 'Green'
            Logwrite -message ("Power Check = Pass") -component "Main()" -type 1
            Logwrite -message ("The device is currently on AC power.") -component "Main()" -type 1     
        }

    $Nomad_Check.Text.controls
    $GeneralTab.Controls.Add($Power_Check)

#endregion

#Region Combine Error Codes

Logwrite -message ("$OSDPreCheckExitCode") -component "Main()" -type 1


#region Asset Tag 
#Get Asset tag from BIOS     
    $assettag = (Get-WmiObject -Class win32_systemenclosure).SMBIOSAssetTag
    $serial = (Get-CimInstance -classname win32_bios).serialnumber
Logwrite -message ("Asset Tag = $assettag") -component "Main()" -type 1
    if ($assettag-eq $null)
        {
            $compname = $serial
        }
        Else {
            $compname = $assettag
        }
 $assettag = New-Object System.Windows.Forms.Label
    $assettag.Location = New-Object System.Drawing.Size(10,255)
    $assettag.Size = New-Object System.Drawing.Size(180,30)
    $assettag.Font =New-Object System.Drawing.Font('Arial',10)
    $assettag.text = 'Asset Tag, as shown in BIOS, if available'
    $GeneralTab.Controls.Add($assettag)

    $objTextBox = New-Object System.Windows.Forms.TextBox
    $objTextBox.Location = New-Object System.Drawing.Size(10,230)
    $objTextBox.Size = New-Object System.Drawing.Size(180,40)
    $objTextBox.Font = New-Object System.Drawing.Font('Arial',10)
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
    $cmdprompt.Location = New-Object System.Drawing.Size(20,350)
    $cmdprompt.Size = New-Object System.Drawing.Size(250,15)
    $cmdprompt.Font = New-Object System.Drawing.Font ('Arial',10,[System.Drawing.FontStyle]::BOLD)
    $cmdprompt.ForeColor = [System.Drawing.Color]::'Green'

    $cmdprompt.Text = 'Press F8 for `ncmd prompt/PowerShell access.'
  #  $objForm.Controls.Add($cmdprompt)
    #New-Object System.Drawing.Font
    #('Arial',14,[System.Drawing.FontStyle]::Bold)
    #endregion

#Region CMTrace    
    #Function to open smsts.log with CMTrace, useful for troubleshooting
    function SMSTSLogButton {
        $smstslogButton = New-Object System.Windows.Forms.Button
        $smstslogButton.Location = New-Object System.Drawing.Size(270,350)
        $smstslogButton.Size = New-Object System.Drawing.Size(180,28)
        $smstslogButton.Text = 'CMTrace - smsts.log'
        $smstslogButton.Add_Click({
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
        $RestartButton.Location = New-Object System.Drawing.Size(50,350)
        $RestartButton.Size = New-Object System.Drawing.Size(120,28)
        $RestartButton.Text = 'Restart Computer'
        $RestartButton.Add_Click({
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

    #Commeneted out as this needs to be created in WINPE
    #$tsenv = New-Object -COMObject Microsoft.SMS.TSEnvironment


    #region OKButton
    #Continue button to confirm all choices and process to the task sequence wizard
    $OKButton = New-Object System.Windows.Forms.Button
    $OKButton.Location = New-Object System.Drawing.Size(570,350)
    $OKButton.Size = New-Object System.Drawing.Size(75,28)
    #$OKButton.BackColor = 'CornflowerBlue'
    $OKButton.Text = 'OK...'


    $OKButton.Add_Click({
        $objForm.Close()
        [System.Environment]::Exit($OSDPreCheckExitCode)

    })

    #region finishup
    #$OKbutton.add_Click($objForm.Close())
    $objForm.Controls.Add($OKButton)

    $OKButtonTooltip = New-Object System.Windows.Forms.ToolTip
    $OKButtonTooltip.AutomaticDelay = 0
    $OKButtonTooltip.AutoPopDelay = '10000'
    $OKButtonTooltip.ToolTipTitle ='OK button'
    $OKButtonTooltip.SetToolTip($OKButton, "Clicking OK will validate the selected options,`nif the Computername and build type have been entered `ncorrectly a confirmation box will appear")


    $objForm.Add_Shown({$objForm.Activate()})
    [void] $objForm.ShowDialog()
    #endregion
