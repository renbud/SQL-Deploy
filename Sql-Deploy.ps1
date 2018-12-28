<#########################################################################################
Command line utility that can deploy a folder of SQL scripts.
The utility can be used to release all the scripts in the folder (e.g)
e.g. Release -Env QA  -DeploymentRoot: "H:\Database\_Release\" -DeploymentFolder "2018\COLES PIC_Changes"

This is a step towards automating the release process.

Requirement:

# Specify path, environment(server, database, user, password) as parameters
# Run all \*.sql scripts in the specified path folder
# Log all output
# Exit on error and display clear error message. Also log error.

Additional requirement:

* Log each release to a database table, keyed by folder name. The folder name is the release name. This is a unique key
* Changes are detected by hashing the \*.sql files
* (If a release is changed and re-run , then a version number is incremented automatically??)
* Rollback. Run the scripts in a “Rollback” folder and update the status of the release to “rolled back”
* After the release, check-in the database schema changes by calling SQLCompare to compare the updated schema with a source control scripts folder.
   Call GIT commit with the release folder name and version as a comment. Push the changes to the origin.
* The password and other environment parameters  should be held in a config.json file.
  The password should be stored encrypted. Hence the password is not required on the command line when invoking the deployment utility.
########################################################################################>
Param(
    [Parameter(Mandatory=$true, Position=0, HelpMessage="Environment to deploy to?")][ValidateSet('dev','uat','qa','prod')]
    [String]$EnvName,
    [Parameter(Mandatory=$true, Position=1, HelpMessage="Root path of all deployment folders?")]
    [String]$DeploymentRoot,
    [Parameter(Mandatory=$true, Position=2, HelpMessage="Folder containing .sql scripts to deploy? (Relative to DeploymentRoot)")]
    [String]$DeploymentFolder,
    [Parameter(Mandatory=$false, Position=3, HelpMessage="Server name?")] # The following parameters mimic the SQLCMD.exe credentials parameters
    [String]$S,
    [Parameter(Mandatory=$false, Position=4, HelpMessage="Database name?")]
    [String]$d,
    [Parameter(Mandatory=$false, Position=5, HelpMessage="Use integrated security?")]
    [Switch]$E,
    [Parameter(Mandatory=$false, Position=6, HelpMessage="User name?")]
    [String]$U,
    [Parameter(Mandatory=$false, Position=7, HelpMessage="Password?")]
    [String]$P,
    [Parameter(Mandatory=$false, Position=8, HelpMessage="Remove deployment?")]
    [Switch]$Remove
)

##############################################################################################################################################################
# Check parameters
##############################################################################################################################################################
#Write-Host $EnvName
#Write-Host $DeploymentRoot
#Write-Host $DeploymentFolder
if (-NOT (Test-Path $DeploymentRoot -PathType 'Container')) 
{ 
    Throw "$($DeploymentRoot) is not a valid folder."
}

$DeploymentFolder = $DeploymentFolder.TrimStart("\").TrimEnd("\")
$Path = Resolve-Path ($DeploymentRoot +"\" +$DeploymentFolder) -ErrorAction SilentlyContinue
if ($Path -eq $null) 
{ 
    Throw "$($DeploymentFolder) is not a valid deployment folder. DeploymentFolder must be a sub-folder relative to $DeploymentRoot."
}
if ($Remove) {
    $Path = Resolve-Path ($DeploymentRoot +"\" +$DeploymentFolder+"\Remove") -ErrorAction SilentlyContinue
    if ($Path -eq $null) 
    { 
        Throw "$($DeploymentFolder) does not have a sub-folder named ""Remove"". In order to remove a deployment, a sub-folder called ""Remove"" containing .sql scripts to remove the feature must be created under $DeploymentFolder."
    }
}


##############################################################################################################################################################
# Load supporting modules
##############################################################################################################################################################

$scriptDir = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
. $scriptDir\Get-SqlFilesHash.ps1
. $scriptDir\Config-Utils.ps1
. $scriptDir\Sql-Runner.ps1

##############################################################################################################################################################
# Check configuration
##############################################################################################################################################################
$config = (Get-ConfigAsDictionary)."$EnvName" # Configuration for the environment contains the connection details and credentials
if (($config -eq $null) -and ([String]::IsNullOrEmpty($S)) ) {
    Throw "Environment $EnvName has not been configured. Either use Sql-Config.ps1 to set this up,  or pass -S -d -U -P -E parameters instead"
}
if (($config -eq $null) ) {
    $connectionHashTable  = @{ S = $S }
}
else {
    $connectionHashTable = Convert-Config-ToHashTable $config
}

if (![String]::IsNullOrEmpty($d)) {
    $connectionHashTable.Remove("d")
    $connectionHashTable.Add("d", $d)

}
if ($E -eq $true) {
    $connectionHashTable.Remove("E")
    $connectionHashTable.Add("E", $E)

}
if (![String]::IsNullOrEmpty($U)) {
    $connectionHashTable.Remove("U")
    $connectionHashTable.Add("U", $U)

}
if (![String]::IsNullOrEmpty($S)) {
    $connectionHashTable.Remove("S")
    $connectionHashTable.Add("S", $S)
}

if (![String]::IsNullOrEmpty($P)) {
    $connectionHashTable.Remove("P")
    $connectionHashTable.Add("P", $P)
}

##############################################################################################################################################################
# Do the work
##############################################################################################################################################################

Push-Location -Path $Path # make the folder that contains the .sql scripts the current folder


try {
    $hashString = Get-SqlFilesHash -Path $Path # Hash of all .sql files in $Path
    $connection = Get-SQLConnection @connectionHashTable

    if (-not $Remove) {
        if (!(Check-DeploymentRequired -Connection $connection -FeatureName $DeploymentFolder -HashString $hashString -ErrorAction stop))
        {
                Write-Host "Deployment of feature $($DeploymentFolder) already completed." -ForegroundColor Green
                Exit
        }
    }
    Notify-DeploymentStarting -Connection $connection -FeatureName $DeploymentFolder -HashString $hashString -Remove $Remove


    $masterFileName = "_master.osql" # This is a temporary file containing the concatenation of all the release files in order (plus some pre and post sql commands)
    Create-MasterFile -MasterFileName $masterFileName

    $sqlcmdArgs0 = @{b=$true; i=$masterFileName;  o=$($EnvName+'_master.log')} + $connectionHashTable
    $sqlcmdArgs = Convert-HashTable-ToArray $sqlcmdArgs0 # Use normal array instead of hash table to pass arguments to .exe
    #$sqlcmdArgs
    &SqlCmd $sqlcmdArgs

    Get-Content $($EnvName+'_master.log') # Output was re-directed to file

    if ($LASTEXITCODE -ne 0)
    {
        Notify-DeploymentErrored -Connection $connection -FeatureName $DeploymentFolder -HashString $hashString -Remove $Remove
        Throw "$(if ($Remove) {'Removal'} else {'Deployment'}) of feature $($DeploymentFolder) failed. Check the log file in the folder containing the .sql scripts"
    }
    else
    {
        Notify-DeploymentCompleted -Connection $connection -FeatureName $DeploymentFolder -HashString $hashString -Remove $Remove
        Write-Host "$(if ($Remove) {'Removal'} else {'Deployment'}) of feature $($DeploymentFolder) succeeded." -ForegroundColor Green
    }
}
catch {
    # Do not continue after any error
    throw
}
finally {
    Pop-Location
}