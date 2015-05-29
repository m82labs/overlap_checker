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
    [Parameter(Mandatory=$True, Position=0, HelpMessage="Instance name(s) you are deploying to.")][string]$instancename,
    [Parameter(Mandatory=$False, Position=1, HelpMessage="Database name objects should be deployed to.")][string]$databaseName
)
# ====-------------------------------------------------------------------------

# ==== Variables: Reconfigure as needed for your system -----------------------
[string]$GetJobData_Script = 'GetJobData.proc.sql'
[string]$AddJobDelayStep_Script = 'AddJobDelayStep.proc.sql'
[string]$JobDelaySchema_Script = 'JobDelay.schema.sql'
# ====-------------------------------------------------------------------------

# ==== Validate Parameters and files-------------------------------------------
# Check to see if scripts exist------------------------------------------------
if ( -not (Test-Path $GetJobData_Script) ) {
    Throw "GetJobData procedure creation script file does not exist: $GetJobData_Script"
}
if ( -not (Test-Path $AddJobDelayStep_Script) ) {
    Throw "AddJobDelayStep procedure creation script file does not exist: $AddJobDelayStep_Script"
}
if ( -not (Test-Path $JobDelaySchema_Script) ) {
    Throw "JobDelay schema objects creation script file does not exist: $JobDelaySchema_Script"
}

# Load our files up into string variables.
$GetJobData_Script_str = [IO.File]::ReadAllText($GetJobData_Script)
$AddJobDelayStep_Script_str = [IO.File]::ReadAllText($AddJobDelayStep_Script)
$JobDelaySchema_Script_str = [IO.File]::ReadAllText($JobDelaySchema_Script)
# ====-------------------------------------------------------------------------

# ==== Deploy our scripts to each instance ------------------------------------
$script_block = {
    param($i,$scr1,$scr2,$scr3)
    Try {
        $result = Invoke-Sqlcmd -ServerInstance $i -Query 'SELECT 1' -QueryTimeout 1 -ErrorAction Stop
        $result = Invoke-Sqlcmd -ServerInstance $i -Query $scr1 -QueryTimeout 1 -ErrorAction Stop
        $result = Invoke-Sqlcmd -ServerInstance $i -Query $scr2 -QueryTimeout 1 -ErrorAction Stop
        $result = Invoke-Sqlcmd -ServerInstance $i -Query $scr3 -QueryTimeout 1 -ErrorAction Stop

        Write-Host "Deployment to $i is complete." -ForegroundColor White -BackgroundColor Green
    }
    Catch {
        Write-Host "Deployment to $i failed: $_" -ForegroundColor White -BackgroundColor Red
    }
}

# Loop through instances and check if they are up, then deploy the scripts.
ForEach ( $instance in $instances.Split(',')) {
    $GetJobData_Script_str = $GetJobData_Script_str.Replace('{{{dbname}}}',$instance)
    $AddJobDelayStep_Script_str = $AddJobDelayStep_Script_str.Replace('{{{dbname}}}',$instance)
    $JobDelaySchema_Script_str = $JobDelaySchema_Script_str.Replace('{{{dbname}}}',$instance)

    Start-Job -ScriptBlock $script_block -ArgumentList $instance,$JobDelaySchema_Script_str,$GetJobData_Script_str,$AddJobDelayStep_Script_str  | Out-Null
}

# Report Failure/Success as jobs are running
while ( Get-Job -State Running ) {
    Get-Job | Receive-Job
    Sleep 0.5
}

# Clean Up
Get-Job | Remove-Job