-- Detailed Computer Information
Select SD.Name0 'Machine Name', 
SD.Resource_Domain_OR_Workgr0 
'Resource Domain', 
SD.User_Name0 'Login ID', 
SD.User_Domain0 'Account 
Domain', USR.Full_User_Name0 
'Full Name', PCB.SerialNumber0 
'Serial Number', CS.Manufacturer0 
Manufacturer, CS.Model0 Model, 
SAS.SMS_Assigned_Sites0 
'Assigned Site Code' 
From v_R_System SD Join v_FullCollectionMembership
 FCM on SD.ResourceID = FCM.ResourceID 
 Join v_Collection COL on 
 FCM.CollectionID = COL.CollectionID 
 Join v_R_User USR on SD.User_Name0 = 
 USR.User_Name0 Join v_GS_PC_BIOS PCB 
 on SD.ResourceID = PCB.ResourceID 
 Join v_GS_COMPUTER_SYSTEM CS on 
 SD.ResourceID = CS.ResourceID 
 Join v_RA_System_SMSAssignedSites 
 SAS on SD.ResourceID = SAS.ResourceID 
 Where COL.Name = 'All Systems'