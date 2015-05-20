USE [DBTools]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

IF OBJECT_ID('DBTools..GetJobData') IS NULL
BEGIN
	EXEC('CREATE PROCEDURE [GetJobData] AS SELECT 1;');
END
GO

----------------------------------------------------------------------------------
-- Procedure Name: GetJobData
--
-- Desc: This procedure caluclates and returns the run times for all jobs on the
-- instance depending on the run interval, and time period you specify.
--
-- Parameters:
--    INPUT 
--		@timePeriodHr -   Time period to map run times out. Defaults to 24hr
--        @minInterval -    Minimum run interval in seconds. If you only want 
--                          jobs that run less than 1 time every minute, you would
--                          set this to 60.
--        @maxInterval -    Similar to @minInterval. This specifies the maximum 
--                          run interval. If you only want jobs that run more than 
--                          once every twelve hours, you would set this to 43200
--
-- Returns:
-- Returns all job executions for the specified period. These aren't actual
-- executions, but assumed executions. If a job is set to run every 12 hours, and
-- you want to get a 24 hour period, that job would have two rows in the result
-- set.
--
-- Auth: Mark Wilkinson
-- Date: 2015.01.29 14:23:15
--
-- Change History
-- ----------------
-- Date - Auth: 2015.04.23 22:20 - Mark Wilkinson
-- Description: Simplified the logic, added support for job execution periods.
-- Date - Auth: 2015.05.18 - M.Wilkinson
-- Description: Added JOIN to job exclusion table. Search for tag '#exc' to modify
----------------------------------------------------------------------------------

ALTER PROCEDURE [GetJobData]
(
@timePeriodHr INT = 24,
@minInterval INT = 120,
@maxInterval INT = 43200
)
AS
SET NOCOUNT ON

-- @currentDate is simply used as a base date to calculate run times
DECLARE @currentDate INT = CAST(CONVERT(VARCHAR,GETDATE(),112) AS INT);

-- Start by getting the original start date for the job along with the run interval
WITH JobData AS (
SELECT
    CONVERT(VARCHAR(36),sj.job_id) AS job_id,
    sj.name,
    (run_data.avg_dur / run_data.exec_count) + 1 AS avg_dur,
    msdb.dbo.agent_datetime(@currentDate,ss.active_start_time) As start_datetime,
    (
        CASE
            WHEN ss.freq_type = 1 THEN -1
            WHEN ss.freq_type = 4 AND ss.freq_subday_type = 2 THEN ss.freq_subday_interval
            WHEN ss.freq_type = 4 AND ss.freq_subday_type = 4 THEN ss.freq_subday_interval * 60
            WHEN ss.freq_type = 4 AND ss.freq_subday_type = 8 THEN ss.freq_subday_interval * 3600
        END
    ) AS interval_sec,
    COUNT(ss.schedule_id) OVER (PARTITION BY sj.job_id) AS schedule_count,
	msdb.dbo.agent_datetime(@currentDate,ss.active_end_time) AS job_end,
     jde.calculate_delay
FROM
    msdb.dbo.sysjobs AS sj
    INNER JOIN msdb.dbo.sysjobschedules AS sjs ON
        sj.job_id = sjs.job_id
    INNER JOIN msdb.dbo.sysschedules AS ss ON
        sjs.schedule_id = ss.schedule_id
    CROSS APPLY (
        SELECT
            sjh.job_id,
            SUM(
                CASE
                    WHEN sjh.step_id = 1 AND sjh.step_name = 'Delay' THEN 0
                    WHEN sjh.step_id > 0 THEN
                        (((sjh.run_duration/10000) % 10000) * 3600) +
                        (((sjh.run_duration/100) % 100 ) * 60) +
                        (sjh.run_duration % 100)
                END
            ) AS avg_dur,
            SUM(
                CASE
                    WHEN sjh.step_id = 0 THEN 1
                    ELSE 0
                END
            ) AS exec_count
        FROM
            msdb.dbo.sysjobhistory AS sjh
        WHERE
            sjh.job_id = sj.job_id
        GROUP BY
            sjh.job_id
    ) AS run_data
    LEFT OUTER JOIN [JobDelay_Exclusion] AS jde --#exc
        ON sj.name = jde.job_name
WHERE
    sj.enabled = 1
    AND ss.freq_type = 4
    AND ss.enabled = 1
), DaysRun AS (
    -- Now, based on the current date, calculate the run times for this job through the specified time period
    SELECT
        jd.job_id,
        jd.name AS job_name,
        jd.interval_sec,
        jd.avg_dur,
        jd.calculate_delay,
        jd.start_datetime AS run_datetime,
        DATEADD(second,jd.avg_dur,jd.start_datetime) AS end_datetime,
		jd.job_end
    FROM
        JobData AS jd
    WHERE
        jd.interval_sec < @maxInterval
        AND jd.interval_sec > @minInterval
        AND avg_dur IS NOT NULL
        AND jd.schedule_count = 1
    UNION ALL
    SELECT
        dr.job_id,
        dr.job_name,
        dr.interval_sec,
        dr.avg_dur,
        dr.calculate_delay,
        DATEADD(second,dr.interval_sec,dr.run_datetime) AS run_datetime,
        DATEADD(second,dr.interval_sec,dr.end_datetime) AS end_datetime,
		dr.job_end
    FROM
        DaysRun AS dr
    WHERE
        dr.run_datetime < dr.job_end
)
SELECT
    job_id,
    job_name,
    interval_sec,
    avg_dur,
    calculate_delay,
    run_datetime,
    end_datetime
FROM
    DaysRun
OPTION(MAXRECURSION 32767);
GO