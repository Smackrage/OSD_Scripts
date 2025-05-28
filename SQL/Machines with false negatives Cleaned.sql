select distinct vr.name0 
into #tmp
from v_ClientAdvertisementStatus cs 
join v_Add_Remove_Programs arp on arp.resourceid= cs.resourceid
join v_R_System vr on vr.resourceid= cs.resourceid
where cs.laststatename = 'Failed'
and arp.displayname0 = 'Windows Internet Explorer 7'
and cs.AdvertisementID = 'M0120078'
--Order by arp.installdate0


declare @displayname varchar (max)
Declare @CollID Varchar (10)
set @displayname ='Windows Internet Explorer 7'
Set @CollID = 'SMS000ES'

Select sys.Netbios_Name0, fcm.SiteCode,  sys.User_Domain0, sys.User_Name0, sys.Operating_System_Name_and0, arp.DisplayName0 
FROM v_R_System sys
JOIN v_Add_Remove_Programs arp ON sys.ResourceID = arp.ResourceID 
JOIN v_FullCollectionMembership fcm on sys.ResourceID=fcm.ResourceID
WHERE DisplayName0 = @displayname and fcm.CollectionID=@CollID
and exists (select * from #tmp where name0 = sys.name0)

Drop table #tmp
