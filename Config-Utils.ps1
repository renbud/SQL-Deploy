[String] $ConfigPath = "$env:APPDATA\SQL-Deploy\config.json"

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

function Decrypt-EncryptedString {
    param(
        [Parameter(ValueFromPipeline=$true,Mandatory=$true,Position=0)]
        [string] $str
    )
    try {
        $sstr = ConvertTo-SecureString -String $str
        return Decrypt-SecureString $sstr
        }
    catch {
        return ""
        }
}

function Get-ConfigAsDictionary{
        if (Test-Path $ConfigPath) {
            $json = Get-Content -Raw  -Path $ConfigPath
        } else {
           $d1 = @{}
           $json = ConvertTo-Json -InputObject $d1
        }

        $custObj = ConvertFrom-Json -InputObject $json
 
        $dict = @{}
        $custObj.psobject.properties | Foreach { $dict[$_.Name] = $_.Value }
        return $dict
}

#####################################################################################
# Decrypts the password and converts from CustomObject to hash table (for splatting)
#####################################################################################
function Convert-Config-ToHashTable{
    param(
        [Parameter(ValueFromPipeline=$true,Mandatory=$true,Position=0)]
        $config,
        [Parameter(ValueFromPipeline=$true,Mandatory=$false,Position=1)]
        [Switch]$raw = $false
    )
    $dict = @{}
    $config.psobject.properties | Foreach { $dict[$_.Name] = $_.Value }
    if ($raw) {
        return $dict
    }

    $password = Decrypt-EncryptedString $config.password
    [Bool]$E = [System.Convert]::ToBoolean($config.E)
    $dict.Remove("password")
    $dict["P"] = $password
    $dict.Remove("E")
    if ($E) {
        $dict["E"] = $E
    }
    return $dict
}


#####################################################################################
# Converts a hashtable to an array that can be used to pass parameters to executables
#####################################################################################
function Convert-HashTable-ToArray{
    param(
        [Parameter(ValueFromPipeline=$true,Mandatory=$true,Position=0)]
        $dict
    )
    $args = @() # Empty array
    foreach ($key in $dict.Keys) 
    {
        $value = $dict[$key]
        if ($value -eq $false) {
            continue;
        }
        $args += $("-$key")
        if ($value -ne $true) {
            $args += $value
        }
    }
    return $args
}

#################################################
# Set supplied values into the configuration file
# Uses Read-Host if the values are not supplied as parameters
# Does not use the parameter prompt mechanism because it shows the current value in the prompt
##################################################
function Set-ConfigValues{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0, HelpMessage="Environment? e.g. <dev,uat,qa,prod>")]
        [String]$envname = "dev",
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

        $parentPath = Split-Path  $ConfigPath
        if ( !(Test-Path $parentPath))
           {md $parentPath}

        $dict = Get-ConfigAsDictionary

        if ($dict.Contains($envname)) {
            $env1 = $dict.Item($envname)
            $ht1 = Convert-Config-ToHashTable -config $env1 -raw
        }
        else {
            $ht1 = @{}
        }

        if (![String]::IsNullOrEmpty($S)) {
            $ht1.S = $S
        }
        else {
            $ret = Read-Host -Prompt "Server name or address ($($ht1.S))"
            if ($ret -ne "") {$ht1.S = $ret}
        }

        if (![String]::IsNullOrEmpty($d)) {
            $ht1.d = $d
        }
        else {
            $ret = Read-Host -Prompt "Database name ($($ht1.d))"
            if ($ret -ne "") {$ht1.d = $ret}
        }

        if ($E) {
            $ht1.E = $E
        }
        else {
            $ret = Read-Host -Prompt "Integrated Security <True or False> ($($ht1.E))"
            if ($ret -ne "") {$ht1.E =  [System.Convert]::ToBoolean($ret)}
            else {$ht1.E =  [System.Convert]::ToBoolean($ht1.E)}
        }
        if (-not $ht1.E) {
                if (![String]::IsNullOrEmpty($U)) {
                    $ht1.U = $U
                }
                else {
                    $ret = Read-Host -Prompt "User name ($($ht1.U))"
                    if ($ret -ne "") {$ht1.U = $ret}
                }

                if (![String]::IsNullOrEmpty($P)) {
                    $ssPass = ConvertTo-SecureString -String $P
                    $encryptedPassword = ConvertFrom-SecureString $ssPass
                    $ht1.password = $encryptedPassword
                }
                else {
                    $ssPass = Read-Host "Enter Password" -AsSecureString
                    if ($ssPass -ne $null) {
                        $ssPass
                        if ($(Decrypt-SecureString $ssPass).Length -gt 0) {
                            $encryptedPassword = ConvertFrom-SecureString $ssPass
                            $encryptedPassword
                            $ht1.password = $encryptedPassword
                        }
                    }
                }

        }

        <#
        $env = ConvertFrom-Json -InputObject "{
                                                ""S"":""$servername"",
                                                ""d"":""$dbname"",
                                                ""E"":""$integratedSecurity"",
                                                ""U"":""$username"",
                                                ""password"": ""$encryptedPassword""
                                                }"
        #>
 
        if ($dict.ContainsKey($envname)) {
            $dict.Remove($envname)
        }
        $dict.Add($envname, $ht1)
 
        $newJson = ConvertTo-Json $dict
        $newJson  | Out-File -FilePath $ConfigPath
 
        Get-Content -Path $ConfigPath

}
