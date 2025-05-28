--DECLARE @collectionId VARCHAR (15) 

--SET @collectionId = 'M01000F8' 

SELECT sd.name0                                      'Machine Name', 
       CONVERT(VARCHAR(10), os.lastbootuptime0, 101) 'Last Boot Date', 
       Datediff(d, os.lastbootuptime0, Getdate())    'Last Boot (Days)', 
       sd.user_name0 
FROM   v_r_system sd 
       INNER JOIN v_gs_operating_system AS os 
         ON sd.resourceid = os.resourceid 
       INNER JOIN v_fullcollectionmembership AS col 
         ON sd.resourceid = col.resourceid 
       INNER JOIN v_collection AS ccm 
         ON col.collectionid = ccm.collectionid 
WHERE  ( Datediff(d, os.lastbootuptime0, Getdate()) >= 30 ) 
       AND ccm.collectionid = @collectionId 
--'M01000F8' 
ORDER  BY os.lastbootuptime0 