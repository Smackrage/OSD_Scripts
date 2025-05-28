
$KeyPath = "Computer\HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\Explorer\StartLayoutFile" 
try {
# Check if the registry key exists     
if (Test-Path "Registry::$KeyPath") 
{# Remove the registry key         
Remove-Item -Path "Registry::$KeyPath" -Recurse -Force  Write-Host "Registry key '$KeyPath' has been deleted."
} else 
{ Write-Host "Registry key '$KeyPath' does not exist."
}
} catch {
Write-Error "An error occurred while trying to delete the registry key: $_" 
}