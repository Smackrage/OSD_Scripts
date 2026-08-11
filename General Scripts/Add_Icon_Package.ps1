<#
.SYNOPSIS
GUI to prep icons for SCCM + push to Application/Package.
- Browse & preview
- Resize to 256×256
- Try keep <100 KB (best-effort)
- Export PNG / ICO (256 & 32)
- Apply to SCCM (Application or Package) via SMS Provider

.NOTES
Author: Martin Smith
Date: 27/10/2025
Version: 1.2 (adds SCCM Apply: Application/Package + site connect)
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[void][System.Windows.Forms.Application]::EnableVisualStyles()

#region CMTrace logging ----------------------------------------------------------
function Get-LogRoot {
    if ($env:_SMSTSLogPath) { return $env:_SMSTSLogPath }
    if ($env:LOGPATH)       { return $env:LOGPATH }
    if (Test-Path 'C:\Windows\CCM\Logs') { return 'C:\Windows\CCM\Logs' }
    return 'C:\Windows\Temp'
}
$Script:LogFile = Join-Path (Get-LogRoot) ("IconTool_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))

function Write-CMTraceLog {
    param([Parameter(Mandatory)][string]$Message,[ValidateSet('1','2','3')][string]$Severity='1')
    $ts   = Get-Date -Format 'HH:mm:ss.fff'
    $date = Get-Date -Format 'MM-dd-yyyy'
    $tid  = [System.Threading.Thread]::CurrentThread.ManagedThreadId
    $line = "<![LOG[$Message]LOG]!><time=""$ts+600"" date=""$date"" component=""IconTool"" context=""""
thread=""$tid"" file=""""
severity=""$Severity"">"
    switch ($Severity) {
        '1' { Write-Host    "[INFO ] $Message" }
        '2' { Write-Warning "[WARN ] $Message" }
        '3' { Write-Error   "[ERROR] $Message" }
    }
    try { Add-Content -LiteralPath $Script:LogFile -Value $line -ErrorAction Stop } catch {}
}
#endregion -----------------------------------------------------------------------

#region SCCM connect + setters ---------------------------------------------------
function Connect-CMSite {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidatePattern('^[A-Z0-9]{3}$')][string]$SiteCode,
        [Parameter(Mandatory)][string]$ProviderMachineName
    )
    $cmModule = Join-Path $env:SMS_ADMIN_UI_PATH '..\ConfigurationManager.psd1'
    if (-not (Test-Path $cmModule)) {
        throw "Cannot find ConfigurationManager.psd1 (install the ConfigMgr console on this machine)."
    }
    Import-Module $cmModule -ErrorAction Stop
    if (-not (Get-PSDrive -Name $SiteCode -PSProvider 'AdminUI.PS.Provider\CMSite' -ErrorAction SilentlyContinue)) {
        New-PSDrive -Name $SiteCode -PSProvider "AdminUI.PS.Provider\CMSite" -Root $ProviderMachineName -ErrorAction Stop | Out-Null
    }
    Set-Location "$($SiteCode):" -ErrorAction Stop
    Write-CMTraceLog "Connected to site $SiteCode via $ProviderMachineName."
}

function Set-AppIcon {
    param([string]$Name, [string]$IconPath)
    $null = Get-CMApplication -Name $Name -Fast -ErrorAction Stop
    Set-CMApplication -Name $Name -IconLocationFile $IconPath -ErrorAction Stop
    Write-CMTraceLog "Set-CMApplication icon for '$Name' -> $IconPath"
}

function Set-PkgIcon {
    param([string]$Name, [string]$IconPath)
    $null = Get-CMPackage -Name $Name -Fast -ErrorAction Stop
    $supports = ($null -ne (Get-Command Set-CMPackage -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty Parameters |
        Select-Object -ExpandProperty Keys |
        Where-Object { $_ -eq 'IconLocationFile' }))
    if (-not $supports) {
        throw "This console/cmdlet does not support Set-CMPackage -IconLocationFile. Update your console/site build."
    }
    Set-CMPackage -Name $Name -IconLocationFile $IconPath -ErrorAction Stop
    Write-CMTraceLog "Set-CMPackage icon for '$Name' -> $IconPath"
}
#endregion -----------------------------------------------------------------------

#region Imaging helpers ----------------------------------------------------------
function New-ResizedBitmap {
    param(
        [Parameter(Mandatory)][System.Drawing.Image]$Image,
        [Parameter(Mandatory)][int]$Width,
        [Parameter(Mandatory)][int]$Height
    )
    $dest = New-Object System.Drawing.Bitmap -ArgumentList @(
        $Width, $Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    )
    $dest.SetResolution($Image.HorizontalResolution, $Image.VerticalResolution)
    $g = [System.Drawing.Graphics]::FromImage($dest)
    try {
        $g.CompositingMode    = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
        $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $g.InterpolationMode  = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.SmoothingMode      = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $g.PixelOffsetMode    = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.Clear([System.Drawing.Color]::Transparent)
        $destRect = New-Object System.Drawing.Rectangle 0,0,$Width,$Height
        $g.DrawImage($Image, $destRect, 0,0,$Image.Width,$Image.Height, [System.Drawing.GraphicsUnit]::Pixel)
    } finally { $g.Dispose() }
    return $dest
}

function Save-Png {
    param(
        [Parameter(Mandatory)][System.Drawing.Image]$Image,
        [Parameter(Mandatory)][string]$Path,
        [switch]$TryPalette8bit
    )
    $tmp = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(),'png')
    try {
        $Image.Save($tmp, [System.Drawing.Imaging.ImageFormat]::Png)
        $bytes = [System.IO.File]::ReadAllBytes($tmp)
        if ($TryPalette8bit.IsPresent -and $bytes.Length -gt 100KB) {
            Write-CMTraceLog "Attempting 8-bit palette reduction for PNG..."
            $reduced = Convert-To8bpp -Image $Image
            if ($null -ne $reduced) {
                $reduced.Save($tmp, [System.Drawing.Imaging.ImageFormat]::Png)
                $reduced.Dispose()
                $bytes = [System.IO.File]::ReadAllBytes($tmp)
                Write-CMTraceLog ("8-bit PNG size: {0:N0} bytes" -f $bytes.Length)
            } else {
                Write-CMTraceLog "8-bit conversion not available; keeping 32bpp." '2'
            }
        }
        [System.IO.File]::WriteAllBytes($Path,$bytes)
        return $bytes.Length
    } finally {
        try { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue } catch {}
    }
}

function Convert-To8bpp {
    param([Parameter(Mandatory)][System.Drawing.Image]$Image)
    try {
        $w,$h = $Image.Width, $Image.Height
        $bmpSrc = New-Object System.Drawing.Bitmap -ArgumentList @($Image)
        $bmpDst = New-Object System.Drawing.Bitmap -ArgumentList @(
            $w, $h, [System.Drawing.Imaging.PixelFormat]::Format8bppIndexed
        )

        # Palette (216 cube + greys)
        $pal = $bmpDst.Palette ; $idx = 0
        foreach ($r in 0..5) { foreach ($g in 0..5) { foreach ($b in 0..5) {
            if ($idx -ge 216) { break }
            $pal.Entries[$idx] = [System.Drawing.Color]::FromArgb([int](($r/5.0)*255), [int](($g/5.0)*255), [int](($b/5.0)*255)); $idx++
        }}}
        while ($idx -lt 256) {
            $grey = [int]((($idx-216)/40.0)*255); if ($grey -lt 0) { $grey=0 } ; if ($grey -gt 255) { $grey=255 }
            $pal.Entries[$idx] = [System.Drawing.Color]::FromArgb($grey,$grey,$grey); $idx++
        }
        $bmpDst.Palette = $pal

        $rect = [System.Drawing.Rectangle]::FromLTRB(0,0,$w,$h)
        $srcData = $bmpSrc.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $dstData = $bmpDst.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::WriteOnly, [System.Drawing.Imaging.PixelFormat]::Format8bppIndexed)
        try {
            $srcStride = [Math]::Abs($srcData.Stride)
            $dstStride = [Math]::Abs($dstData.Stride)
            for ($y=0; $y -lt $h; $y++) {
                $srcPtr = $srcData.Scan0 + ($y * $srcStride)
                $dstPtr = $dstData.Scan0 + ($y * $dstStride)
                for ($x=0; $x -lt $w; $x++) {
                    $b = [System.Runtime.InteropServices.Marshal]::ReadByte($srcPtr, ($x*4) + 0)
                    $g = [System.Runtime.InteropServices.Marshal]::ReadByte($srcPtr, ($x*4) + 1)
                    $r = [System.Runtime.InteropServices.Marshal]::ReadByte($srcPtr, ($x*4) + 2)
                    $ri = [Math]::Round(($r/255.0)*5); if ($ri -gt 5){$ri=5}
                    $gi = [Math]::Round(($g/255.0)*5); if ($gi -gt 5){$gi=5}
                    $bi = [Math]::Round(($b/255.0)*5); if ($bi -gt 5){$bi=5}
                    $index = [byte]($ri*36 + $gi*6 + $bi)
                    [System.Runtime.InteropServices.Marshal]::WriteByte($dstPtr, $x, $index)
                }
            }
        } finally {
            $bmpSrc.UnlockBits($srcData); $bmpDst.UnlockBits($dstData)
        }
        $bmpSrc.Dispose()
        return $bmpDst
    } catch {
        Write-CMTraceLog "Convert-To8bpp failed: $($_.Exception.Message)" '2'
        return $null
    }
}

function New-IcoBytes {
    param(
        [Parameter(Mandatory)][System.Drawing.Image]$Img256,
        [Parameter(Mandatory)][System.Drawing.Image]$Img32,
        [switch]$TryPalette8bit
    )
    function GetPngBytes([System.Drawing.Image]$im){
        $tmp = [System.IO.Path]::GetTempFileName() -replace '\.tmp$','.png'
        try {
            $null = Save-Png -Image $im -Path $tmp -TryPalette8bit:$TryPalette8bit
            return [System.IO.File]::ReadAllBytes($tmp)
        } finally {
            try { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue } catch {}
        }
    }
    $png256 = GetPngBytes $Img256
    $png32  = GetPngBytes $Img32

    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($ms)

    # ICONDIR
    $bw.Write([UInt16]0); $bw.Write([UInt16]1); $bw.Write([UInt16]2)
    $headerSize = 6 + (16 * 2)
    $offset1 = [UInt32]$headerSize
    $offset2 = [UInt32]($headerSize + $png256.Length)

    # 256 entry (width/height 0 = 256)
    $bw.Write([byte]0); $bw.Write([byte]0); $bw.Write([byte]0); $bw.Write([byte]0)
    $bw.Write([UInt16]1); $bw.Write([UInt16]32)
    $bw.Write([UInt32]$png256.Length); $bw.Write([UInt32]$offset1)

    # 32 entry
    $bw.Write([byte]32); $bw.Write([byte]32); $bw.Write([byte]0); $bw.Write([byte]0)
    $bw.Write([UInt16]1); $bw.Write([UInt16]32)
    $bw.Write([UInt32]$png32.Length); $bw.Write([UInt32]$offset2)

    $bw.Write($png256); $bw.Write($png32); $bw.Flush()
    return $ms.ToArray()
}
#endregion -----------------------------------------------------------------------

#region UI -----------------------------------------------------------------------------
$form               = New-Object System.Windows.Forms.Form
$form.Text          = "SCCM Icon Prep — 256x256 + <100KB + Apply to SCCM"
$form.StartPosition = 'CenterScreen'
$form.Size          = New-Object System.Drawing.Size(980, 660)

$btnBrowse          = New-Object System.Windows.Forms.Button
$btnBrowse.Text     = "Browse…"
$btnBrowse.Location = New-Object System.Drawing.Point(20,20)
$btnBrowse.Size     = New-Object System.Drawing.Size(100,30)

$txtPath            = New-Object System.Windows.Forms.TextBox
$txtPath.Location   = New-Object System.Drawing.Point(130,23)
$txtPath.Size       = New-Object System.Drawing.Size(820,24)

$pic                = New-Object System.Windows.Forms.PictureBox
$pic.Location       = New-Object System.Drawing.Point(20,60)
$pic.Size           = New-Object System.Drawing.Size(512,512)
$pic.BorderStyle    = 'FixedSingle'
$pic.SizeMode       = 'Zoom'

$lblMeta            = New-Object System.Windows.Forms.Label
$lblMeta.Location   = New-Object System.Drawing.Point(550, 60)
$lblMeta.Size       = New-Object System.Drawing.Size(400, 60)
$lblMeta.Text       = "No image loaded."

$chkResize          = New-Object System.Windows.Forms.CheckBox
$chkResize.Text     = "Resize to 256×256"
$chkResize.Location = New-Object System.Drawing.Point(550, 140)
$chkResize.Checked  = $true

$chkUnder100          = New-Object System.Windows.Forms.CheckBox
$chkUnder100.Text     = "Try to keep file < 100 KB"
$chkUnder100.Location = New-Object System.Drawing.Point(550, 170)
$chkUnder100.Checked  = $true

$btnExportPng         = New-Object System.Windows.Forms.Button
$btnExportPng.Text    = "Export PNG"
$btnExportPng.Location= New-Object System.Drawing.Point(550, 210)
$btnExportPng.Size    = New-Object System.Drawing.Size(120,30)

$btnExportIco         = New-Object System.Windows.Forms.Button
$btnExportIco.Text    = "Export ICO (256 & 32)"
$btnExportIco.Location= New-Object System.Drawing.Point(680, 210)
$btnExportIco.Size    = New-Object System.Drawing.Size(150,30)

# --- SCCM section ---
$grpSccm              = New-Object System.Windows.Forms.GroupBox
$grpSccm.Text         = "Apply to SCCM"
$grpSccm.Location     = New-Object System.Drawing.Point(550, 260)
$grpSccm.Size         = New-Object System.Drawing.Size(400, 230)

$rbApp                = New-Object System.Windows.Forms.RadioButton
$rbApp.Text           = "Application"
$rbApp.Location       = New-Object System.Drawing.Point(20,30)
$rbApp.Checked        = $true

$rbPkg                = New-Object System.Windows.Forms.RadioButton
$rbPkg.Text           = "Package"
$rbPkg.Location       = New-Object System.Drawing.Point(140,30)

$lblName              = New-Object System.Windows.Forms.Label
$lblName.Text         = "Object Name:"
$lblName.Location     = New-Object System.Drawing.Point(20,65)
$lblName.Size         = New-Object System.Drawing.Size(90,20)

$txtName              = New-Object System.Windows.Forms.TextBox
$txtName.Location     = New-Object System.Drawing.Point(120,62)
$txtName.Size         = New-Object System.Drawing.Size(250,24)

$lblSite              = New-Object System.Windows.Forms.Label
$lblSite.Text         = "Site Code:"
$lblSite.Location     = New-Object System.Drawing.Point(20,95)
$lblSite.Size         = New-Object System.Drawing.Size(90,20)

$txtSite              = New-Object System.Windows.Forms.TextBox
$txtSite.Location     = New-Object System.Drawing.Point(120,92)
$txtSite.Size         = New-Object System.Drawing.Size(80,24)

$lblProv              = New-Object System.Windows.Forms.Label
$lblProv.Text         = "Provider:"
$lblProv.Location     = New-Object System.Drawing.Point(20,125)
$lblProv.Size         = New-Object System.Drawing.Size(90,20)

$txtProv              = New-Object System.Windows.Forms.TextBox
$txtProv.Location     = New-Object System.Drawing.Point(120,122)
$txtProv.Size         = New-Object System.Drawing.Size(250,24)

$chkUseLastSaved      = New-Object System.Windows.Forms.CheckBox
$chkUseLastSaved.Text = "Use last exported ICO if available (otherwise generate temp)"
$chkUseLastSaved.Location = New-Object System.Drawing.Point(20,155)
$chkUseLastSaved.Size  = New-Object System.Drawing.Size(360,20)
$chkUseLastSaved.Checked = $true

$btnApplySccm         = New-Object System.Windows.Forms.Button
$btnApplySccm.Text    = "Apply to SCCM"
$btnApplySccm.Location= New-Object System.Drawing.Point(20,185)
$btnApplySccm.Size    = New-Object System.Drawing.Size(150,30)

$grpSccm.Controls.AddRange(@(
    $rbApp,$rbPkg,$lblName,$txtName,$lblSite,$txtSite,$lblProv,$txtProv,$chkUseLastSaved,$btnApplySccm
))

$lblStatus            = New-Object System.Windows.Forms.Label
$lblStatus.Location   = New-Object System.Drawing.Point(550, 510)
$lblStatus.Size       = New-Object System.Drawing.Size(400, 90)
$lblStatus.Text       = "Status: idle"

$form.Controls.AddRange(@(
    $btnBrowse,$txtPath,$pic,$lblMeta,$chkResize,$chkUnder100,$btnExportPng,$btnExportIco,
    $grpSccm,$lblStatus
))

$fd = New-Object System.Windows.Forms.OpenFileDialog
$fd.Filter = "Images|*.png;*.jpg;*.jpeg;*.bmp;*.ico|All files|*.*"

$global:LoadedImage   = $null
$global:LastExportIco = $null

function Load-Image($path){
    try {
        if ($global:LoadedImage) { $global:LoadedImage.Dispose(); $global:LoadedImage = $null }
        $fs = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        try { $img = [System.Drawing.Image]::FromStream($fs) } finally { $fs.Dispose() }
        $global:LoadedImage = $img
        $pic.Image = $img
        $lblMeta.Text = "Loaded: {0}x{1}`r`nFormat: {2}" -f $img.Width,$img.Height,$img.RawFormat.Guid
        Write-CMTraceLog "Loaded image: $path ($($img.Width)x$($img.Height))"
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Failed to load: $path`n$($_.Exception.Message)","Load error",'OK','Error') | Out-Null
        Write-CMTraceLog "Load failed: $($_.Exception.Message)" '3'
    }
}

$btnBrowse.Add_Click({
    if ($fd.ShowDialog() -eq 'OK') {
        $txtPath.Text = $fd.FileName
        Load-Image $fd.FileName
    }
})

function Get-Working256 {
    if (-not $global:LoadedImage) { return $null }
    if ($chkResize.Checked) {
        return New-ResizedBitmap -Image $global:LoadedImage -Width 256 -Height 256
    } else {
        if ($global:LoadedImage.Width -eq 256 -and $global:LoadedImage.Height -eq 256) {
            return New-Object System.Drawing.Bitmap -ArgumentList @($global:LoadedImage)
        } else {
            return New-ResizedBitmap -Image $global:LoadedImage -Width 256 -Height 256
        }
    }
}

function Get-Working32 {
    if (-not $global:LoadedImage) { return $null }
    return New-ResizedBitmap -Image $global:LoadedImage -Width 32 -Height 32
}

$btnExportPng.Add_Click({
    try {
        if (-not $global:LoadedImage) { return }
        $pngSave = New-Object System.Windows.Forms.SaveFileDialog
        $pngSave.Filter = "PNG image|*.png"
        $pngSave.FileName = "icon_256.png"
        if ($pngSave.ShowDialog() -ne 'OK') { return }

        $img256 = Get-Working256
        try {
            $size = Save-Png -Image $img256 -Path $pngSave.FileName -TryPalette8bit:$chkUnder100.Checked
        } finally { if ($img256) { $img256.Dispose() } }

        $lblStatus.Text = "Saved PNG: {0} bytes" -f $size
        Write-CMTraceLog ("Saved PNG to {0} ({1:N0} bytes)" -f $pngSave.FileName,$size)
    } catch {
        $lblStatus.Text = "PNG export failed."
        Write-CMTraceLog "PNG export failed: $($_.Exception.Message)" '3'
    }
})

$btnExportIco.Add_Click({
    try {
        if (-not $global:LoadedImage) { return }
        $icoSave = New-Object System.Windows.Forms.SaveFileDialog
        $icoSave.Filter = "Icon (*.ico)|*.ico"
        $icoSave.FileName = "icon.ico"
        if ($icoSave.ShowDialog() -ne 'OK') { return }

        $img256 = Get-Working256
        $img32  = Get-Working32
        try {
            $bytes = New-IcoBytes -Img256 $img256 -Img32 $img32 -TryPalette8bit:$chkUnder100.Checked
        } finally { if ($img256) { $img256.Dispose() }; if ($img32) { $img32.Dispose() } }

        [System.IO.File]::WriteAllBytes($icoSave.FileName, $bytes)
        $global:LastExportIco = $icoSave.FileName
        $lblStatus.Text = "Saved ICO: {0} bytes" -f $bytes.Length
        Write-CMTraceLog ("Saved ICO to {0} ({1:N0} bytes)" -f $icoSave.FileName,$bytes.Length)
    } catch {
        $lblStatus.Text = "ICO export failed."
        Write-CMTraceLog "ICO export failed: $($_.Exception.Message)" '3'
    }
})

$btnApplySccm.Add_Click({
    try {
        if (-not $global:LoadedImage) {
            [System.Windows.Forms.MessageBox]::Show("Load an image first.","Heads up",'OK','Information') | Out-Null
            return
        }
        if ([string]::IsNullOrWhiteSpace($txtName.Text) -or [string]::IsNullOrWhiteSpace($txtSite.Text) -or [string]::IsNullOrWhiteSpace($txtProv.Text)) {
            [System.Windows.Forms.MessageBox]::Show("Please fill in Object Name, Site Code, and Provider.","Missing info",'OK','Information') | Out-Null
            return
        }

        # Determine ICO path to use
        $icoPath = $null
        if ($chkUseLastSaved.Checked -and $global:LastExportIco -and (Test-Path $global:LastExportIco)) {
            $icoPath = $global:LastExportIco
            Write-CMTraceLog "Using last exported ICO: $icoPath"
        } else {
            # Generate a temp ICO from current preview (256 & 32)
            $img256 = Get-Working256
            $img32  = Get-Working32
            try {
                $bytes = New-IcoBytes -Img256 $img256 -Img32 $img32 -TryPalette8bit:$chkUnder100.Checked
            } finally { if ($img256) { $img256.Dispose() }; if ($img32) { $img32.Dispose() } }
            $icoPath = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), ("icon_{0}.ico" -f ([System.Guid]::NewGuid().ToString("N"))))
            [System.IO.File]::WriteAllBytes($icoPath, $bytes)
            Write-CMTraceLog "Generated temp ICO for SCCM apply: $icoPath"
        }

        # Connect + apply
        Write-CMTraceLog "Connecting to site $($txtSite.Text) via $($txtProv.Text)..."
        Connect-CMSite -SiteCode $txtSite.Text.ToUpper() -ProviderMachineName $txtProv.Text

        if ($rbApp.Checked) {
            Set-AppIcon -Name $txtName.Text -IconPath $icoPath
            $lblStatus.Text = "Applied icon to Application '$($txtName.Text)'."
        } else {
            Set-PkgIcon -Name $txtName.Text -IconPath $icoPath
            $lblStatus.Text = "Applied icon to Package '$($txtName.Text)'."
        }

        [System.Windows.Forms.MessageBox]::Show("Done. If Software Center hasn’t refreshed yet, trigger Machine/User Policy Retrieval.","Success",'OK','Information') | Out-Null
    } catch {
        $msg = $_.Exception.Message
        $lblStatus.Text = "Apply failed."
        Write-CMTraceLog "Apply to SCCM failed: $msg" '3'
        [System.Windows.Forms.MessageBox]::Show("Apply failed:`r`n$msg","Error",'OK','Error') | Out-Null
    }
})

[void]$form.ShowDialog()

if ($global:LoadedImage) { $global:LoadedImage.Dispose() }
Write-CMTraceLog "Closed UI. Log at: $Script:LogFile"
