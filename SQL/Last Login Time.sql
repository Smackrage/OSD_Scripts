USE SMS_M01
Select 
V_GS_SYSTEM.Name0 as [ComputerName], 
V_GS_NETWORK_LOGIN_PROFILE.TimeStamp as [Last Login Time], 
V_GS_NETWORK_LOGIN_PROFILE.Name0 as [Logon User], 
V_GS_SYSTEM.Domain0 as [Logon Domain], 
V_GS_SYSTEM.SystemRole0 as [System Role], 
V_GS_SYSTEM.SystemType0 as [System Type] 
from V_GS_NETWORK_LOGIN_PROFILE 
left JOIN v_GS_SYSTEM ON V_GS_NETWORK_LOGIN_PROFILE.ResourceID = 
v_GS_SYSTEM.ResourceID 
where V_GS_NETWORK_LOGIN_PROFILE.LastLogon0 is not NULL
ORDER BY 'last login time'