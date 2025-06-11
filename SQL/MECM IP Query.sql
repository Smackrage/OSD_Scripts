WITH IPData AS (
    SELECT
        SYS.Netbios_Name0 AS 'Device Name',
        NAC.IPAddress0 AS 'IP Address',
        ROW_NUMBER() OVER (PARTITION BY SYS.ResourceID ORDER BY NAC.IPAddress0) AS RN
    FROM
        v_GS_NETWORK_ADAPTER_CONFIGUR NAC
    INNER JOIN
        v_R_System SYS ON NAC.ResourceID = SYS.ResourceID
    WHERE
        NAC.IPEnabled0 = 1
        AND NAC.IPAddress0 IS NOT NULL
        AND NAC.IPAddress0 NOT LIKE '169.254.%'
        AND NAC.IPAddress0 NOT LIKE '%.%.%.%,%' -- Exclude multi-IP strings
        AND NAC.IPAddress0 NOT LIKE '%.%.%.%.%' + ',' + '%' -- Exclude comma-separated lists
        AND NAC.IPAddress0 NOT LIKE '%:%' -- IPv4 only
)
SELECT
    [Device Name],
    [IP Address]
FROM
    IPData
WHERE
    RN = 1
ORDER BY
    [Device Name];
