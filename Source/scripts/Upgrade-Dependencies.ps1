param([string]$LoaderDirectory,[string]$MenuDirectory)
$ErrorActionPreference='Stop'
$taskRoot=Split-Path $PSScriptRoot -Parent
$taskBin=(Get-Content -LiteralPath (Join-Path $taskRoot 'runtime/installation.json') -Raw | ConvertFrom-Json).gameBin
if(Get-Process Dawnwalker -ErrorAction SilentlyContinue){throw 'Close the game before upgrading UE4SS.'}
$taskLoader=[IO.Path]::GetFullPath($LoaderDirectory)
$taskMenu=[IO.Path]::GetFullPath($MenuDirectory)
if(!(Test-Path -LiteralPath (Join-Path $taskLoader 'ue4ss/UE4SS.dll'))){throw 'Loader package layout not recognized'}
if(!(Test-Path -LiteralPath (Join-Path $taskMenu 'Scripts/main.lua'))){throw 'Menu package layout not recognized'}
$taskBackup=Join-Path $taskRoot ('backups/update-105-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force -Path $taskBackup | Out-Null
$taskChanges=[System.Collections.Generic.List[object]]::new()
function Install-ScopedFile([string]$Source,[string]$Relative){
 $taskTarget=[IO.Path]::GetFullPath((Join-Path $taskBin $Relative))
 if(!$taskTarget.StartsWith([IO.Path]::GetFullPath($taskBin)+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Destination escaped the game binary directory'}
 $taskExists=Test-Path -LiteralPath $taskTarget
 if($taskExists){$taskCopy=Join-Path $taskBackup $Relative;New-Item -ItemType Directory -Force -Path (Split-Path $taskCopy -Parent) | Out-Null;Copy-Item -LiteralPath $taskTarget -Destination $taskCopy}
 New-Item -ItemType Directory -Force -Path (Split-Path $taskTarget -Parent) | Out-Null
 Copy-Item -LiteralPath $Source -Destination $taskTarget
 $taskChanges.Add(@{relative=$Relative;existed=$taskExists;sha256=(Get-FileHash -LiteralPath $taskTarget).Hash})
}
foreach($taskFile in Get-ChildItem -LiteralPath $taskLoader -Recurse -File){
 $taskRelative=$taskFile.FullName.Substring($taskLoader.Length+1)
 if($taskRelative -in @('ue4ss\Mods\mods.txt','ue4ss\Mods\mods.json')){continue}
 Install-ScopedFile $taskFile.FullName $taskRelative
}
foreach($taskFile in Get-ChildItem -LiteralPath $taskMenu -Recurse -File){
 Install-ScopedFile $taskFile.FullName ('ue4ss\Mods\DawnwalkerModMenu\'+$taskFile.FullName.Substring($taskMenu.Length+1))
}
$taskMod=Join-Path $taskBin 'ue4ss/Mods/DawnwalkerConvai'
foreach($taskName in @('main.lua','live_reload.lua')){Install-ScopedFile (Join-Path $taskRoot ('mod/Scripts/'+$taskName)) ('ue4ss\Mods\DawnwalkerConvai\Scripts\'+$taskName)}
Install-ScopedFile (Join-Path $taskRoot 'mod/mod_settings.ini') 'ue4ss\Mods\DawnwalkerConvai\mod_settings.ini'
if(!(Test-Path -LiteralPath (Join-Path $taskMod 'config.ini'))){Install-ScopedFile (Join-Path $taskRoot 'mod/config.ini') 'ue4ss\Mods\DawnwalkerConvai\config.ini'}
Set-Content -LiteralPath (Join-Path $taskRoot 'runtime/mod-directory.txt') -Value $taskMod.Replace('\','/') -Encoding utf8
Set-Content -LiteralPath (Join-Path $taskRoot 'runtime/native-ui.enabled') -Value '1' -Encoding ascii
$taskChanges | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $taskBackup 'manifest.json') -Encoding utf8
Write-Output ('Dependencies updated; backed up '+$taskChanges.Count+' installed files under '+$taskBackup)
