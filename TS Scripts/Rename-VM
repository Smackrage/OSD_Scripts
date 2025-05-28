Function LogWrite

{

    Param ([string]$logstring)

    Add-content $LogFile -value $logstring

}

 

$TSEnv = New-Object -ComObject Microsoft.SMS.TSEnvironment

$Network = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration | where {$_.Description -like 'vmxnet3*'}

$MACAddress = $Network.MACAddress -replace ':',''

Logwrite "MAC Address value is: $MacAddress"

$ComputerName = "V1-" + $MACAddress

Logwrite "OSD Computername will be set to - $computername"

$TSEnv.Value("OSDComputerName") = $ComputerName

Logwrite "OSD Computername is set to: $TSEnv.value("OSDComputerName")"

 