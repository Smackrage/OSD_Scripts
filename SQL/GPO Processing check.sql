USE SMS_M01
select
	a.Name0,
	a.User_Name0,
	a.Operating_System_Name_and0,
	CONVERT(VARCHAR(12),b.ModifiedDate,107)As "GPO Date Last Applied"
from v_R_System a join v_GS_SoftwareFile b on b.ResourceID=a.ResourceID
where b.FileName='secedit.sdb'
and DATEDIFF(dd,b.ModifiedDate,GetDate()) > 10
order by b.ModifiedDate