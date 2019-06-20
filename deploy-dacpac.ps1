 <#########################################################################################
Prompt the user to set server, database, user and password
########################################################################################>
    Param(
        [Parameter(Mandatory=$true, Position=1, HelpMessage="DACPAC file path")]
        [String]$DacPacFile,
        [Parameter(Mandatory=$true, Position=2, HelpMessage="Server name or IP address")]
        [String]$DacPacTargetDatabaseServer,
        [Parameter(Mandatory=$false, Position=3, HelpMessage="Database name")]
        [String]$DacPacTargetDatabaseName = "NLISWEB",
        [Parameter(Mandatory=$true, Position=4, HelpMessage="User name")]
        [String]$DacPacTargetDatabaseUserId = "NLIS_USER",
        [Parameter(Mandatory=$false, Position=5, HelpMessage="Password")]
        [String]$DacPacTargetDatabasePassword=""
   )
 
     function Decrypt-SecureString {
        param(
            [Parameter(ValueFromPipeline=$true,Mandatory=$true,Position=0)]
            [System.Security.SecureString]
            $sstr
        )

        $marshal = [System.Runtime.InteropServices.Marshal]
        $ptr = $marshal::SecureStringToBSTR( $sstr )
        $str = $marshal::PtrToStringBSTR( $ptr )
        $marshal::ZeroFreeBSTR( $ptr )
        $str
    }
    $scriptDir = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
    $DacPacFile = Resolve-Path $DacPacFile

    if ($DacPacTargetDatabasePassword -eq "")
    {
        $ssPass = Read-Host "Enter Password" -AsSecureString
        $DacPacTargetDatabasePassword = Decrypt-SecureString $ssPass
    }
 
    echo "Deploying Internal Database to $DacPacTargetDatabaseName on $DacPacTargetDatabaseServer user: $DacPacTargetDatabaseUserId"

    echo "Loading Assemblies"
    Add-Type -Path "C:\Program Files (x86)\Microsoft SQL Server\110\SDK\Assemblies\Microsoft.SqlServer.Types.dll"
    Add-Type -Path "C:\Program Files (x86)\Microsoft SQL Server\110\DAC\bin\Microsoft.Data.Tools.Utilities.dll"
    Add-Type -Path "C:\Program Files (x86)\Microsoft SQL Server\110\SDK\Assemblies\Microsoft.SqlServer.TransactSql.ScriptDom.dll"
    Add-Type -Path "C:\Program Files (x86)\Microsoft SQL Server\110\DAC\bin\Microsoft.Data.Tools.Schema.Sql.dll"
    Add-Type -Path "C:\Program Files (x86)\Microsoft SQL Server\110\DAC\bin\Microsoft.SqlServer.Dac.dll"
    Add-PSSnapin SqlServerCmdletSnapin100 
    Add-PSSnapin SqlServerProviderSnapin100

    echo "Loading $DacPacFile"
    $dacPackage = [Microsoft.SqlServer.Dac.DacPackage]::Load($DacPacFile) 

    echo "Creating DacServices to Connect to SqlServer($DacPacTargetDatabaseServer)"
    $dacServices = New-Object Microsoft.SqlServer.Dac.DacServices "server=$DacPacTargetDatabaseServer;user id=$DacPacTargetDatabaseUserId;password=$DacPacTargetDatabasePassword"

    #echo "Deploying to Database($DacPacTargetDatabaseName)"
    #$dacServices.Deploy($dacPackage, $DacPacTargetDatabaseName, $true)
    
    $installationPath =  Split-Path $DacPacFile
    $scriptFileName = "$installationPath\DeploymentScript.sql"
    
    echo "Generating Deployment Script"
    $dacDeployOptions = New-Object Microsoft.SqlServer.Dac.DacDeployOptions
    $dacDeployOptions.BlockOnPossibleDataLoss = $false
    $dacDeployOptions.IncludeTransactionalScripts = $true
    $script = $dacServices.GenerateDeployScript($dacPackage, $DacPacTargetDatabaseName, $dacDeployOptions)
    echo "Saving the Deployment Script"
    [System.IO.File]::WriteAllText($scriptFileName, $script)
    
    echo "Running Deployment Script in Transaction"
    Invoke-SqlCmd -InputFile $scriptFileName -ServerInstance $DacPacTargetDatabaseServer -Database $DacPacTargetDatabaseName -Username $DacPacTargetDatabaseUserId -Password $DacPacTargetDatabasePassword

    echo "Deploying Internal Database Done Successfully"