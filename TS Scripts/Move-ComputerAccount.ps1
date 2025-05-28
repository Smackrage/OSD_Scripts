$LogFile = "C:\windows\ccm\logs\MoveComputerOU.log"

$ComputerName = $env:COMPUTERNAME

 

Function LogWrite

{

    Param ([string]$logstring)

    Add-content $LogFile -value $logstring

}

 

$WarningPreference = "SilentlyContinue"

 

$PSVer = $PSVersionTable.PSVersion.Major

LogWrite "Starting executing script. Using PS version: $PSVer"

 

$ArchProcess = [System.Environment]::Is64BitProcess

LogWrite "Is this 64bit Process? : $ArchProcess"

 

$ComputerOUName = 'LDAP://OU=PRD,OU=Windows11,OU=EndUserDevices,DC=Company,DC=internal'

Try

{

    LogWrite "Querying LDAP for Computer Account"

    $objSysInf = New-Object -ComObject "ADSystemInfo"

    $CurrentComputer = [ADSI]("LDAP://{0}" -f $objSysInf.GetType().InvokeMember("ComputerName", [System.Reflection.BindingFlags]::GetProperty, $null, $objSysInf, $null))

    $ComputerCurrentOU = ([ADSI]$CurrentComputer.Parent).Path

    $ComputerDN = $CurrentComputer.distinguishedName

    $ComputerTargetOU = [ADSI]$ComputerOUName

    LogWrite "Current OU: $ComputerCurrentOU"

    LogWrite "Target OU: $ComputerOUName"

}

Catch

{

    LogWrite "Error: $error[0]"

}

 

If ($ComputerCurrentOU -ne $ComputerOUName)

{

    Try

    {

        LogWrite "Moving Computer $ComputerDN object to $ComputerOUName"

        $objADComputer = [ADSI]"LDAP://$ComputerDN"

        LogWrite $objADComputer.distinguishedName

        $objADComputer.psbase.MoveTo($ComputerTargetOU)

        LogWrite "Move completed."

    }

    Catch

    {

    LogWrite "Error: $Error[0]"   

    Write-Error "Error: $Error[0]"

    }

}

Else

{

    LogWrite "Computer already in correct OU: $ComputerCurrentOU"

}