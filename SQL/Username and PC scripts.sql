USE Sms_syd

SELECT 
	Name0,
	Username0	 
FROM computer_system_data
WHERE name0 like 'VDM%'
--ORDER BY name0 asc

-------------------------------------
--People Finder

SELECT 
	v_r_system.Name0 as SystemName,
	MIN(v_r_system.User_Name0) as UserName
    FROM v_r_user u inner join
      v_r_system on u.User_Name0 = v_r_system.User_Name0 inner join
      v_RA_System_SMSAssignedSites on v_RA_System_SMSAssignedSites.ResourceID = v_r_system.ResourceID inner join
      v_RA_System_IPAddresses on v_r_system.ResourceID = v_RA_System_IPAddresses.ResourceID
    WHERE (u.User_Name0 LIKE '%') AND (IP_Addresses0 NOT LIKE '172.22.22.%')
    GROUP BY v_r_system.Name0

------------------------------------
-- PC and username script
Select * from v_r_user
Select 
	User_Name0,
	Name0
 From v_r_system
WHERE Name0 LIKE 'VDM%'