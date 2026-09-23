$ErrorActionPreference='Stop'
$taskRoot=Split-Path $PSScriptRoot -Parent
$taskCompiler=Join-Path $taskRoot 'vendor/zig/zig-x86_64-windows-0.14.1/zig.exe'
if(!(Test-Path -LiteralPath $taskCompiler)){throw 'Portable Zig 0.14.1 is required in vendor/zig'}
$taskOutput=Join-Path $taskRoot 'bridge/native/background_launcher_v1.dll'
& $taskCompiler cc -target x86_64-windows-gnu -shared -O2 -Wall -Wextra -o $taskOutput (Join-Path $taskRoot 'bridge/native-source/background_launcher.c') -lkernel32
if($LASTEXITCODE -ne 0){throw 'Background launcher compilation failed'}
Get-FileHash -LiteralPath $taskOutput -Algorithm SHA256
