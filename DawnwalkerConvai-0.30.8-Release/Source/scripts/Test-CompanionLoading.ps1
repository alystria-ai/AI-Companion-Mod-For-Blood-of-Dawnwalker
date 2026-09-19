param([string]$HostName='ConvaiHost.next.exe')
$ErrorActionPreference='Stop'
$taskRoot=Split-Path $PSScriptRoot -Parent
$taskAssembly=Join-Path $taskRoot ('bridge\native\'+$HostName)
$taskTest=Join-Path $taskRoot 'bridge\native\CompanionLoadingTests.exe'
$taskCompiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
& $taskCompiler /nologo /target:exe /platform:x64 "/out:$taskTest" "/reference:$taskAssembly" (Join-Path $taskRoot 'tests\CompanionLoadingTests.cs')
if($LASTEXITCODE -ne 0){throw 'Loading test compilation failed'}
& $taskTest
if($LASTEXITCODE -ne 0){throw 'Loading lifecycle check failed'}
