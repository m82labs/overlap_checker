#Overlap Checker
Application to reduce SQL Agent Job overlaps by introducing calculated job delays.

##Overview##
For a quick overview, please read my blog post on this project: 

##Installation##
Installation is fairly straight forward:
  1. Clone this repo.
  2. Open the solution and build it.
  3. Run `SQL Scripts\deploy.sql` on any instance you want to run the Overlap Checker on.
  4. Now just copy the `JobOverlapChecker.exe` and `JobOverlapChecker.exe.config` files to each instance and the set up a scheduled job on each instance that executes the JobOverlapChecker.exe. 

  ***WARNING: Read through the `deploy.sql` script, it will create various database objects and add a new 'Deploy' step to ALL jobs on the instance.***

Here is an example `JobOverlapChecker.exe.config` file:
```
<?xml version="1.0" encoding="utf-8" ?>
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
    <add key="TargetTable" value="JobDelay"/>
  </appSettings>
</configuration>
```
 
##Troubleshooting##
Coming Soon

##Disclaimer##
This is my first time posting C# code to Git, and my second time ( maybe third) ever writing C#. Feedback is **VERY** welcome.
