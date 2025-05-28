Select 
	temp1.SystemConsoleUser0 as [Primary User],  
 Count (temp1.ResourceID) as [Instance Count]  
 from ( 
 Select distinct  
  v_GS_SYSTEM_CONSOLE_USER.SystemConsoleUser0,  
 v_GS_SYSTEM_CONSOLE_USER.ResourceID   
 from v_GS_SYSTEM_CONSOLE_USER  
 left join v_GS_SYSTEM_CONSOLE_USAGE_MAXGROUP on v_GS_SYSTEM_CONSOLE_USAGE_MAXGROUP.ResourceID = v_GS_SYSTEM_CONSOLE_USER.ResourceID  
 inner join v_FullCollectionMembership on v_FullCollectionMembership.ResourceID = v_GS_SYSTEM_CONSOLE_USER.ResourceID  
 inner join v_R_System_Valid ON v_R_System_Valid.ResourceID = v_GS_SYSTEM_CONSOLE_USER.ResourceID  
 where v_FullCollectionMembership.CollectionID = @CollectionID  
 AND TotalConsoleTime0 != 0  
 And (cast(v_GS_SYSTEM_CONSOLE_USER.TotalUserConsoleMinutes0 as Decimal (20,4)))/(cast(v_GS_SYSTEM_CONSOLE_USAGE_MAXGROUP.TotalConsoleTime0 as Decimal(20,4))) >= .66  
 ) as temp1  
 group by temp1.SystemConsoleUser0  
 order by Count (temp1.ResourceID) desc
 
 
 
 SELECT * FROM v_GS_SYSTEM_CONSOLE_USER
Where v_GS_SYSTEM_CONSOLE_USER.SystemConsoleUser0 NOT LIKE '%\helpassistant'
AND v_GS_SYSTEM_CONSOLE_USER.SystemConsoleUser0 NOT LIKE '%\administrator'
AND v_GS_SYSTEM_CONSOLE_USER.SystemConsoleUser0 = '$domain$\%username%'
 
 Order by SystemConsoleUser0
 --mg8jh12s\helpassistant
 
 SELECT * FROM v_GS_SYSTEM_CONSOLE_USage
 
 
 