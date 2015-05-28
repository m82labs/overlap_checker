USE [DBTools]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

IF OBJECT_ID('DBTools..AddJobDelayStep') IS NULL
BEGIN
	EXEC('CREATE PROCEDURE [AddJobDelayStep] AS SELECT 1;');
END
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
-- Date - Auth: 2015.05.28 - M.Wilkinson
-- Description: This was originally written for an MSX/TSX environment. It will
--              now work in any environment.
----------------------------------------------------------------------------------

ALTER PROCEDURE [AddJobDelayStep]
(
@operation CHAR(1) = 'A' -- A - Add, D - Delete
)
AS

DECLARE
    @currentJobID UNIQUEIDENTIFIER,
    @currentJobName sysname,
    @sqlCmd NVARCHAR(max);
 
-- Create a cursor for all jobs on the system
DECLARE JobCursor CURSOR LOCAL FAST_FORWARD
FOR
SELECT DISTINCT
    sj.job_id,
    sj.name
FROM
    msdb.dbo.sysjobservers sjs
    JOIN msdb.dbo.sysjobs sj
        ON sj.job_id = sjs.job_id
WHERE
    sj.enabled = 1
    AND sj.originating_server_id = 0

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