$ErrorActionPreference='Stop'
$taskStartLock=New-Object System.Threading.Mutex($false,'Local\DawnwalkerConvaiStart')
$taskLocked=$false
try {
    try {$taskLocked=$taskStartLock.WaitOne(0)} catch [System.Threading.AbandonedMutexException] {$taskLocked=$true}
    if(!$taskLocked){exit}
    $taskRoot=Split-Path $PSScriptRoot -Parent
    $taskRuntime=Join-Path $taskRoot 'runtime'
    $taskHost=[IO.Path]::GetFullPath((Join-Path $taskRoot 'bridge/native/ConvaiHost.exe'))
    $taskServerScript=[IO.Path]::GetFullPath((Join-Path $taskRoot 'bridge/server.mjs'))
    $taskNode=[IO.Path]::GetFullPath((Get-Content -LiteralPath (Join-Path $taskRuntime 'node-path.txt') -Raw).Trim())
    if(!(Test-Path -LiteralPath $taskHost)){throw 'Convai WebView2 host is missing'}
    $taskRestart=Join-Path $taskRuntime 'background-restart.request'
    $taskNext=Join-Path $taskRoot 'bridge/native/ConvaiHost.next.exe'
    $taskPidFile=Join-Path $taskRuntime 'background-host.pid'
    $taskHostProcess=$null
    if(Test-Path -LiteralPath $taskPidFile){
        $taskHostId=0
        if([int]::TryParse((Get-Content -LiteralPath $taskPidFile -Raw).Trim(),[ref]$taskHostId)){
            $taskHostProcess=Get-Process -Id $taskHostId -ErrorAction SilentlyContinue
            if($taskHostProcess -and $taskHostProcess.Path -ne $taskHost){
                # Windows can reuse the PID after a previous game session.
                # Discard the stale record; never stop its unrelated owner.
                if(!$taskHostProcess.Path -and $taskHostProcess.ProcessName -eq 'ConvaiHost'){
                    throw 'Cannot verify the recorded helper process from this account'
                }
                $taskHostProcess=$null
                Remove-Item -LiteralPath $taskPidFile -ErrorAction SilentlyContinue
            }
        }
    }
    $taskHeartbeat=0L
    try {[void][long]::TryParse((Get-Content -LiteralPath (Join-Path $taskRuntime 'background-heartbeat.txt') -Raw).Trim(),[ref]$taskHeartbeat)} catch {}
    $taskFresh=([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()-$taskHeartbeat -le 10)
    $taskRequested=(Test-Path -LiteralPath $taskRestart) -or (Test-Path -LiteralPath $taskNext)
    if($taskHostProcess -and $taskFresh -and !$taskRequested){exit}

    # A native host crash can leave an older Node child listening. Verify both
    # its executable and exact entry script; never kill an unrelated Node app.
    $taskListener=Get-NetTCPConnection -LocalPort 32123 -State Listen -ErrorAction SilentlyContinue
    $taskServerId=$null
    foreach($taskOwner in @($taskListener.OwningProcess | Select-Object -Unique)){
        if(!$taskOwner){continue}
        $taskServer=Get-CimInstance Win32_Process -Filter "ProcessId=$taskOwner"
        $taskEntryPattern='(?:^|\s)"?'+[regex]::Escape($taskServerScript)+'"?(?:\s|$)'
        if(!$taskServer -or $taskServer.ExecutablePath -ne $taskNode -or $taskServer.CommandLine -notmatch $taskEntryPattern){throw 'Port 32123 owner could not be verified as this mod server'}
        $taskServerId=$taskOwner
    }
    if($taskHostProcess){Stop-Process -Id $taskHostProcess.Id;if(!$taskHostProcess.WaitForExit(5000)){throw 'Previous helper did not exit'}}
    if($taskServerId){
        $taskOrphan=Get-Process -Id $taskServerId -ErrorAction SilentlyContinue
        if($taskOrphan){
            if($taskOrphan.Path -ne $taskNode){throw 'Bridge process changed during restart'}
            Stop-Process -Id $taskOrphan.Id
            if(!$taskOrphan.WaitForExit(5000)){throw 'Previous bridge did not exit'}
        }
    }
    if(Test-Path -LiteralPath $taskNext){Move-Item -LiteralPath $taskNext -Destination $taskHost -Force}
    Start-Process -FilePath $taskHost -WindowStyle Hidden -WorkingDirectory $taskRoot | Out-Null
    if(Test-Path -LiteralPath $taskRestart){Remove-Item -LiteralPath $taskRestart}
} finally {if($taskLocked){$taskStartLock.ReleaseMutex()};$taskStartLock.Dispose()}
