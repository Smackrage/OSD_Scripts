SELECT DISTINCT 
v_R_System.Name0 'Computer', 
v_GS_OPERATING_SYSTEM.Description0 'Computer Description', 
v_GS_OPERATING_SYSTEM.LastBootUpTime0, 
v_GS_PatchStatusEx.LastStateName 
FROM 
v_R_System 
INNER JOIN v_FullCollectionMembership ON v_R_System.ResourceID = v_FullCollectionMembership.ResourceId 
INNER JOIN v_GS_OPERATING_SYSTEM ON v_R_System.ResourceID = v_GS_OPERATING_SYSTEM.ResourceID 
INNER JOIN v_GS_PatchStatusEx ON v_R_System.ResourceID = v_GS_PatchStatusEx.ResourceID 
WHERE 
v_FullCollectionMembership.CollectionID = 'SMS00001' 
AND 
v_GS_PatchStatusEx.LastStateName = 'Reboot pending' 
ORDER BY 
v_GS_OPERATING_SYSTEM.LastBootUpTime0