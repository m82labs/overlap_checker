#------------------------------------------------------------------------------
# Script: Install.ps1
# Author: M.Wilkinson
# Date: 2015.05.28 13:46
# Parameters:
#  - instancename: Instance to deploy to.
#
# Purpose:
# This script deploys all related database and executables to the specified 
# server(s).
#
#------------------------------------------------------------------------------

# ==== Parameters -------------------------------------------------------------
param (
    [Parameter(Mandatory=$True, Position=0, HelpMessage="Instance name(s) you are deploying to. If you are specifying multiple instances, they must be comma separated.")][string]$instancename,
    [Parameter(Mandatory=$True, Position=1, HelpMessage="Database name objects should be deployed to.")][string]$databaseName = 'DBTools',
    [Parameter(Mandatory=$True, Position=2, HelpMessage="Database schema name objects should be deployed to.")][string]$schemaName = 'dbo'
)
# ====-------------------------------------------------------------------------

# ==== Variables: Reconfigure as needed for your system -----------------------
[string]$ScriptPath = $PSScriptRoot
[string]$GetJobData_Script = "$ScriptPath\GetJobData.proc.sql"
[string]$AddJobDelayStep_Script = "$ScriptPath\AddJobDelayStep.proc.sql"
[string]$JobDelaySchema_Script = "$ScriptPath\JobDelay.schema.sql"
[string]$ConfigJSON_Script = "$ScriptPath\JobOverlapChecker.exe.config.template"
# ====-------------------------------------------------------------------------

# ==== Validate Parameters and files-------------------------------------------
# Check to see if scripts exist------------------------------------------------
if ( -not (Test-Path $GetJobData_Script) ) {
    Throw "GetJobData procedure creation script file does not exist: $GetJobData_Script"
    Break
}
if ( -not (Test-Path $AddJobDelayStep_Script) ) {
    Throw "AddJobDelayStep procedure creation script file does not exist: $AddJobDelayStep_Script"
    Break
}
if ( -not (Test-Path $JobDelaySchema_Script) ) {
    Throw "JobDelay schema objects creation script file does not exist: $JobDelaySchema_Script"
    Break
}
if ( -not (Test-Path $ConfigJSON_Script) ) {
    Throw "Config JSON file does not exist: $ConfigJSON_Script"
    Break
}

# Load our files up into string variables.
$GetJobData_Script_str = [IO.File]::ReadAllText($GetJobData_Script)
$AddJobDelayStep_Script_str = [IO.File]::ReadAllText($AddJobDelayStep_Script)
$JobDelaySchema_Script_str = [IO.File]::ReadAllText($JobDelaySchema_Script)
$ConfigJSON_Script_str = [IO.File]::ReadAllText($ConfigJSON_Script)
# ====-------------------------------------------------------------------------

# ==== Replace schema and database names in scripts ---------------------------
$GetJobData_Script_str = ($GetJobData_Script_str.Replace('{{{dbName}}}',$databaseName)).Replace('{{{schema}}}',$schemaName)
$AddJobDelayStep_Script_str = ($AddJobDelayStep_Script_str.Replace('{{{dbName}}}',$databaseName)).Replace('{{{schema}}}',$schemaName)
$JobDelaySchema_Script_str = ($JobDelaySchema_Script_str.Replace('{{{dbName}}}',$databaseName)).Replace('{{{schema}}}',$schemaName)
# ====-------------------------------------------------------------------------

# ==== Define our script block ------------------------------------------------
$script_block = {
    param($i,$scr1,$scr2,$scr3)

    # Check if the instance is up
    $tcp = New-Object System.Net.Sockets.TcpClient
    $tcpConnection = $tcp.BeginConnect($i, 1433, $null, $null)
    $success = $tcpConnection.AsyncWaitHandle.WaitOne(2000);
    $tcp.Close()

    if ( ! $success ) {
        # If the instance is not connectable, display a message.
        Write-Host "$i is down." -ForegroundColor White -BackgroundColor Red
    } else {
        # If it is up, try to deploy scripts
        Try {
            $result = Invoke-Sqlcmd -ServerInstance $i -Query $scr1 -ErrorAction Stop
            $result = Invoke-Sqlcmd -ServerInstance $i -Query $scr2 -ErrorAction Stop
            $result = Invoke-Sqlcmd -ServerInstance $i -Query $scr3 -ErrorAction Stop

            Write-Host "Deployment to $i is complete." -ForegroundColor White -BackgroundColor Green
        }
        Catch {
            Write-Host "Deployment to $i failed: $_" -ForegroundColor White -BackgroundColor Red
        }
    }
}

Write-Host "Deploying Scripts..."

# Loop through instances and execute our code block.
ForEach ( $instance in $instancename.Split(',')) {
    Start-Job -ScriptBlock $script_block -ArgumentList $instance,$JobDelaySchema_Script_str,$GetJobData_Script_str,$AddJobDelayStep_Script_str  | Out-Null
}

# Report Failure/Success as jobs are running
while ( Get-Job -State Running ) {
    Get-Job | Receive-Job
    Sleep 0.5
}

# Clean Up
Get-Job | Remove-Job

Write-Host "Database Deployment Complete."

# Write out the config file
Try {
    $configFile = ($ConfigJSON_Script_str.Replace('{{dbName}}',$databaseName)).Replace('{{schema}}',$schemaName)
    [System.IO.File]::WriteAllLines("$ScriptPath\JobOverlapChecker.exe.config", $configFile)
    Write-Host "
Config file generated: $ScriptPath\JobOverlapChecker.exe.config.
This file will need to be copied, along with the executable (overlap_checker\JobOverlapChecker\bin\Debug\JobOverlapChecker.exe), to all SQL instances you are running the overlap checker on.

You will also need to add a job to each instance with a step that executes the 'AddJobDelayStep' procedure, passing @operation = 'a' to it, followed by a step that executes the JobOverlapChecker.exe binary."
}
Catch {
    Write-Host "Failed to generate config file: $_" -ForegroundColor White -BackgroundColor Red
}

Pause