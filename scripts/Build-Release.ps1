$ErrorActionPreference='Stop'
$taskRoot=Split-Path $PSScriptRoot -Parent
Set-Location $taskRoot
$taskVersion=(Get-Content package.json -Raw|ConvertFrom-Json).version
$taskNotes=Join-Path $taskRoot ('docs/RELEASE-'+$taskVersion.Replace('.','')+'.md')
if(!(Test-Path -LiteralPath $taskNotes)){throw 'Matching release notes are required before building'}
if(!$env:CONVAI_API_KEY){throw 'CONVAI_API_KEY is required for the shared-service release'}
if(Test-Path runtime/convai-config.json){throw 'Use a clean build checkout; existing runtime configuration will not be overwritten'}
$taskConfig=Get-Content characters/release-config.json -Raw | ConvertFrom-Json
$taskConfig | Add-Member -NotePropertyName apiKey -NotePropertyValue $env:CONVAI_API_KEY.Trim() -Force
$taskConfig.PSObject.Properties.Remove('endUserId')
try{
 [IO.File]::WriteAllText((Join-Path $taskRoot 'runtime/convai-config.json'),($taskConfig|ConvertTo-Json -Depth 30),[Text.UTF8Encoding]::new($false))
 & ./scripts/Build-CompanionNative.ps1
 & ./scripts/Build-CompanionNative.ps1 -AssetLoader
 & ./scripts/Build-CompanionNative.ps1 -Protection
 & ./scripts/Build-BackgroundLauncher.ps1
 & ./scripts/Build-Prebuilt.ps1 -BundleSharedKey -StableNames
}finally{
 $taskConfig=$null
 if(Test-Path runtime/convai-config.json){Remove-Item -LiteralPath (Join-Path $taskRoot 'runtime/convai-config.json')}
}
$taskVersion=(Get-Content package.json -Raw|ConvertFrom-Json).version
python scripts/package-multilingual.py "dist/DawnwalkerConvai-$taskVersion-Runtime.zip" "dist/DawnwalkerConvai-$taskVersion-Multilingual.zip"
if($LASTEXITCODE){throw 'Multilingual package failed'}
$taskSource=Join-Path $taskRoot 'dist/Source'
New-Item -ItemType Directory -Force $taskSource | Out-Null
foreach($taskFile in (& git ls-files)){
 if($taskFile -match '\.(zip|exe|dll|tgz)$' -or $taskFile -eq 'SHA256SUMS.txt'){continue}
 $taskDestination=Join-Path $taskSource $taskFile
 New-Item -ItemType Directory -Force (Split-Path $taskDestination -Parent)|Out-Null
 Copy-Item -LiteralPath (Join-Path $taskRoot $taskFile) -Destination $taskDestination
}
Compress-Archive -Path (Join-Path $taskSource '*') -DestinationPath "dist/DawnwalkerConvai-$taskVersion-Source.zip"
# Include the GitHub workflow in the source archive; Compress-Archive skips hidden entries.
Add-Type -AssemblyName System.IO.Compression.FileSystem
$taskSourceArchive=[IO.Compression.ZipFile]::Open((Join-Path $taskRoot "dist/DawnwalkerConvai-$taskVersion-Source.zip"),[IO.Compression.ZipArchiveMode]::Update)
try{
 foreach($taskFile in Get-ChildItem $taskSource -Recurse -Force -File){
  $taskRelative=$taskFile.FullName.Substring($taskSource.Length+1).Replace('\','/')
  if(!$taskSourceArchive.GetEntry($taskRelative)){[IO.Compression.ZipFileExtensions]::CreateEntryFromFile($taskSourceArchive,$taskFile.FullName,$taskRelative)|Out-Null}
 }
}finally{$taskSourceArchive.Dispose()}
Get-ChildItem dist -Filter '*.zip' -File | Sort-Object Name | ForEach-Object {((Get-FileHash $_.FullName).Hash.ToLower()+'  '+$_.Name)} | Set-Content dist/SHA256SUMS.txt -Encoding ascii
Copy-Item -LiteralPath $taskNotes -Destination (Join-Path $taskRoot 'dist/RELEASE-NOTES.md')
