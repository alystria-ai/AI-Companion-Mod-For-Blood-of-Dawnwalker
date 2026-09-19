param([string]$GameDirectory=$env:DAWNWALKER_GAME_DIRECTORY)
$ErrorActionPreference='Stop'
if([string]::IsNullOrWhiteSpace($GameDirectory)){throw 'Pass -GameDirectory with your game installation folder, or set DAWNWALKER_GAME_DIRECTORY.'}
$projectRoot=Split-Path $PSScriptRoot -Parent
$bin=Join-Path $GameDirectory 'Dawnwalker\Binaries\Win64'
if (!(Test-Path -LiteralPath (Join-Path $bin 'Dawnwalker.exe'))) {throw 'Dawnwalker.exe not found'}
if (Get-Process Dawnwalker -ErrorAction SilentlyContinue) {throw 'Close Dawnwalker before installing'}
$package=Join-Path $projectRoot 'vendor\ue4ss'
if (!(Test-Path -LiteralPath $package)) {throw 'Extract the supplied Dawnwalker UE4SS package into vendor\ue4ss first'}
if ((Test-Path -LiteralPath (Join-Path $bin 'dwmapi.dll')) -or (Test-Path -LiteralPath (Join-Path $bin 'ue4ss'))) {throw 'An existing loader is present. Preserve it before reinstalling; this installer will not overwrite it.'}
$runtime=Join-Path $projectRoot 'runtime'
New-Item -ItemType Directory -Force -Path $runtime | Out-Null
$exeHash=(Get-FileHash -LiteralPath (Join-Path $bin 'Dawnwalker.exe')).Hash
$supported='7AD7D09645B0589DC0FF78B53AA1A7B18ECA79B1B7F888B403AB41D88AC7E853'
if ($exeHash -ne $supported) {Write-Warning 'Executable differs from the loader tested build. Runtime compatibility is unverified. Disable-Loader.ps1 rolls back the loader.'}
$manifest=[System.Collections.Generic.List[object]]::new()
foreach($file in Get-ChildItem -LiteralPath $package -Recurse -File) {
    $relative=$file.FullName.Substring($package.Length+1)
    $destination=Join-Path $bin $relative
    if(Test-Path -LiteralPath $destination){throw "Would overwrite existing file: $destination"}
}
foreach($file in Get-ChildItem -LiteralPath $package -Recurse -File) {
    $relative=$file.FullName.Substring($package.Length+1);$destination=Join-Path $bin $relative
    New-Item -ItemType Directory -Force -Path (Split-Path $destination -Parent) | Out-Null
    Copy-Item -LiteralPath $file.FullName -Destination $destination
    $manifest.Add(@{path=$destination;source=$file.FullName})
}
$mod=Join-Path $bin 'ue4ss\Mods\DawnwalkerConvai'
New-Item -ItemType Directory -Force -Path (Join-Path $mod 'Scripts') | Out-Null
Copy-Item -Path (Join-Path $projectRoot 'mod\Scripts\*.lua') -Destination (Join-Path $mod 'Scripts')
$luaPath=$runtime.Replace('\','/').Replace("'","\'")
Set-Content -LiteralPath (Join-Path $mod 'Scripts\runtime_path.lua') -Value "return '$luaPath'" -Encoding ascii
New-Item -ItemType File -Path (Join-Path $mod 'enabled.txt') | Out-Null
$modsTxt=Join-Path $bin 'ue4ss\Mods\mods.txt'
$txt=Get-Content -LiteralPath $modsTxt -Raw
$txt=$txt.Replace('; Built-in keybinds',"DawnwalkerConvai : 1`r`n`r`n; Built-in keybinds")
Set-Content -LiteralPath $modsTxt -Value $txt -Encoding ascii
$modsJson=Join-Path $bin 'ue4ss\Mods\mods.json'
$list=@(Get-Content -LiteralPath $modsJson -Raw | ConvertFrom-Json)
$list+=@{mod_name='DawnwalkerConvai';mod_enabled=$true}
ConvertTo-Json -InputObject $list -Depth 5 | Set-Content -LiteralPath $modsJson -Encoding ascii
@{gameBin=$bin;project=$projectRoot;exeHash=$exeHash;loaderTestedHash=$supported;node=(Get-Command node).Source;installedAt=(Get-Date).ToString('o');files=$manifest} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $runtime 'installation.json') -Encoding utf8
Write-Host 'Installed. F5 manages companions. Face a nearby character: F6/F7 single text/voice; F8/F9 group text/voice.'
Write-Host "Diagnostics: $runtime\npc-diagnostics.txt"
