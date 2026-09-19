param([string]$OutputName='ConvaiHost.exe',[string]$SharedConfig)
$ErrorActionPreference='Stop'
$taskRoot=Split-Path $PSScriptRoot -Parent
$taskSdk=Join-Path $taskRoot 'vendor\webview2\sdk'
$taskOutput=Join-Path $taskRoot 'bridge\native'
New-Item -ItemType Directory -Force -Path $taskOutput | Out-Null
foreach($taskName in @('Microsoft.Web.WebView2.Core.dll','Microsoft.Web.WebView2.WinForms.dll')){
    if(!(Test-Path -LiteralPath (Join-Path $taskOutput $taskName))){Copy-Item -LiteralPath (Join-Path $taskSdk ('lib\net462\'+$taskName)) -Destination $taskOutput}
}
if(!(Test-Path -LiteralPath (Join-Path $taskOutput 'WebView2Loader.dll'))){Copy-Item -LiteralPath (Join-Path $taskSdk 'runtimes\win-x64\native\WebView2Loader.dll') -Destination $taskOutput}
$taskCompiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$taskResourceArgs=@()
if($SharedConfig){$taskResourceArgs=@('/resource:'+([IO.Path]::GetFullPath($SharedConfig))+',DawnwalkerConvai.SharedDefaults.json')}
& $taskCompiler @taskResourceArgs /nologo /target:winexe /platform:x64 "/out:$taskOutput\$OutputName" /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Web.Extensions.dll "/reference:$taskOutput\Microsoft.Web.WebView2.Core.dll" "/reference:$taskOutput\Microsoft.Web.WebView2.WinForms.dll" (Join-Path $taskRoot 'bridge\WebViewHost.cs') (Join-Path $taskRoot 'bridge\DialogueOverlay.cs') (Join-Path $taskRoot 'bridge\ComposerKeys.cs') (Join-Path $taskRoot 'bridge\ModKeyBindings.cs') (Join-Path $taskRoot 'bridge\CompanionControls.cs') (Join-Path $taskRoot 'bridge\CompanionPanel.cs') (Join-Path $taskRoot 'bridge\CompanionLoading.cs') (Join-Path $taskRoot 'bridge\HostLifetime.cs') (Join-Path $taskRoot 'bridge\SupportReport.cs')
if($LASTEXITCODE -ne 0){throw 'WebView2 host compilation failed'}
