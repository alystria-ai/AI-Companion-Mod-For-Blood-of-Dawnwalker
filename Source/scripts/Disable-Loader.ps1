$ErrorActionPreference='Stop'
if(Get-Process Dawnwalker -ErrorAction SilentlyContinue){throw 'Close Dawnwalker first'}
$projectRoot=Split-Path $PSScriptRoot -Parent
$info=Get-Content -LiteralPath (Join-Path $projectRoot 'runtime\installation.json') -Raw | ConvertFrom-Json
$bin=[IO.Path]::GetFullPath($info.gameBin)
$source=[IO.Path]::GetFullPath((Join-Path $bin 'dwmapi.dll'))
$destination=[IO.Path]::GetFullPath((Join-Path $projectRoot 'runtime\dwmapi.dll.disabled'))
if((Split-Path $source -Parent) -ne $bin){throw 'Invalid loader path'}
if(Test-Path -LiteralPath $destination){throw 'Disabled loader backup already exists'}
if((Get-FileHash -LiteralPath $source).Hash -ne (Get-FileHash -LiteralPath (Join-Path $projectRoot 'vendor\ue4ss\dwmapi.dll')).Hash){throw 'Loader changed; refusing to move another installation'}
Move-Item -LiteralPath $source -Destination $destination
Write-Host 'UE4SS disabled. The game executable and saves were not edited.'
