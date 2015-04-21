--== Creates the 'DBTools' database, the job delay table, the GetJobData stored proc
--== and the proc used to add delay steps.
--== LOOK THROUGH THESE SCRIPTS AND MAKE CHANGES IF YOU PLAN TO USE A DIFFERENT DB.

--== Database
IF DB_ID('DBTools') IS NULL
CREATE DATABASE DBTools;
ALTER DATABASE DBTools SET RECOVERY SIMPLE;
GO

--== JobDelay Table
USE [DBTools];
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [JobDelay](
	[job_name] [sysname] NOT NULL,
	[delay_sec] [int] NULL,
 CONSTRAINT [PK_JobDelay] PRIMARY KEY CLUSTERED 
(
	[job_name] ASC
)WITH (FILLFACTOR = 100)
);
GO

--== GetJobData Proc
USE [DBTools]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

----------------------------------------------------------------------------------
-- Procedure Name: GetJobDataRS
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
-- you want to get a 24 hour period, that job would have to rows in the result
-- set.
--
-- Auth: Mark Wilkinson
-- Date: 2015.01.29 14:23:15
--
-- Change History
-- ----------------
-- Date - Auth: 
-- Description: 
----------------------------------------------------------------------------------

CREATE PROCEDURE [GetJobData]
(
@timePeriodHr INT = 24,
@minInterval INT = 120,
@maxInterval INT = 43200
)
AS
SET NOCOUNT ON

-- @currentDate is simply used as a base date to calculate run times
DECLARE @currentDate DATETIME = CONVERT(datetime,CONVERT(VARCHAR,GETDATE(),101));

-- Start by getting the original start date for the job along with the run interval
WITH JobData AS (
SELECT
    CONVERT(VARCHAR(36),sj.job_id) AS job_id,
    sj.name,
    (run_data.avg_dur / run_data.exec_count) + 1 AS avg_dur,
    msdb.dbo.agent_datetime(ss.active_start_date,ss.active_start_time) As start_datetime,
    (
        CASE
            WHEN ss.freq_type = 1 THEN -1
            WHEN ss.freq_type = 4 AND ss.freq_subday_type = 2 THEN ss.freq_subday_interval
            WHEN ss.freq_type = 4 AND ss.freq_subday_type = 4 THEN ss.freq_subday_interval * 60
            WHEN ss.freq_type = 4 AND ss.freq_subday_type = 8 THEN ss.freq_subday_interval * 3600
        END
    ) AS interval_sec,
    COUNT(ss.schedule_id) OVER (PARTITION BY sj.job_id) AS schedule_count
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
        DATEADD(second,((DATEDIFF(second,jd.start_datetime,@currentDate) / jd.interval_sec) * jd.interval_sec),jd.start_datetime) AS run_datetime,
        DATEADD(second,((DATEDIFF(second,jd.start_datetime,@currentDate) / jd.interval_sec) * jd.interval_sec) + jd.avg_dur,jd.start_datetime) AS end_datetime
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
        DATEADD(second,dr.interval_sec,dr.run_datetime) AS run_datetime,
        DATEADD(second,dr.interval_sec,dr.end_datetime) AS end_datetime
    FROM
        DaysRun AS dr
    WHERE
        dr.run_datetime < DATEADD(second,(@timePeriodHr*3600),@currentDate)
)
SELECT
    job_id,
    job_name,
    interval_sec,
    avg_dur,
    run_datetime,
    end_datetime
FROM
    DaysRun
OPTION(MAXRECURSION 32767);
GO

--== Add delay step proc
USE [DBTools]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
----------------------------------------------------------------------------------
-- Procedure Name: AddJobDelayStep
--
-- Desc: Adds a delay step to each job, it can also remove the steps if
--       @operation = 'D'.
--
-- Notes:
--
-- Parameters:
--	INPUT
--		@operation CHAR(1) - A,D Add or Delete the Delay step from all jobs
--
-- Returns:
--
-- Date: 2015.02.19 13:44:59
-- Auth: Mark Wilkinson
--
-- Change History
-- ----------------
-- Date - Auth: 
-- Description: 
----------------------------------------------------------------------------------

CREATE PROCEDURE [AddJobDelayStep]
(
@operation CHAR(1) = 'A' -- A - Add, D - Delete
)
AS

DECLARE
    @currentJobID UNIQUEIDENTIFIER,
    @currentJobName sysname,
    @sqlCmd NVARCHAR(max);
 
-- Create a cursor for all jobs on the system
DECLARE JobCursor CURSOR
FOR
SELECT DISTINCT
    sj.job_id,
    sj.name
FROM
    msdb.dbo.sysjobservers sjs
    JOIN msdb.dbo.sysjobs sj
        ON sj.job_id = sjs.job_id
    INNER JOIN msdb.dbo.systargetservers AS sts
        ON sts.server_id = sjs.server_id
WHERE
    sts.server_name <> @@servername
    AND sj.enabled = 1
    AND sj.originating_server_id = 0
    AND sj.name <> N'Check replicated subscriber rowcounts';

OPEN JobCursor;

FETCH NEXT FROM JobCursor
INTO
    @currentJobID,
    @CurrentJobName;

WHILE @@FETCH_STATUS = 0
BEGIN
    
    IF (
        @operation = 'A'
        AND NOT EXISTS (
            SELECT  1
            FROM    msdb.dbo.sysjobsteps
            WHERE   job_id = @currentJobID
                    AND step_id = 1
                    AND step_name = 'Delay'
        )
    )
    BEGIN

        SET @sqlCmd = REPLACE(REPLACE(
    --<< SQL -----------------------------
            N'
            DECLARE @delay INT = NULL;
            DECLARE @waitfor CHAR(8);

            SELECT  @delay = delay_sec
            FROM    DBTools.dbo.JobDelay
            WHERE   job_name = "{{@job_name}}"
                        
            SET @waitfor = LEFT(DATEADD(second,ISNULL(@delay,0),CAST("00:00:00" AS TIME)),8);

            WAITFOR DELAY @waitfor;'
    --<< Subs ----------------------------
        ,'{{@job_name}}',@currentJobName)
        ,'"','''');

        EXEC msdb.dbo.sp_add_jobstep @job_id = @currentJobID,
                                     @step_name = N'Delay',
                                     @step_id = 1,
                                     @cmdexec_success_code = 0,
                                     @on_success_action = 3,
                                     @on_fail_action = 3,
                                     @retry_attempts = 0,
                                     @retry_interval = 0,
                                     @os_run_priority = 0,
                                     @subsystem = N'TSQL',
                                     @command = @sqlCmd,
                                     @database_name = N'Common',
                                     @flags = 0;

    END

    IF @operation = 'D'
    BEGIN
        IF EXISTS (
            SELECT  1
            FROM    msdb.dbo.sysjobsteps
            WHERE   job_id = @currentJobID
                    AND step_id = 1
                    AND step_name = 'Delay'
        )
        BEGIN
            EXEC msdb.dbo.sp_delete_jobstep @job_id = @currentJobID,
                                            @step_id = 1;
        END
    END

    FETCH NEXT FROM JobCursor
    INTO
        @currentJobID,
        @CurrentJobName;

END

CLOSE JobCursor;
DEALLOCATE JobCursor;
GO

--== Add 'Delay' Steps
EXEC DBTools.dbo.[AddJobDelayStep] @operation = 'A'