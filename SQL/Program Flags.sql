DECLARE @ProgramFlags 
TABLE 
(
   BitFlag INT PRIMARY KEY,
   Meaning VARCHAR(128),
   Description VARCHAR(512)
)
INSERT INTO @ProgramFlags
VALUES
   (2			,'USECUSTOMPROGRESSMSG','The task sequence shows a custom progress user interface message.'),
   (16			,'DEFAULT_PROGRAM','This is a default program.'),
   (32			,'DISABLEMOMALERTONRUNNING','Disables MOM alerts while the program runs.'),
   (64			,'MOMALERTONFAIL','Generates MOM alert if the program fails.'),
   (128			,'RUN_DEPENDANT_ALWAYS','If set, this program''s immediate dependent should always be run.'),
   (256			,'WINDOWS_CE','Indicates a device program.  If set, the program is not offered to desktop clients.'),
   (1024        ,'COUNTDOWN','The countdown dialog is not displayed.'),
   (4096        ,'DISABLED','The program is disabled.'),
   (8192        ,'UNATTENDED','The program requires no user interaction.'),
   (16384       ,'USERCONTEXT','The program can only run when a user is logged on.'),
   (32768       ,'ADMINRIGHTS','The program must be run as the local Administrator account.'),
   (65536       ,'EVERYUSER','The program must be run by every user for whom it is valid. Valid only for mandatory jobs.'),
   (131072      ,'NOUSERLOGGEDIN','The program is only run when no user is logged on.'),
   (262144      ,'OKTOQUIT','The program will restart the computer'),
   (524288      ,'OKTOREBOOT','Configuration Manager restarts the computer when the program has finished running successfully.'),
   (1048576     ,'USEUNCPATH','Use a UNC path (no drive letter to access)'),
   (2097152     ,'PERSISTCONNECTION','Persists the connection to the drive specified in the DriveLetter property.  The USEUNCPATH bit flag must not be set.'),
   (4194304     ,'RUNMINIMIZED','Run the program as a minimized window.'),
   (8388608     ,'RUNMAXIMIZED','Run the program as a maximized window.'),
   (16777216    ,'HIDEWINDOW','Hide the program window.'),
   (33554432    ,'OKTOLOGOFF','Logoff user when program completes successfully.'),
   (134217728   ,'ANY_PLATFORM','Override check for platform support.'),
   (536870912   ,'SUPPORT_UNINSTALL','Run uninstall from the registry key when the advertisement expires.')
   ;
 
WITH cte AS 
(
   SELECT
      f.BitFlag,
      f.Meaning,
      (f.BitFlag & p.ProgramFlags)/f.BitFlag AS [Enabled],
      p.PackageID,
      p.ProgramName
   FROM
      dbo.v_Program p
      CROSS JOIN @ProgramFlags f
)   
SELECT
   PackageID,
   ProgramName,
   MAX(CASE BitFlag WHEN 2 THEN [Enabled] END) AS [USECUSTOMPROGRESSMSG],
   MAX(CASE BitFlag WHEN 16 THEN [Enabled] END) AS [DEFAULT_PROGRAM],
   MAX(CASE BitFlag WHEN 32 THEN [Enabled] END) AS [DISABLEMOMALERTONRUNNING],
   MAX(CASE BitFlag WHEN 64 THEN [Enabled] END) AS [MOMALERTONFAIL],
   MAX(CASE BitFlag WHEN 128 THEN [Enabled] END) AS [RUN_DEPENDANT_ALWAYS],
   MAX(CASE BitFlag WHEN 256 THEN [Enabled] END) AS [WINDOWS_CE],
   MAX(CASE BitFlag WHEN 1024 THEN [Enabled] END) AS [COUNTDOWN],
   MAX(CASE BitFlag WHEN 4096 THEN [Enabled] END) AS [DISABLED],
   MAX(CASE BitFlag WHEN 8192 THEN [Enabled] END) AS [UNATTENDED],
   MAX(CASE BitFlag WHEN 16384 THEN [Enabled] END) AS [USERCONTEXT],
   MAX(CASE BitFlag WHEN 32768 THEN [Enabled] END) AS [ADMINRIGHTS],
   MAX(CASE BitFlag WHEN 65536 THEN [Enabled] END) AS [EVERYUSER],
   MAX(CASE BitFlag WHEN 131072 THEN [Enabled] END) AS [NOUSERLOGGEDIN],
   MAX(CASE BitFlag WHEN 262144 THEN [Enabled] END) AS [OKTOQUIT],
   MAX(CASE BitFlag WHEN 524288 THEN [Enabled] END) AS [OKTOREBOOT],
   MAX(CASE BitFlag WHEN 1048576 THEN [Enabled] END) AS [USEUNCPATH],
   MAX(CASE BitFlag WHEN 2097152 THEN [Enabled] END) AS [PERSISTCONNECTION],
   MAX(CASE BitFlag WHEN 4194304 THEN [Enabled] END) AS [RUNMINIMIZED],
   MAX(CASE BitFlag WHEN 8388608 THEN [Enabled] END) AS [RUNMAXIMIZED],
   MAX(CASE BitFlag WHEN 16777216 THEN [Enabled] END) AS [HIDEWINDOW],
   MAX(CASE BitFlag WHEN 33554432 THEN [Enabled] END) AS [OKTOLOGOFF],
   MAX(CASE BitFlag WHEN 134217728 THEN [Enabled] END) AS [ANY_PLATFORM],
   MAX(CASE BitFlag WHEN 536870912 THEN [Enabled] END) AS [SUPPORT_UNINSTALL]
FROM
   cte
GROUP BY
   PackageID,
   ProgramName
