--Floor: Based off location Boundary added as IP range, and that each floor/location has it's own subnet.
SELECT 'All' as Floor
UNION ALL
SELECT 
BI.DisplayName AS Floor
FROM dbo.v_BoundaryInfo BI
WHERE BI.DisplayName != 'NULL'
AND BI.DisplayName NOT LIKE '172.%'
AND BI.DisplayName != 'Sydney - Citrix'
AND BI.DisplayName NOT LIKE 'Citrix%' 
Order by 1


-- Main Query: Count of Adobe Acrobat installations with Desk Location
SELECT 
	syst.name0 [Machine Name], 
	Syst.Operating_System_Name_and0,
	US.displayName0  [User Name],
	US.physicalDeliveryOfficeNam0 [Desk Location],
	arp.version0     [Adobe Version], 
	RBI.IPSubnet,
	RBI.DisplayName [Floor],
      -- CHARINDEX('- English, Français, Deutsch' ,RTRIM(arp.DisplayName0)) AS [CHARINDEX],
    CASE
    WHEN CHARINDEX(' - English, Français, Deutsch' ,RTRIM(arp.DisplayName0) ,-1) = 0 THEN ARP.DIsplayname0
    ELSE SUBSTRING(arp.displayname0, 1,CHARINDEX(' - English, Français, Deutsch' ,RTRIM(arp.DisplayName0) ,-1))
    END as [Adobe Name]
    FROM   v_gs_add_remove_programs AS arp 
		INNER JOIN v_r_system AS syst 
		ON arp.resourceid = syst.resourceid 
		INNER JOIN v_RA_System_IPSubnets IP
		on SYST.resourceid=IP.resourceid
		INNER JOIN v_GS_WORKSTATION_STATUS WS
		on SYST.resourceID=WS.resourceID
		LEFT OUTER JOIN RoamingBoundaryIPSubnet RBI
		on IP.IP_Subnets0=RBI.IPSubnet    
		INNER JOIN v_R_User as US 
		on syst.User_Name0=US.User_Name0 
WHERE  RBI.DisplayName = @Floor
		AND SYST.Operating_System_Name_and0 NOT LIKE '%server%'
		AND RBI.DisplayName != 'NULL'
		AND arp.publisher0 = 'Adobe Systems' 
		AND 
		(
		arp.prodid0 IN
			( 
			'{AC76BA86-1033-F400-BA7E-000000000004}' --'Adobe Acrobat  9 Standard - English, Français, Deutsch' 
			,'{AC76BA86-1033-F400-7760-000000000004}' --'Adobe Acrobat 9 Pro - English, Français, Deutsch' 
			,'{AC76BA86-1033-F400-7760-000000000005}' --'Adobe Acrobat X Pro - English, Français, Deutsch' 
			,'Adobe Acrobat 7.0 Standard - V' --'Adobe Acrobat 7.0.7 Standard' 
			,'{AC76BA86-1033-0000-7760-100000000002}' --'Adobe Acrobat 7.0 Professional' 
			,'{AC76BA86-1033-0000-7760-000000000003} ' --'Adobe Acrobat 8 Professional' 
			)
		)
ORDER  BY 4