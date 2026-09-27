# Validate both source dependencies and, when supplied, the actual installed layout.
param([string]$ScriptsDirectory,[string]$BootstrapDirectory)
$ErrorActionPreference='Stop'
$taskRoot=Split-Path $PSScriptRoot -Parent
$taskSource=if($ScriptsDirectory){$ScriptsDirectory}else{Join-Path $taskRoot 'mod/Scripts'}
$taskLoader=Get-Content -LiteralPath (Join-Path $taskSource 'live_reload.lua') -Raw
$taskList=[regex]::Match($taskLoader,'M\.modules\s*=\s*\{([^}]+)\}').Groups[1].Value
if (!$taskList) {throw 'Lua loader module manifest was not found'}
$taskNames=@([regex]::Matches($taskList,"'([^']+)'") | ForEach-Object {$_.Groups[1].Value})
if (($taskNames | Select-Object -Unique).Count -ne $taskNames.Count) {throw 'Duplicate Lua module in loader manifest'}
foreach ($taskName in $taskNames) {
 $taskPath=Join-Path $taskSource ($taskName+'.lua')
 if (!(Test-Path -LiteralPath $taskPath)) {throw "Missing loader module: $taskName"}
 $taskCode=Get-Content -LiteralPath $taskPath -Raw
 foreach ($taskRequire in [regex]::Matches($taskCode,'\brequire\s*\(?\s*[''"]([A-Za-z0-9_]+)[''"]')) {
  $taskDependency=$taskRequire.Groups[1].Value
  if ((Test-Path -LiteralPath (Join-Path $taskSource ($taskDependency+'.lua'))) -and $taskDependency -notin $taskNames -and $taskDependency -ne 'live_reload') {
   throw "Lua module '$taskName' needs '$taskDependency', which is missing from the loader manifest"
  }
 }
}
if($BootstrapDirectory){
 foreach($taskName in @('main.lua','live_reload.lua')){
  $taskBootstrap=Join-Path $BootstrapDirectory $taskName
  $taskPayload=Join-Path $taskSource $taskName
  if(!(Test-Path -LiteralPath $taskBootstrap) -or (Get-FileHash -LiteralPath $taskBootstrap).Hash -ne (Get-FileHash -LiteralPath $taskPayload).Hash){
   throw "Startup/payload mismatch: $taskName. Synchronize the complete Lua update before testing a new launch."
  }
 }
}
Write-Output "Lua loader dependencies verified ($($taskNames.Count) modules)."
