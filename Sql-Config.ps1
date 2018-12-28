<#########################################################################################
Prompt the user to set server, database, user and password for an environment
########################################################################################>
    Param(
        [Parameter(Mandatory=$true, Position=0, HelpMessage="Environment to deploy to?")][ValidateSet('dev','uat','qa','prod')]
        [String]$EnvName,
        [Parameter(Mandatory=$false, Position=1, HelpMessage="Server name or IP address")]
        [String]$S,
        [Parameter(Mandatory=$false, Position=2, HelpMessage="Database name")]
        [String]$d,
        [Parameter(Mandatory=$false, Position=3, HelpMessage="Is integrated security")]
        [Switch]$E = $false,
        [Parameter(Mandatory=$false, Position=4, HelpMessage="User name")]
        [String]$U,
        [Parameter(Mandatory=$false, Position=5, HelpMessage="Password")]
        [String]$P
   )

$scriptDir = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
. $scriptDir\Config-Utils.ps1

Set-ConfigValues $EnvName $S $d $E $U $P
