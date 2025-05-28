SELECT
    CS.Manufacturer0 AS Manufacturer,
    CS.Model0 AS Model,
    COUNT(*) AS DeviceCount
FROM
    v_GS_COMPUTER_SYSTEM CS
GROUP BY
    CS.Manufacturer0,
    CS.Model0
ORDER BY
    DeviceCount DESC;
