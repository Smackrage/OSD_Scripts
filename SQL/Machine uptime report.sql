Select 
SD.Name0 'Machine Name',
Convert(VarChar(10), OS.LastBootUpTime0, 101) 'Last Boot Date',
DateDiff(D, OS.LastBootUpTime0,
GetDate()) 'Last Boot (Days)'
 
From v_R_System SD
Join v_Gs_Operating_System OS on SD.ResourceID = OS.ResourceID                                           
 
Where (DateDiff(D, OS.LastBootUpTime0, GetDate()) >= 30)
Order By OS.LastBootUpTime0