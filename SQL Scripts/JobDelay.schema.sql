IF DB_ID('{{{dbName}}}') IS NULL
BEGIN
    CREATE DATABASE {{{dbName}}};
    ALTER DATABASE {{{dbName}}} SET RECOVERY SIMPLE;
END
GO

USE [{{{dbName}}}];
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

IF OBJECT_ID('{{{dbName}}}.{{{schema}}}.JobDelay') IS NULL
BEGIN
	CREATE TABLE {{{schema}}}.[JobDelay](
		[job_name] [sysname] NOT NULL,
		[delay_sec] [int] NULL,
	 CONSTRAINT [PK_JobDelay] PRIMARY KEY CLUSTERED 
	(
		[job_name] ASC
	)WITH (FILLFACTOR = 100)
	);
END
GO