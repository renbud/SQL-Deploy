function Get-SqlFilesHash{
    [CmdletBinding()]
    param(
        [Parameter(Position=0,mandatory=$true)][string]$Path
    )

    Begin{
        #Write-Host "Path: $Path"
    }
    Process{
        $SqlFileSet = Get-ChildItem -Path "$Path\*" -Include *.sql
        $string = $SqlFileSet | Get-Content | Out-String
        if ($string.Trim().Length -eq 0) {
            Throw "Deployment folder $Path does not contain any *.sql code to release"
        }
        $stream = [IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes($string))
        $result = Get-FileHash -InputStream $stream -Algorithm SHA256
        return $result.Hash
    }
    End{}

}