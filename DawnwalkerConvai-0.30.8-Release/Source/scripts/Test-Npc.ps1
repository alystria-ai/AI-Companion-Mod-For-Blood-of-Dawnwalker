param([ValidateSet('inspect','preview','stop')][string]$Action='inspect',[string]$Name='Anca')
$ErrorActionPreference='Stop'
if($Name.Contains("`n") -or $Name.Contains("`r") -or !$Name){throw 'Provide a non-empty actor name without newlines'}
$projectRoot=Split-Path $PSScriptRoot -Parent
$runtime=Join-Path $projectRoot 'runtime'
$id=[Guid]::NewGuid().ToString('N')
$path=Join-Path $runtime 'dev-command.txt'
[IO.File]::WriteAllText($path+'.tmp',"$id`n$Action`n$Name`n",[Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath ($path+'.tmp') -Destination $path -Force
Write-Output "Queued $Action for $Name ($id). Result: runtime\dev-response.txt"
