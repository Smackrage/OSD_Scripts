SELECT 
	COUNT (*) AS package_failures,
	status.AdvertisementID AS 'ADVERTID',
	LastAcceptanceMessageIDName,
	LastStatusMessageIDName,
	LastExecutionContext,
	Advertname.AdvertisementName AS  'ADVERT NAME'
--INTO ##temp
FROM dbo.v_ClientAdvertisementStatus AS Status
	INNER JOIN dbo.v_Advertisement AS Advertname ON Status.AdvertisementID=Advertname.AdvertisementID
WHERE lastacceptancemessageIDName NOT IN ('program received','Program completed with success')
GROUP BY status.AdvertisementID,
	LastAcceptanceMessageIDName,
	LastStatusMessageIDName,
	LastExecutionContext,
	Advertname.AdvertisementName
--SELECT * FROM ##temp
HAVING COUNT (*) >=0
ORDER BY package_failures DESC
--DROP TABLE ##temp

--Select * from dbo.v_ClientAdvertisementStatus