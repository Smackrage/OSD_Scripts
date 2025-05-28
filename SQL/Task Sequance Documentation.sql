SELECT [TS_ID]
      ,[TS_ReferenceID]
  FROM [SMS_M01].[dbo].[TS_References]
GO

SELECT [TS_ID]
      ,[Sequence]
      ,[Type]
      ,[BootImageID]
      ,[TS_Flags]
  FROM [SMS_M01].[dbo].[TS_TaskSequence]
GO

SELECT
[OfferID]
      ,[ItemKey]
      ,[ExecutionTime]
      ,[Step]
      ,[ActionName]
      ,[GroupName]
      ,[LastStatus]
      ,[ExitCode]
      ,[ActionOutput]
  FROM [SMS_M01].[dbo].[TaskExecutionStatus]
GO


SELECT ps.Name 
       , ps.SourceVersion
       , ps.SourceDate
       , ps.Targeted AS NumberOfDPsTargeted0
       , ps.Installed AS NumberOfDPsInstalled0
       , ps.Retrying AS NumberOfDPsRetrying0
       , ps.Failed AS NumberOfDPsFailed0
       , ps.SourceSite
       , ps.SourceSize
       , ps.SourceCompressedSize
       , ps.PackageID
FROM 
     (
         SELECT DISTINCT *
         FROM v_TaskSequenceReferencesInfo 
         WHERE v_TaskSequenceReferencesInfo.PackageID='M0100026'
     ) RefPkgs 
     JOIN v_PackageStatusRootSummarizer ps ON ps.PackageID = RefPkgs.PackageID
ORDER BY ps.Name

SELECT * FROM SMSPackages
WHERE SMSPackages.PKgID = 'M0100026'
SELECT * FROM TaskExecutionStatus