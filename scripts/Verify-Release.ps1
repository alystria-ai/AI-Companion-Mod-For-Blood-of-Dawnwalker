$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$taskRoot=Split-Path $PSScriptRoot -Parent
Set-Location $taskRoot
$taskVersion=(Get-Content package.json -Raw|ConvertFrom-Json).version
$taskMaps=@{}
foreach($taskPart in @('Complete','Scripts','Runtime','Source')){
 $taskZip=[IO.Compression.ZipFile]::OpenRead((Join-Path $taskRoot "dist/DawnwalkerConvai-$taskVersion-$taskPart.zip"))
 $taskMap=@{}
 try{
  foreach($taskEntry in $taskZip.Entries){
   if(!$taskEntry.Name){continue}
   $taskName=$taskEntry.FullName.Replace('\','/')
   if($taskName -match '(^/|(^|/)\.\.(/|$))'){throw 'Unsafe archive path'}
   $taskStream=$taskEntry.Open();$taskMemory=[IO.MemoryStream]::new()
   try{$taskStream.CopyTo($taskMemory);$taskBytes=$taskMemory.ToArray()}finally{$taskStream.Dispose();$taskMemory.Dispose()}
   $taskMap[$taskName]=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($taskBytes))
   if($taskPart -eq 'Scripts' -and !$taskName.EndsWith('.lua')){throw 'Scripts must contain Lua only'}
   if($taskPart -eq 'Runtime' -and $taskName.EndsWith('.lua')){throw 'Lua belongs in Scripts'}
   if($taskPart -eq 'Source' -and $taskName -match '(\.(exe|dll|zip|tgz)$|^(runtime|vendor|node_modules|backups|\.git)/)'){throw 'Unexpected file in source archive'}
   $taskText=[Text.Encoding]::UTF8.GetString($taskBytes)
   $taskHost=$taskName.EndsWith('/bridge/native/ConvaiHost.exe') -and $taskPart -in @('Complete','Runtime')
   if($env:CONVAI_API_KEY -and $taskText.Contains($env:CONVAI_API_KEY.Trim()) -and !$taskHost){throw 'Service credential outside player helper'}
   if($taskName.EndsWith('/runtime/convai-config.json')){
    $taskConfig=$taskText|ConvertFrom-Json
    if($taskConfig.apiKey -or $taskConfig.endUserId){throw 'Private identity in loose configuration'}
   }
   if($taskName.EndsWith('/bridge/public/client.js') -and $taskMap[$taskName] -ne (Get-FileHash bridge/public/client.js).Hash){throw 'Browser bundle mismatch'}
  }
  $taskManifest=$taskZip.GetEntry('SHA256SUMS.txt')
  if($taskManifest){
   $taskReader=[IO.StreamReader]::new($taskManifest.Open())
   try{$taskLines=$taskReader.ReadToEnd() -split '\r?\n'}finally{$taskReader.Dispose()}
   foreach($taskLine in $taskLines){
    if(!$taskLine.Trim()){continue}
    $taskPair=$taskLine -split '  ',2
    if($taskMap[$taskPair[1].Replace('\','/')] -ne $taskPair[0]){throw 'Internal manifest mismatch'}
   }
  }
  $taskMaps[$taskPart]=$taskMap
  Write-Output "$taskPart verified: $($taskMap.Count) files"
 }finally{$taskZip.Dispose()}
}
foreach($taskName in $taskMaps.Complete.Keys){
 if(!$taskName.StartsWith('Dawnwalker/')){continue}
 $taskPart=if($taskName.EndsWith('.lua')){'Scripts'}else{'Runtime'}
 if($taskMaps.Complete[$taskName] -ne $taskMaps[$taskPart][$taskName]){throw 'Split archives do not reconstruct Complete'}
}
if(!$taskMaps.Source.ContainsKey('.github/workflows/release.yml')){throw 'Source archive is missing the release workflow'}
foreach($taskLine in Get-Content dist/SHA256SUMS.txt){
 $taskPair=$taskLine -split '  ',2
 if((Get-FileHash (Join-Path 'dist' $taskPair[1])).Hash -ne $taskPair[0]){throw 'Archive checksum mismatch'}
}
Write-Output 'Package reconstruction, file manifests, source export and credential checks passed.'
