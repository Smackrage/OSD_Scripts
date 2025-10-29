<#
.SYNOPSIS
Read OU from file, validate it, and fall back if missing (WinPE-safe; no cmdlets).

.DESCRIPTION
- Reads OU path from X:\Windows\Temp\OU.txt.
- Validates OU by binding with DirectoryServices.
- If OU doesn’t exist, switches to fallback OU.
- Logs actions in CMTrace format.

.NOTES
Author: Martin Smith (Data #3)
Date: 01/09/2025
Version: 1.2 
#>

# =========================
# ==== Configuration  =====
# =========================

$OUFile    = "X:\Windows\Temp\OU.txt"
$fallbackOU = "LDAP://OU=PRD,OU=Windows11,OU=EndUserDevices,DC=contoso,DC=internal"

$ldapUser = $null   # e.g. "Contoso\\SomeJoinAcct"
$ldapPass = $null   # e.g. "SuperSecret"

$logPath = "X:\Windows\Temp\OUCheck.log"

# =========================
# ======  Logging   =======
# =========================

function Write-CMTraceLine {
    param(
        [string]$Message,
        [int]$Type = 1,
        [string]$Component = "OUCheck",
        [string]$LogFile = $logPath
    )

    try {
        $now   = [DateTime]::Now
        $time  = $now.ToString("HH:mm:ss.fff")
        $date  = $now.ToString("MM-dd-yyyy")
        $line  = "<!LOG!>$Message<!><time=""$time"" date=""$date"" component=""$Component"" context="""" type=""$Type"" thread="""" file="""">"

        $dir = [System.IO.Path]::GetDirectoryName($LogFile)
        if (![string]::IsNullOrWhiteSpace($dir) -and -not [System.IO.Directory]::Exists($dir)) {
            [System.IO.Directory]::CreateDirectory($dir)
        }

        $sw = [System.IO.StreamWriter]::new($LogFile, $true, [System.Text.Encoding]::UTF8)
        $sw.WriteLine($line)
        $sw.Dispose()
    } catch {
        [System.Console]::WriteLine(("LOGWRITEFAIL: {0}" -f $Message))
    }
}

# =========================
# ===  LDAP Utilities  ====
# =========================

try { [void][System.Reflection.Assembly]::LoadWithPartialName("System.DirectoryServices") } catch {}

function Test-LdapPathExists {
    param(
        [string]$LdapPath,
        [string]$Username,
        [string]$Password
    )
    try {
        if ([string]::IsNullOrWhiteSpace($LdapPath)) {
            Write-CMTraceLine "Empty LDAP path provided." 3
            return $false
        }

        $de = if ($Username -and $Password) {
            [System.DirectoryServices.DirectoryEntry]::new($LdapPath, $Username, $Password)
        } else {
            [System.DirectoryServices.DirectoryEntry]::new($LdapPath)
        }

        $null = $de.NativeObject
        $schemaClassName = $de.SchemaClassName
        if ($schemaClassName -and -not $schemaClassName.Equals("organizationalUnit", [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-CMTraceLine ("Path bound but SchemaClassName='{0}' (expected organizationalUnit)." -f $schemaClassName) 2
        }
        $de.Dispose()
        return $true
    }
    catch {
        Write-CMTraceLine ("Bind failed for '{0}'. Error: {1}" -f $LdapPath, $_.Exception.Message) 2
        return $false
    }
}

# =========================
# =====  Main Logic  ======
# =========================

$OU = $null

try {
    if ([System.IO.File]::Exists($OUFile)) {
        $lines = [System.IO.File]::ReadAllLines($OUFile)
        if ($lines.Length -gt 0) {
            $OU = $lines[0].Trim()
        }
    }
} catch {
    Write-CMTraceLine ("Failed to read OU from file {0}. Error: {1}" -f $OUFile, $_.Exception.Message) 3
}

if ([string]::IsNullOrWhiteSpace($OU)) {
    Write-CMTraceLine ("OU file missing or empty. Defaulting to fallback '{0}'." -f $fallbackOU) 2
    $OU = $fallbackOU
}

Write-CMTraceLine ("Validating OU '{0}'..." -f $OU) 1

if (Test-LdapPathExists -LdapPath $OU -Username $ldapUser -Password $ldapPass) {
    Write-CMTraceLine ("OU exists: '{0}'" -f $OU) 1
} else {
    Write-CMTraceLine ("OU invalid. Falling back to '{0}'" -f $fallbackOU) 2
    $OU = $fallbackOU
}

# Echo final OU (so TS or wrapper can pick it up)
[System.Console]::WriteLine(("OU={0}" -f $OU))

# Optionally overwrite the file with final OU
try {
    [System.IO.File]::WriteAllText($OUFile, $OU)
} catch {
    Write-CMTraceLine ("Failed to overwrite OU file. Error: {0}" -f $_.Exception.Message) 2
}
