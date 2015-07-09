#Overlap Checker
Application to reduce SQL Agent Job overlaps by introducing calculated job delays.

###Whats New
- Added ability to exclude jobs by adding a custom keyword to either the job description or category
- Updated the installer

##Overview##
For a quick overview, please read through the code comments, and my blog post on this project:

##Installation##
Installation is fairly straight forward:
  1. Clone this repo.
  2. Open the solution and build it.
  3. Run `Install\Install.ps1` and tell it which instances to install Overlap Checker on, which database to use, and which schema to create the database objects in.
  4. Now just copy the `JobOverlapChecker\bin\Debug\JobOverlapChecker.exe` and `Install\JobOverlapChecker.exe.config` files to a folder on each instance and then set up a scheduled job on each instance with a step that executes `YourDB.YourSchema.AddJobDelayStep @operation = 'A'` followed by a step that executes `JobOverlapChecker.exe`.  This will ensure that every job, even newly created ones, have the delay step added.

  ***WARNING: Read through the `Install.ps1` script, it will create various database objects on the instance(s) specified.***

Here is an example `JobOverlapChecker.exe.config` file:
```
﻿<?xml version="1.0" encoding="utf-8" ?>
<configuration>
    <startup>
        <supportedRuntime version="v4.0" sku=".NETFramework,Version=v4.5" />
    </startup>
    <connectionStrings>
      <add name="SQLData"
            connectionString="Data Source=localhost;Initial Catalog=DBTools;Integrated Security=true;"
            providerName="System.Data.SqlClient"/>
    </connectionStrings>
  <appSettings>
    <add key="Instance" value="localhost"/>
    <add key="Schema" value="dbo"/>
    <add key="TargetTable" value="JobDelay"/>
    <add key="JobDataProc" value="GetJobData"/>
    <add key="JobExclusionString" value="NoDelay"/>
  </appSettings>
</configuration>
```

##Disclaimer##
This is my first time posting C# code to Git, and my second time ( maybe third) ever writing C#. Feedback is **VERY** welcome.
