--select *
--from mytable
--where lastlogindate < dateadd(d,-30,getdate()) 

select SYS.Netbios_Name0, SYS.AD_Site_Name0, OS.LastBootUpTime0 as 'Last Reboot', WS.LastHWScan as 'Last Reported to SMS'
from v_GS_Operating_System as OS
join v_r_system as SYS on OS.ResourceID=SYS.ResourceID
join v_gs_workstation_status as ws on sys.resourceid=ws.resourceid
Where WS.LastHWScan < dateadd(d,-1,getdate())
--and datediff(day,OS.LastBootUpTime0,getdate()) > '1'
Order by sys.Netbios_Name0, SYS.AD_Site_Name0, OS.LastBootUpTime0 

