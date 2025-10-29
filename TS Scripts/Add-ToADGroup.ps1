#md C:\Temp
$LogFile = "C:\windows\ccm\logs\Add-toADGRoup.log"
$ComputerName = $env:COMPUTERNAME

Function LogWrite
{
    Param ([string]$logstring)
    Add-content $LogFile -value $logstring
}

$Group = "This is your group name"
LogWrite "DefaultGroup: $Group"
try {
        LogWrite "ComputerName: $ComputerName"
        $ComputerDn = ([ADSISEARCHER]"sAMAccountName=$($env:COMPUTERNAME)$").FindOne().Path
        LogWrite "ComputerDn: $ComputerDn"
        $GroupDn = ([ADSISEARCHER]"sAMAccountName=$($Group)").FindOne().Path
        LogWrite "GroupDn: $GroupDn"
        $Group = [ADSI]"$GroupDn"
        LogWrite "Group: $Group"
        if(!$Group.IsMember($ComputerDn)) {
            $Group.Add($ComputerDn)
        LogWrite $_.Exception.Message
        LogWrite "Computer Added - Not in the Group"
        }
        LogWrite "Already in the Group"
    }
    catch {
        LogWrite $_.Exception.Message
        $_.Exception.Message ; Exit 1
    }