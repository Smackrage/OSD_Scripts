SELECT
	Package.PackageID,
	Package.Name AS 'PACKAGE NAME',
	Package.PkgSourcePath,
	Package.ShareName
	FROM v_Package AS Package 
WHERE NOT EXISTS 
	(Select * From v_Advertisement as  Advert
	Where Package.PackageID=ADVERT.PackageID)


--LEFT JOIN v_Advertisement AS Advert ON Package.PackageID=ADVERT.PackageID
--Where advert.AdvertisementName IS NULL
