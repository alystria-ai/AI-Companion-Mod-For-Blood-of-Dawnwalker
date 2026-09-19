$ErrorActionPreference='Stop'
$taskRuntime=Join-Path (Split-Path $PSScriptRoot -Parent) 'runtime'
$taskBeat=Join-Path $taskRuntime 'background-heartbeat.txt'
$taskRunning=$false
if(Test-Path -LiteralPath $taskBeat){$taskRunning=([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()-[long](Get-Content -LiteralPath $taskBeat)) -lt 10}
if(!$taskRunning){& (Join-Path $PSScriptRoot 'Start-Background.ps1')}