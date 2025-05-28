 --Find Printers, Need to enable Printer section in MOF
 SELECT Distinct 
SYS.Netbios_Name0, 
PRT.Name0, PRT.ShareName0, 
PRT.DriverName0, PRT.DeviceID0, 
PRT.PortName0 FROM v_R_System 
SYS JOIN v_GS_PRINTER_DEVICE PRT
on SYS.ResourceID = PRT.ResourceID
WHERE PRT.PortName0 like 'ip%' or 
PRT.PortName0 like 'com%' or 
PRT.PortName0 like 'lpt%' or 
PRT.PortName0 like 'usb%' ORDER 
BY SYS.Netbios_Name0
