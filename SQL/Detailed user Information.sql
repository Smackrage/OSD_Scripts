-- Detailed User Information
Select SD.Name0 
'Machine Name', SD.User_Name0 
'Logon Name', UD.Full_User_Name0 
'Full Name' From v_R_System SD 
Join v_R_User UD on SD.User_Name0 = 
UD.User_Name0 
Where SD.User_Name0 = 'mnsmith'