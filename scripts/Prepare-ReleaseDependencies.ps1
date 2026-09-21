$ErrorActionPreference='Stop'
$taskRoot=Split-Path $PSScriptRoot -Parent
Set-Location $taskRoot
function Get-VerifiedArchive($Url,$Destination,$Hash){
 Invoke-WebRequest -Uri $Url -OutFile $Destination
 if((Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash -ne $Hash){throw 'Dependency checksum mismatch'}
}
foreach($taskDir in @('runtime','vendor/zig','vendor/webview2/sdk','vendor/release-node','vendor/release-licenses/browser')){New-Item -ItemType Directory -Force $taskDir | Out-Null}
Get-VerifiedArchive 'https://ziglang.org/download/0.14.1/zig-x86_64-windows-0.14.1.zip' 'runtime/zig.zip' '554f5378228923ffd558eac35e21af020c73789d87afeabf4bfd16f2e6feed2c'
Expand-Archive runtime/zig.zip vendor/zig -Force
Get-VerifiedArchive 'https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/1.0.4191.47/microsoft.web.webview2.1.0.4191.47.nupkg' 'runtime/webview2.zip' 'F492BBF547D0DA329553B6727435B677579B1E9F91CC9E4A1AD029366D5F23D0'
Expand-Archive runtime/webview2.zip vendor/webview2/sdk -Force
Get-VerifiedArchive 'https://nodejs.org/dist/v24.19.0/node-v24.19.0-win-x64.zip' 'runtime/node.zip' '57f71ab3652e797d84acddc79c81cc9ff1c6ddb2a1974cdb83f00fee9bff4c73'
Expand-Archive runtime/node.zip vendor/release-node -Force
$taskNode=(Resolve-Path 'vendor/release-node/node-v24.19.0-win-x64/node.exe').Path
Set-Content runtime/node-path.txt $taskNode -Encoding utf8NoBOM
Copy-Item vendor/release-node/node-v24.19.0-win-x64/LICENSE vendor/release-licenses/NODE-LICENSE.txt
Copy-Item vendor/webview2/sdk/LICENSE.txt vendor/release-licenses/WEBVIEW2-LICENSE.txt
Copy-Item vendor/webview2/sdk/NOTICE.txt vendor/release-licenses/WEBVIEW2-NOTICE.txt
