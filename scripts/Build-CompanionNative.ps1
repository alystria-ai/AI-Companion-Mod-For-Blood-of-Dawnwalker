param([string]$OutputName,[switch]$ReadOnlyAudit,[switch]$AssetLoader,[switch]$Protection,[switch]$Simulation)
$ErrorActionPreference='Stop'
$taskKindCount=@($ReadOnlyAudit,$AssetLoader,$Protection,$Simulation).Where({$_}).Count
if($taskKindCount -gt 1){throw 'Choose one helper kind'}
if(!$OutputName){$OutputName=if($Simulation){'companion_simulation_v1.dll'}elseif($Protection){'companion_protection_v2.dll'}elseif($AssetLoader){'companion_assets_v2.dll'}elseif($ReadOnlyAudit){'companion_audit.dll'}else{'companion_native_v9.dll'}}
if($ReadOnlyAudit -and $OutputName -eq 'companion_native_v9.dll'){throw 'The diagnostic DLL must not replace the population-owner DLL.'}
if($AssetLoader -and $OutputName -notmatch '^companion_assets_v[1-9][0-9]*\.dll$'){throw 'The asset loader must use its own versioned DLL name.'}
if($Protection -and $OutputName -notmatch '^companion_protection_v[1-9][0-9]*\.dll$'){throw 'The protection helper must use its own versioned DLL name.'}
if($Simulation -and $OutputName -notmatch '^companion_simulation_v[1-9][0-9]*\.dll$'){throw 'The simulation helper must use its own versioned DLL name.'}
$taskRoot=Split-Path $PSScriptRoot -Parent
$taskCompiler=Join-Path $taskRoot 'vendor/zig/zig-x86_64-windows-0.14.1/zig.exe'
if(!(Test-Path -LiteralPath $taskCompiler)){throw 'Portable Zig 0.14.1 is required in vendor/zig; see companion native source notes.'}
$taskOutput=Join-Path $taskRoot 'bridge/native'
New-Item -ItemType Directory -Force -Path $taskOutput | Out-Null
$taskSource=if($Simulation){'companion_simulation.c'}elseif($Protection){'companion_protection.c'}elseif($AssetLoader){'companion_asset_loader.c'}elseif($ReadOnlyAudit){'companion_audit.c'}else{'companion_native.c'}
& $taskCompiler cc -target x86_64-windows-gnu -shared -O2 -Wall -Wextra -Wno-cast-function-type-mismatch -o (Join-Path $taskOutput $OutputName) (Join-Path $taskRoot ('bridge/native-source/'+$taskSource)) -lkernel32
if($LASTEXITCODE -ne 0){throw 'Companion native bridge compilation failed'}
Get-FileHash -LiteralPath (Join-Path $taskOutput $OutputName) -Algorithm SHA256
