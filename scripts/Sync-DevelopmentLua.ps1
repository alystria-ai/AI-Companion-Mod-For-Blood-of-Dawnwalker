param([string]$ModDirectory)
$ErrorActionPreference='Stop'
$taskRoot=Split-Path $PSScriptRoot -Parent
if(!$ModDirectory){$ModDirectory=(Get-Content -LiteralPath (Join-Path $taskRoot 'runtime/mod-directory.txt') -Raw).Trim()}
$taskMod=(Resolve-Path -LiteralPath $ModDirectory).Path
$taskPayload=Join-Path $taskMod 'Payload/mod/Scripts'
$taskBootstrap=Join-Path $taskMod 'Scripts'
if(!(Test-Path -LiteralPath (Join-Path $taskBootstrap 'runtime_path.lua')) -or !(Test-Path -LiteralPath $taskPayload)){
 throw 'Expected an existing installed DawnwalkerConvai mod with its Payload and bootstrap.'
}
& (Join-Path $PSScriptRoot 'Check-LuaModules.ps1')
$taskBackup=Join-Path $taskRoot ('runtime/install-backups/lua-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $taskBackup -Force | Out-Null
Copy-Item -LiteralPath $taskPayload -Destination (Join-Path $taskBackup 'payload') -Recurse
Copy-Item -LiteralPath $taskBootstrap -Destination (Join-Path $taskBackup 'bootstrap') -Recurse
$taskFiles=Get-ChildItem -LiteralPath (Join-Path $taskRoot 'mod/Scripts') -Filter '*.lua' -File
foreach($taskFile in $taskFiles){Copy-Item -LiteralPath $taskFile.FullName -Destination (Join-Path $taskPayload $taskFile.Name)}
foreach($taskName in @('live_reload.lua','main.lua')){
 Copy-Item -LiteralPath (Join-Path $taskPayload $taskName) -Destination (Join-Path $taskBootstrap $taskName)
}
& (Join-Path $PSScriptRoot 'Check-LuaModules.ps1') -ScriptsDirectory $taskPayload -BootstrapDirectory $taskBootstrap
foreach($taskFile in $taskFiles){
 if((Get-FileHash -LiteralPath $taskFile.FullName).Hash -ne (Get-FileHash -LiteralPath (Join-Path $taskPayload $taskFile.Name)).Hash){throw "Installed Lua differs from source: $($taskFile.Name)"}
}
Write-Output 'Complete Lua update synchronized and verified; configuration preserved. Startup bootstrap changes take effect on the next launch.'
