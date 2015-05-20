IF DB_ID('DBTools') IS NULL
CREATE DATABASE DBTools;
ALTER DATABASE DBTools SET RECOVERY SIMPLE;
GO

USE [DBTools];
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

IF OBJECT_ID('DBTools.dbo.JobDelay') IS NULL
BEGIN
	CREATE TABLE [JobDelay](
		[job_name] [sysname] NOT NULL,
		[delay_sec] [int] NULL,
	 CONSTRAINT [PK_JobDelay] PRIMARY KEY CLUSTERED 
	(
		[job_name] ASC
	)WITH (FILLFACTOR = 100)
	);
END
GO

IF OBJECT_ID('DBTools.dbo.JobDelay_Exclusion') IS NULL
BEGIN
	CREATE TABLE [JobDelay_Exclusion](
		[job_name] [sysname] NOT NULL,
		[calculate_delay] [bit] NULL,
	 CONSTRAINT [PK_JobDelay_Exclusion] PRIMARY KEY CLUSTERED 
	(
		[job_name] ASC
	)WITH (FILLFACTOR = 100)
	);
END
GO