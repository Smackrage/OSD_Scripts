<#
Fix-StartSearch.ps1  (Windows 11)
- Resets Windows Search index (cleanly).
- Re-registers key shell/system apps (Search, StartMenuExperienceHost, ShellExperienceHost).
- Restarts shell & Windows Search service.
- Optional SFC/DISM OS repair.
- CMTrace-style logging to C:\Temp\logs\Fix_StartSearch.log

USAGE (Run as Admin):
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Fix-StartSearch.ps1
  # Optional repair:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Fix-StartSearch.ps1 -RepairOS
#>

[CmdletBinding()]
param(
  [switch]$RepairOS
)

# ===== Guard: Admin =====
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Write-Host "Please run this script as Administrator." -ForegroundColor Yellow
  exit 1
}

# ===== Logging (CMTrace-compatible) =====
$LogRoot = "C:\Temp\logs"
$LogFile = Join-Path $LogRoot "Fix_StartSearch.log"
if (-not (Test-Path $LogRoot)) { New-Item -Path $LogRoot -ItemType Directory -Force | Out-Null }
New-Item -Path $LogFile -ItemType File -Force | Out-Null

function Write-Log {
  param(
    [Parameter(Mandatory)][string]$Message,
    [ValidateSet('1','2','3')][string]$Severity = '1', # 1=Info,2=Warn,3=Error
    [string]$Component = 'Fix-StartSearch'
  )
  $ts = Get-Date -Format "MM-dd-yyyy HH:mm:ss.fff"
  "$ts,$PID,$Component,$Message,$Severity" | Out-File -FilePath $LogFile -Append -Encoding UTF8
  if ($Severity -eq '3') { Write-Host $Message -ForegroundColor Red }
  elseif ($Severity -eq '2') { Write-Host $Message -ForegroundColor Yellow }
  else { Write-Host $Message }
}

# ===== Helpers =====
function Stop-ProcessSafe {
  param([string[]]$Names)
  foreach ($n in $Names) {
    try {
      Get-Process -Name $n -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
      Write-Log "Stopped process: $n"
    } catch {
      Write-Log "Failed stopping process: $n -> $($_.Exception.Message)" '2'
    }
  }
}

function ReRegister-SystemApp {
  param([string]$FolderName) # e.g. Microsoft.Windows.Search
  try {
    $systemApps = Join-Path $env:WINDIR "SystemApps"
    $folders = Get-ChildItem -Path $systemApps -Directory -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -like "$FolderName*" }
    $manifest = $null
    foreach ($folder in $folders) {
      $manifestPath = Join-Path $folder.FullName "AppxManifest.xml"
      if (Test-Path $manifestPath) {
        $manifest = Get-Item $manifestPath
        break
      }
    }
    if ($manifest) {
      Add-AppxPackage -DisableDevelopmentMode -Register $manifest.FullName -ErrorAction Stop
      Write-Log "Re-registered $FolderName"
    } else {
      Write-Log "Manifest not found for $FolderName" '2'
    }
  } catch {
    Write-Log "Re-register failed for $FolderName -> $($_.Exception.Message)" '2'
  }
}

# ===== Start =====
Write-Log "=== Fix Start/Search: begin ==="

# 1) Stop Windows Search service + related processes
try {
  Write-Log "Stopping WSearch service..."
  try {
    Stop-Service -Name WSearch -Force -ErrorAction Stop
    Write-Log "WSearch service stopped."
  } catch {
    Write-Log "Failed to stop WSearch service -> $($_.Exception.Message)" '2'
  }
  Stop-ProcessSafe -Names @('SearchHost','StartMenuExperienceHost','ShellExperienceHost','SearchApp','RuntimeBroker','explorer')
} catch {
  Write-Log "Error while stopping components -> $($_.Exception.Message)" '2'
}

# 2) Reset the Search index store (clean rebuild)
$SearchRoot = "C:\ProgramData\Microsoft\Search"
$AppsPath   = Join-Path $SearchRoot "Data\Applications\Windows"
$TempPath   = Join-Path $SearchRoot "Data\Temp"
$stamp      = (Get-Date).ToString('yyyyMMdd_HHmmss')

try {
  if (Test-Path $AppsPath) {
    $backup = "$AppsPath.bak_$stamp"
    Write-Log "Backing up index store to $backup"
    Rename-Item -Path $AppsPath -NewName (Split-Path $backup -Leaf) -ErrorAction Stop
  }
  if (Test-Path $TempPath) {
    Remove-Item -Path $TempPath -Recurse -Force -ErrorAction SilentlyContinue
  }
  Write-Log "Search index store reset queued (will rebuild on service start)."
} catch {
  Write-Log "Index store reset error -> $($_.Exception.Message)" '2'
}

# 3) Re-register core system apps tied to Start/Search (SystemApps, not user Appx)
ReRegister-SystemApp -FolderName "Microsoft.Windows.Search"
ReRegister-SystemApp -FolderName "Microsoft.Windows.StartMenuExperienceHost"
ReRegister-SystemApp -FolderName "Microsoft.Windows.ShellExperienceHost"

# 4) Restart Windows Search service
try {
  Set-Service -Name WSearch -StartupType Automatic
  Start-Service -Name WSearch
  Write-Log "WSearch started."
} catch {
  Write-Log "Failed to start WSearch -> $($_.Exception.Message)" '3'
}

# 5) Restart Explorer (refresh Start & taskbar)
try {
  Start-Process explorer.exe
  Write-Log "Explorer restarted."
} catch {
  Write-Log "Failed to restart Explorer -> $($_.Exception.Message)" '2'
}

# 6) Optional: OS health repair
if ($RepairOS) {
  try {
    Write-Log "Starting DISM /RestoreHealth (this can take a while)..."
    Start-Process -FilePath dism.exe -ArgumentList "/Online","/Cleanup-Image","/RestoreHealth" -Wait -NoNewWindow
    Write-Log "DISM completed."

    Write-Log "Starting SFC /scannow..."
    Start-Process -FilePath sfc.exe -ArgumentList "/scannow" -Wait -NoNewWindow
    Write-Log "SFC completed."
  } catch {
    Write-Log "OS repair step failed -> $($_.Exception.Message)" '2'
  }
}

# 7) Quick sanity: confirm Search service & SearchHost are alive
try {
  $svc = Get-Service WSearch -ErrorAction SilentlyContinue
  $proc = Get-Process -Name SearchHost -ErrorAction SilentlyContinue
  $procIdStr = if ($proc) { ($proc.Id -join ',') } else { 'N/A' }
  Write-Log ("Status -> WSearch:{0}, SearchHost PID:{1}" -f $svc.Status, $procIdStr)
} catch {
  Write-Log "Status check failed -> $($_.Exception.Message)" '2'
}

Write-Host "`nDone. If Search doesn't work immediately, give it a minute to rebuild the index. Log: $LogFile"
exit 0
