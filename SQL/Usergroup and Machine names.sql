USE SMS_M01
SELECT 
	Vsys.Name0 AS 'Machine Name',
	Vuse.Full_user_name0 AS 'Username',
	Vgrp.User_group_name0 AS 'Group Name',
	Vsys.AD_Site_Name0 AS 'Location'
FROM v_R_User AS Vuse
INNER JOIN v_RA_User_UserGroupName AS Vgrp
   ON Vgrp.ResourceID = Vuse.ResourceID
INNER JOIN v_R_System AS Vsys
   ON Vsys.User_Name0 = Vuse.User_Name0
WHERE User_Group_Name0 = '%Domain%\Standard Applications Pilot Group'
ORDER BY Vuse.Name0