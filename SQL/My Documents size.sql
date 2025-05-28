SELECT
	sft.Filename,
	sft.Filesize /1024 /1024 AS 'Size',
	sft.filepath,
	sys.name0,
	comp.model0,
	sys.Ad_site_name0
FROM
dbo.v_GS_softwareFile as sft
INNER JOIN dbo.v_R_System sys ON sys.resourceid=sft.resourceid
INNER JOIN dbo.v_HS_COMPUTER_SYSTEM AS Comp ON sys.resourceid=comp.resourceid
WHERE Filepath like '%my Music%' and username0 is not null --and username0 like '%scooper'
group by sys.name0,sft.filename, username0, comp.model0, Ad_site_name0, sft.filepath, sft.filesize
ORDER BY Sys.name0, sft.filepath
