##################################################################################################################
# Return a System.Data.SQLClient.SQLConnection
# The connection is unopened but has a connection string
# Thus it can be opened by the caller, but must also be closed by the caller
##################################################################################################################
function Get-SQLConnection {
    [CmdletBinding()]
    Param (
            [Parameter(Mandatory=$true, Position=1, HelpMessage="Server name or IP address")]
            [String]$S,
            [Parameter(Mandatory=$true, Position=2, HelpMessage="Database name")]
            [String]$d,
            [Parameter(Mandatory=$false, Position=3, HelpMessage="Is integrated security")]
            [Switch]$E = $false,
            [Parameter(Mandatory=$false, Position=4, HelpMessage="User name")]
            [String]$U,
            [Parameter(Mandatory=$false, Position=5, HelpMessage="Password")]
            [String]$P
    )
    $Connection = New-Object System.Data.SQLClient.SQLConnection
    [String] $str = "server='$S';database='$d';"
    if ($E -eq $true) {
        $str += "trusted_connection=true;"
    }
    else {
            $str += "user='$U'; password='$P'"
    }
    $Connection.ConnectionString = $str
    return $Connection
}


##################################################################################################################
# Execute SQLQuery
# Return a System.Data.DataTable
##################################################################################################################
function Execute-SQLQuery {
    [CmdletBinding()]
    Param (
            [Parameter(Mandatory=$true, Position=1, HelpMessage="Unopened SQLConnection object - with connection string")]
            [System.Data.SQLClient.SQLConnection]$Connection,
            [Parameter(Mandatory=$true, Position=3, HelpMessage="SQL query to run")]
            [String]$SQLQuery
    )
    try {
        $Datatable = New-Object System.Data.DataTable
        #Write-Host  $SQLQuery -ForegroundColor Yellow
        $Connection.Open()
        $Command = New-Object System.Data.SQLClient.SQLCommand
        $Command.Connection = $Connection
        $Command.CommandText = $SQLQuery
        $Reader = $Command.ExecuteReader()
        $Datatable.Load($Reader)
    }
    catch {
        throw
    }
    finally {
        if ($Connection.State -eq [System.Data.ConnectionState]::Open) {
            $Connection.Close()
        }
    }
    return ,$Datatable  # Why the comma you ask: https://stackoverflow.com/questions/1918190/strange-behavior-in-powershell-function-returning-dataset-datatable
}

##################################################################################################################
# Execute SQLCommand
# Returns 0 on success
##################################################################################################################
function Execute-SQLCommand {
    [CmdletBinding()]
    Param (
            [Parameter(Mandatory=$true, Position=1, HelpMessage="Unopened SQLConnection object - with connection string")]
            [System.Data.SQLClient.SQLConnection]$Connection,
            [Parameter(Mandatory=$true, Position=3, HelpMessage="SQL query to run")]
            [String]$SQLCommand
    )

    $Connection.Open()
    $Command = New-Object System.Data.SQLClient.SQLCommand
    $Command.Connection = $Connection
    $Command.CommandText = $SQLCommand
    [int]$res = $Command.ExecuteNonQuery()
    $Connection.Close()
}

##################################################################################################################
# Concatenate the *.sql files in the current folder into a single master file
# Save the file to $MasterFileName (which should have a .osql extension so it does not get included recursively!)
#
# Pre-processing is added to crete the deploy.Feature table if required
# Post-processing updates the deploy.Feature file
##################################################################################################################
function Create-MasterFile {
    [CmdletBinding()]
    Param (
            [Parameter(Mandatory=$true, Position=1, HelpMessage="Name of the combined script file")]
            [string]$MasterFileName
    )

    $contentStart = $SQL_MasterFileStart
    $contentEnd = $SQL_MasterFileEnd
    $contentMiddle = ""

    $SqlFileSet = Get-ChildItem -Path ".\*" -Include *.sql

    $SqlFileSet | Foreach-Object {
        $str =  "PRINT '################################'`r`n"
        $str += "PRINT 'Executing $($_.Name)'`r`n"
        $str += "PRINT '################################'`r`n"
        $str += ':r "' + $_.Name + '"' + "`r`nGO`r`n"
        $contentMiddle += $str
    }
    $contentAll = $contentStart + $contentMiddle + $contentEnd
    $contentAll | Out-File -FilePath $MasterFileName 
}


##################################################################################################################
# Checks if the feature has already been deployed
# Returns $false if the feature has been successfully deployed with the same hash
# Otherwise returns $true
##################################################################################################################
function Check-DeploymentRequired {
    [CmdletBinding()]
   Param (
            [Parameter(Mandatory=$true, Position=1, HelpMessage="Unopened SQLConnection object - with connection string")]
            [System.Data.SQLClient.SQLConnection]$Connection,
            [Parameter(Mandatory=$true, Position=1, HelpMessage="Path of folder containing .sql scripts to deploy?")]
            [String]$FeatureName,
            [Parameter(Mandatory=$true, Position=2, HelpMessage="Checksum of the .sql files")]
            [String]$HashString
    )

    try {
        $dataTable = Execute-SQLQuery -Connection $Connection -SQLQuery "$($SQL_CheckPreviousDeployment.Replace("%FeatureName%", $FeatureName))"
        if ($dataTable.Rows.Count -gt 0) {
            if ($dataTable.Rows[0].HashString -eq $HashString) {
                return $false
            }
        }
    }
    catch {
        return $true
    }

    return $true

}

##################################################################################################################
# Creates the feature tracking schema and table if required
# Creates the feature record if required,
#  otherwise updates the feature record with DeploymentStatus='Started', current hash, date etc..
##################################################################################################################
function Notify-DeploymentStarting {
    [CmdletBinding()]
   Param (
            [Parameter(Mandatory=$true, Position=1, HelpMessage="Unopened SQLConnection object - with connection string")]
            [System.Data.SQLClient.SQLConnection]$Connection,
            [Parameter(Mandatory=$true, Position=1, HelpMessage="Path of folder containing .sql scripts to deploy?")]
            [String]$FeatureName,
            [Parameter(Mandatory=$true, Position=2, HelpMessage="Checksum of the .sql files")]
            [String]$HashString,
            [Parameter(Mandatory=$false, Position=3, HelpMessage="Removal switch")]
            [Bool]$Remove=$false
    )

    $sqlArray = if ($Remove) { $SQL_RemovalStarting } else { $SQL_DeploymentStarting }
    foreach ($str in $SQL_DeploymentStarting) {
        $command = $str.Replace("%FeatureName%", $FeatureName).Replace("%HashString%", $HashString)
        Execute-SQLCommand -Connection $Connection -SQLCommand $command
    }
}

##################################################################################################################
# Updates the feature record with DeploymentStatus='Deployed', current hash, date etc..
##################################################################################################################
function Notify-DeploymentCompleted {
    [CmdletBinding()]
    Param (
            [Parameter(Mandatory=$true, Position=1, HelpMessage="Unopened SQLConnection object - with connection string")]
            [System.Data.SQLClient.SQLConnection]$Connection,
            [Parameter(Mandatory=$true, Position=1, HelpMessage="Path of folder containing .sql scripts to deploy?")]
            [String]$FeatureName,
            [Parameter(Mandatory=$true, Position=2, HelpMessage="Checksum of the .sql files")]
            [String]$HashString,
            [Parameter(Mandatory=$false, Position=3, HelpMessage="Removal switch")]
            [Bool]$Remove=$false
    )

    $command = if ($Remove) { $SQL_RemovalCompleted } else { $SQL_DeploymentCompleted }
    $command = $command.Replace("%FeatureName%", $FeatureName).Replace("%HashString%", $HashString)
    Execute-SQLCommand -Connection $Connection -SQLCommand $command
}

##################################################################################################################
# Updates the feature record with DeploymentStatus='Error', current hash, date etc..
##################################################################################################################
function Notify-DeploymentErrored {
    [CmdletBinding()]
    Param (
            [Parameter(Mandatory=$true, Position=1, HelpMessage="Unopened SQLConnection object - with connection string")]
            [System.Data.SQLClient.SQLConnection]$Connection,
            [Parameter(Mandatory=$true, Position=1, HelpMessage="Path of folder containing .sql scripts to deploy?")]
            [String]$FeatureName,
            [Parameter(Mandatory=$true, Position=2, HelpMessage="Checksum of the .sql files")]
            [String]$HashString,
            [Parameter(Mandatory=$false, Position=3, HelpMessage="Removal switch")]
            [Bool]$Remove=$false
    )

    $command = if ($Remove) { $SQL_RemovalErrored } else { $SQL_DeploymentErrored }
    $command = $command.Replace("%FeatureName%", $FeatureName).Replace("%HashString%", $HashString)
    Execute-SQLCommand -Connection $Connection -SQLCommand $command
}
##################################################################################################################
# SQL statements below
##################################################################################################################

$SQL_MasterFileStart = "
:on error exit

GO
PRINT 'Applying changes to '+@@SERVERNAME
GO
"

$SQL_MasterFileEnd = "
-------------------
PRINT 'Changes complete on '+@@SERVERNAME
"

$SQL_CheckPreviousDeployment = "SELECT HashString FROM deploy.Feature WHERE FeatureName='%FeatureName%' AND DeploymentStatus='Deployed'"

$SQL_DeploymentStarting = $("IF SCHEMA_ID('deploy') IS NULL exec sp_executesql N'CREATE SCHEMA deploy';",
    "IF OBJECT_ID('deploy.Feature') IS NULL
    CREATE TABLE deploy.Feature(
	    FeatureName sysname NOT NULL,
	    DateLastDeployed datetime2(0) NOT NULL,
	    DateLastRemoved datetime2(0) NULL,
	    HashString varchar(100) NOT NULL,
	    DeploymentStatus varchar(10) NOT NULL,
	    DeploymentCount int NOT NULL,
	    CONSTRAINT CK_Deployment_Status CHECK (DeploymentStatus IN ('Started','Deployed','Removed','Error','Removing')),
	    CONSTRAINT PK_Feature PRIMARY KEY CLUSTERED (FeatureName)
    )
    ",
    "IF EXISTS (SELECT * FROM deploy.Feature WHERE FeatureName='%FeatureName%')
    BEGIN
	    UPDATE deploy.Feature
	    SET DateLastDeployed = getdate(),
		    HashString = '%HashString%',
		    DeploymentStatus ='Started'
	    WHERE FeatureName='%FeatureName%'
    END
    ELSE
    BEGIN
        INSERT INTO deploy.Feature(FeatureName, DateLastDeployed, HashString, DeploymentStatus, DeploymentCount)
	    VALUES ('%FeatureName%', getdate(), '%HashString%', 'Started', 0)

    END");

$SQL_DeploymentCompleted = "
IF EXISTS (SELECT * FROM deploy.Feature WHERE FeatureName='%FeatureName%')
BEGIN
	UPDATE deploy.Feature
	SET DateLastDeployed = getdate(),
		HashString = '%HashString%',
		DeploymentStatus ='Deployed',
        DeploymentCount=DeploymentCount+1
	WHERE FeatureName='%FeatureName%'
END
ELSE
BEGIN
	INSERT INTO deploy.Feature(FeatureName, DateLastDeployed, HashString, DeploymentStatus, DeploymentCount)
	VALUES ('%FeatureName%', getdate(), '%HashString%', 'Deployed', 1)
END
"

$SQL_DeploymentErrored = "IF EXISTS (SELECT * FROM deploy.Feature WHERE FeatureName='%FeatureName%')
BEGIN
	UPDATE deploy.Feature
	SET DateLastDeployed = getdate(),
		HashString = '%HashString%',
		DeploymentStatus ='Error'
	WHERE FeatureName='%FeatureName%'
END
ELSE
BEGIN
	INSERT INTO deploy.Feature(FeatureName, DateLastDeployed, HashString, DeploymentStatus, DeploymentCount)
	VALUES ('%FeatureName%', getdate(), '%HashString%', 'Error', 0)
END
"

$SQL_RemovalStarting = $(
    "UPDATE deploy.Feature
	SET DateLastRemoved = getdate(),
		DeploymentStatus ='Removing'
	WHERE FeatureName='%FeatureName%'
    ");

$SQL_RemovalCompleted = "
	UPDATE deploy.Feature
	SET DateLastRemoved = getdate(),
		DeploymentStatus ='Removed'
	WHERE FeatureName='%FeatureName%'
"

$SQL_RemovalErrored = "
	UPDATE deploy.Feature
	SET DateLastRemoved = getdate(),
		DeploymentStatus ='Error'
	WHERE FeatureName='%FeatureName%'
"