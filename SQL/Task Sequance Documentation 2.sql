USE [SMS_M01]
GO

       select 
pkg.PkgID as 'PackageID', 
pkg.Name,
Version,
Language,
Manufacturer,
pkg.Description,
Source As 'PkgSourcePath',
pkg.SourceSite,
StoredPkgPath,
RefreshSchedule,
LastRefresh As 'LastRefreshTime',
ShareName,
PreferredAddress As 'PreferredAddressType',
StoredPkgVersion,
StorePkgFlag As 'PkgSourceFlag',
ShareType,
Permission, 
UseForcedDisconnect As 'ForcedDisconnectEnabled',
ForcedRetryDelay As 'ForcedDisconnectNumRetries',
DisconnectDelay As 'ForcedDisconnectDelay',
IgnoreSchedule As 'IgnoreAddressSchedule',
Priority,
PkgFlags, 
MIFFilename,
MIFPublisher,
MIFName,
MIFVersion,
SourceVersion,
SourceDate, 
SourceSize,
SourceCompSize,
pkg.UpdateMask,
pkg.Action AS 'ActionInProgress',
pkg.Icon,
Hash,
pkg.ExtData,
ImageFlags,
PackageType,
UpdateMaskEx,
pkg.ISVData,
HashVersion,
NewHash, 
prg.Description as Category,
DependentProgram,
ProgramFlags,
Duration,
prg.Name as ProgramName, 
ts.Type as TS_Type, BootImageID, TS_Flags, TS_ID, prg.Comment As 'CustomProgressMsg' 
       from SMSPackages as pkg 
               join PkgPrograms as prg on (pkg.PkgID = prg.PkgID and ((prg.ProgramFlags & 0x00000010) <> 0)) 
               join TS_TaskSequence as ts on (ts.TS_ID = prg.ProgramID) 
       where pkg.Action != 3 and prg.Action != 3 and PackageType = 4 

GO

SELECT * FROM SMSPackages




SUSE [SMS_M01]
GO

/****** Object:  View [dbo].[v_TaskExecutionStatus]    Script Date: 09/16/2009 16:20:55 ******/
SET ANSI_NULLS ON

SELECT tse.OfferID AS AdvertisementID,
 tse.ItemKey AS ResourceID,
 tse.ExecutionTime
 ,tse.Step,
  tse.ActionName,
  tse.GroupName,
 LastStatusMessageID = tse.LastStatus&0xFFFF
 , LastStatusMes
sageIDName = info.MessageName,
 tse.ExitCode,
 tse.ActionOutput   
FROM TaskExecutionStatus tse   
JOIN System_DISC sys on tse.ItemKey=sys.ItemKey   
LEFT JOIN OfferStatusInfo info ON info.MessageID=tse.LastStatus
   WHERE IsNull(sys.Obsolete0,0)!=1 and IsNull(sys.Decommissioned0,0)!=1 
GO


