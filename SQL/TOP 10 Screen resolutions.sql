SELECT TOP 10 CAST (CurrentHorizontalResolution0 AS varchar) + ' x ' + 
    CAST (CurrentVerticalResolution0  AS varchar) AS 'Screen Resolution', 
    COUNT(*) AS 'Count' 
FROM    dbo.v_GS_VIDEO_CONTROLLER 
WHERE    VideoModeDescription0 IS NOT NULL 
GROUP BY CAST (CurrentHorizontalResolution0 AS varchar) + ' x ' + CAST (CurrentVerticalResolution0  AS varchar) 
ORDER BY Count DESC