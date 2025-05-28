SELECT 
	v_R_SYSTEM.Name0
	v_R_System.AD_Site_Name0,
	v_R_SYSTEM.SMS_Unique_Identifier0,
	v_R_SYSTEM.Resource_Domain_OR_Workgr0,
	v_R_SYSTEM.Client0,v_R_SYSTEM.ResourceID,
	v_R_SYSTEM.ResourceType 
FROM 
v_R_System INNER JOIN v_GS_COMPUTER_SYSTEM ON
 v_GS_COMPUTER_SYSTEM.ResourceID = v_R_System.ResourceId 
WHERE v_GS_COMPUTER_SYSTEM.Name0 
NOT IN
 (select distinct v_GS_COMPUTER_SYSTEM.Name0 
from 
 v_R_System INNER JOIN v_GS_COMPUTER_SYSTEM ON
 v_GS_COMPUTER_SYSTEM.ResourceID = v_R_System.ResourceId 
INNER JOIN v_GS_ADD_REMOVE_PROGRAMS ON
 v_GS_ADD_REMOVE_PROGRAMS.ResourceID = v_R_System.ResourceId 
WHERE v_GS_ADD_REMOVE_PROGRAMS.DisplayName0 LIKE @variable )
ORDER BY v_R_SYSTEM.Name0