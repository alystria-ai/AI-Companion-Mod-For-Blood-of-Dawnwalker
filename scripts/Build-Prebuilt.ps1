param([switch]$BundleSharedKey,[switch]$StableNames)
$ErrorActionPreference='Stop'
$taskRoot=Split-Path $PSScriptRoot -Parent
$taskStamp=Get-Date -Format 'yyyyMMdd-HHmmss'
$taskVersion=(Get-Content (Join-Path $taskRoot 'package.json') -Raw|ConvertFrom-Json).version
if($taskVersion -notmatch '^\d+\.\d+\.\d+$'){throw 'Invalid release version'}
$taskSuffix=if($StableNames){''}else{'-'+$taskStamp}
$taskRelease=Join-Path $taskRoot ('dist/DawnwalkerConvai-'+$taskVersion+$taskSuffix)
$taskOutput=$taskRelease+'-Complete'
$taskMod=Join-Path $taskOutput 'Dawnwalker/Binaries/Win64/ue4ss/Mods/DawnwalkerConvai'
$taskPayload=Join-Path $taskMod 'Payload'
foreach($taskDir in @('bridge/native','bridge/public','bridge/fonts','mod/Scripts','scripts','runtime','characters','node','licenses')){New-Item -ItemType Directory -Force -Path (Join-Path $taskPayload $taskDir)|Out-Null}
$taskConfig=Get-Content -LiteralPath (Join-Path $taskRoot 'runtime/convai-config.json') -Raw | ConvertFrom-Json
$taskConfig.PSObject.Properties.Remove('endUserId')
$taskConfig.roster=@($taskConfig.roster | Select-Object key,id,name,kind,gender,aliases)
$taskDefaults=Join-Path $taskRoot ('runtime/shared-defaults-'+$taskStamp+'.json')
try {
 if($BundleSharedKey){
  if(!$taskConfig.apiKey){throw 'No configured shared service key'}
  $taskJson=$taskConfig|ConvertTo-Json -Depth 30 -Compress
  if($taskJson.Length -gt 26000){throw 'Bundled configuration exceeds startup size limit'}
  [IO.File]::WriteAllText($taskDefaults,$taskJson,[Text.UTF8Encoding]::new($false))
  & (Join-Path $PSScriptRoot 'Build-WebView.ps1') -OutputName ConvaiHost.distribution.exe -SharedConfig $taskDefaults
 }else{& (Join-Path $PSScriptRoot 'Build-WebView.ps1') -OutputName ConvaiHost.distribution.exe}
 if($LASTEXITCODE -ne 0){throw 'Helper build failed'}
 Copy-Item -LiteralPath (Join-Path $taskRoot 'bridge/native/ConvaiHost.distribution.exe') -Destination (Join-Path $taskPayload 'bridge/native/ConvaiHost.exe')
 foreach($taskName in @('companion_native_v9.dll','companion_assets_v2.dll','companion_protection_v2.dll','background_launcher_v1.dll','Microsoft.Web.WebView2.Core.dll','Microsoft.Web.WebView2.WinForms.dll','WebView2Loader.dll')){Copy-Item -LiteralPath (Join-Path $taskRoot ('bridge/native/'+$taskName)) -Destination (Join-Path $taskPayload 'bridge/native')}
 foreach($taskFile in Get-ChildItem -LiteralPath (Join-Path $taskRoot 'bridge') -Filter '*.mjs' -File){Copy-Item -LiteralPath $taskFile.FullName -Destination (Join-Path $taskPayload 'bridge')}
 foreach($taskDir in @('bridge/public','bridge/fonts','mod/Scripts')){Get-ChildItem -LiteralPath (Join-Path $taskRoot $taskDir) -File | ForEach-Object {Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $taskPayload $taskDir)}}
 foreach($taskName in @('companion-config.json','companion-lore.json','quest-knowledge.json','combat-roster.json','romance-config.json')){Copy-Item -LiteralPath (Join-Path $taskRoot ('characters/'+$taskName)) -Destination (Join-Path $taskPayload 'characters')}
 Copy-Item -LiteralPath (Join-Path $taskRoot 'scripts/Start-Background.ps1') -Destination (Join-Path $taskPayload 'scripts')
 $taskNode=(Get-Content -LiteralPath (Join-Path $taskRoot 'runtime/node-path.txt') -Raw).Trim()
 Copy-Item -LiteralPath $taskNode -Destination (Join-Path $taskPayload 'node/node.exe')
 $taskConfig.PSObject.Properties.Remove('apiKey')
 [IO.File]::WriteAllText((Join-Path $taskPayload 'runtime/convai-config.json'),($taskConfig|ConvertTo-Json -Depth 30),[Text.UTF8Encoding]::new($false))
 Set-Content -LiteralPath (Join-Path $taskPayload 'runtime/native-ui.enabled') -Value '1' -Encoding ascii
 New-Item -ItemType Directory -Force -Path (Join-Path $taskMod 'Scripts')|Out-Null
 foreach($taskName in @('main.lua','live_reload.lua')){Copy-Item -LiteralPath (Join-Path $taskRoot ('mod/Scripts/'+$taskName)) -Destination (Join-Path $taskMod 'Scripts')}
 $taskBootstrap=@'
local source=debug.getinfo(1,'S').source:gsub('^@',''):gsub('\\','/')
local scripts=assert(source:match('^(.*)/[^/]+$'),'Cannot locate mod Scripts folder')
local mod=assert(scripts:match('^(.*)/Scripts$'),'Unexpected mod folder')
local root=mod..'/Payload/runtime'
local function write(name,value)local f=assert(io.open(root..'/'..name,'w'));f:write(value);f:close()end
write('node-path.txt',mod..'/Payload/node/node.exe')
write('mod-directory.txt',mod)
return root
'@
 Set-Content -LiteralPath (Join-Path $taskMod 'Scripts/runtime_path.lua') -Value $taskBootstrap -Encoding utf8
 foreach($taskName in @('config.ini','mod_settings.ini','keybindings.ini')){Copy-Item -LiteralPath (Join-Path $taskRoot ('mod/'+$taskName)) -Destination $taskMod}
 Set-Content -LiteralPath (Join-Path $taskMod 'enabled.txt') -Value '' -Encoding ascii
 Copy-Item -LiteralPath (Join-Path $taskRoot 'docs/PREBUILT-INSTALL.md') -Destination (Join-Path $taskOutput 'README.md')
 New-Item -ItemType Directory -Force -Path (Join-Path $taskPayload 'docs')|Out-Null
 Copy-Item -LiteralPath (Join-Path $taskRoot 'docs/PREBUILT-INSTALL.md') -Destination (Join-Path $taskPayload 'docs/INSTALL.md')
 Copy-Item -LiteralPath (Join-Path $taskRoot 'docs/FILE-STRUCTURE.md') -Destination (Join-Path $taskPayload 'docs/FILE-STRUCTURE.md')
 [IO.File]::WriteAllText((Join-Path $taskPayload 'release.json'),(@{version=$taskVersion;game='1.05';ue4ss='1.2.1 RC6';menu='1.0.6.2';native=9;assets=2;protection=2}|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
 Copy-Item -LiteralPath (Join-Path $taskRoot 'docs/THIRD-PARTY-PREBUILT.txt') -Destination (Join-Path $taskPayload 'licenses/THIRD-PARTY.txt')
 foreach($taskName in @('NODE-LICENSE.txt','WEBVIEW2-LICENSE.txt','WEBVIEW2-NOTICE.txt')){Copy-Item -LiteralPath (Join-Path $taskRoot ('vendor/release-licenses/'+$taskName)) -Destination (Join-Path $taskPayload 'licenses')}
 foreach($taskFile in Get-ChildItem -LiteralPath (Join-Path $taskRoot 'vendor/release-licenses/browser') -File){Copy-Item -LiteralPath $taskFile.FullName -Destination (Join-Path $taskPayload 'licenses')}
 # Distribution is an explicit allowlist: no saves, diagnostics, machine paths or browser profile.
 # Split packages retain identical game-root-relative destinations. Both halves
 # are required; a scripts-only archive is not a standalone working install.
 foreach($taskPart in @('Scripts','Runtime')){
  $taskPartRoot=$taskRelease+'-'+$taskPart
  foreach($taskFile in Get-ChildItem -LiteralPath (Join-Path $taskOutput 'Dawnwalker') -Recurse -File){
   $taskRelative=$taskFile.FullName.Substring($taskOutput.Length+1)
   $taskLua=$taskFile.Extension -eq '.lua'
   if(($taskPart -eq 'Scripts' -and $taskLua) -or ($taskPart -eq 'Runtime' -and !$taskLua)){
    $taskDestination=Join-Path $taskPartRoot $taskRelative
    New-Item -ItemType Directory -Force -Path (Split-Path $taskDestination -Parent)|Out-Null
    Copy-Item -LiteralPath $taskFile.FullName -Destination $taskDestination
   }
  }
  if($taskPart -eq 'Scripts'){continue}
  $taskIntro=if($taskPart -eq 'Scripts'){'# Scripts package: Runtime package also required'}else{'# Runtime package: Scripts package also required'}
  $taskIntro+="`r`n`r`nExtract BOTH split packages into the game installation folder, merging the Dawnwalker directory. Alternatively use only the Complete package. Do not run the helper manually.`r`n`r`n"
  [IO.File]::WriteAllText((Join-Path $taskPartRoot 'README.md'),$taskIntro+[IO.File]::ReadAllText((Join-Path $taskOutput 'README.md')),[Text.UTF8Encoding]::new($false))
 }
 foreach($taskPackage in @($taskOutput,($taskRelease+'-Scripts'),($taskRelease+'-Runtime'))){
  if($taskPackage -eq ($taskRelease+'-Scripts')){
   Compress-Archive -LiteralPath (Join-Path $taskPackage 'Dawnwalker') -DestinationPath ($taskPackage+'.zip')
   Write-Output ('Release package: '+$taskPackage+'.zip')
   continue
  }
  Get-ChildItem -LiteralPath $taskPackage -Recurse -File | Sort-Object FullName | ForEach-Object {((Get-FileHash -LiteralPath $_.FullName).Hash+'  '+$_.FullName.Substring($taskPackage.Length+1))} | Set-Content -LiteralPath (Join-Path $taskPackage 'SHA256SUMS.txt') -Encoding ascii
  $taskArchive=$taskPackage+'.zip';Compress-Archive -LiteralPath (Join-Path $taskPackage 'Dawnwalker'),(Join-Path $taskPackage 'README.md'),(Join-Path $taskPackage 'SHA256SUMS.txt') -DestinationPath $taskArchive
  Write-Output ('Release package: '+$taskArchive)
 }
}finally{if(Test-Path -LiteralPath $taskDefaults){Remove-Item -LiteralPath $taskDefaults}}
