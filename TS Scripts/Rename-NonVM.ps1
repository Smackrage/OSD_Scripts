$TSEnv = New-Object -ComObject Microsoft.SMS.TSEnvironment

$ComputerName = "V1-" + (Get-CimInstance -ClassName Win32_Bios).SerialNumber

$TSEnv.Value("OSDComputerName") = $ComputerName