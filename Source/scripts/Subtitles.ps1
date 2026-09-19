$ErrorActionPreference='Stop'
$mutex=New-Object Threading.Mutex($false,'Local\DawnwalkerConvaiSubtitles')
if(!$mutex.WaitOne(0)){exit}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Windows.Forms,System.Drawing -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;
public class ConvaiOverlay : Form {
    [StructLayout(LayoutKind.Sequential)] public struct Rect {public int Left,Top,Right,Bottom;}
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out Rect r);
    protected override bool ShowWithoutActivation {get{return true;}}
    protected override CreateParams CreateParams {get{var p=base.CreateParams;p.ExStyle|=0x08000000|0x20|0x80000;return p;}}
}
'@
$runtime=Join-Path (Split-Path $PSScriptRoot -Parent) 'runtime'
$form=New-Object ConvaiOverlay
$form.FormBorderStyle='None';$form.ShowInTaskbar=$false;$form.TopMost=$true
$form.BackColor=[Drawing.Color]::Black;$form.Opacity=0.87
$label=New-Object Windows.Forms.Label
$label.Dock='Fill';$label.ForeColor=[Drawing.Color]::White;$label.TextAlign='MiddleCenter';$label.Padding=New-Object Windows.Forms.Padding(20)
$label.Font=New-Object Drawing.Font('Segoe UI',18)
$form.Controls.Add($label)
$timer=New-Object Windows.Forms.Timer;$timer.Interval=100
$timer.Add_Tick({
    try{
        $window=[ConvaiOverlay]::GetForegroundWindow();[uint32]$processId=0
        [ConvaiOverlay]::GetWindowThreadProcessId($window,[ref]$processId) | Out-Null
        $process=Get-Process -Id $processId -ErrorAction SilentlyContinue
        if(!$process -or $process.ProcessName -ne 'Dawnwalker'){$form.Hide();return}
        $data=Get-Content -LiteralPath (Join-Path $runtime 'overlay.json') -Raw -ErrorAction Stop | ConvertFrom-Json
        $now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        if(($now-$data.updated) -gt 4000){$form.Hide();return}
        $label.Text=if($data.text){$data.text}else{$data.status}
        if(!$label.Text){$form.Hide();return}
        $bounds=New-Object ConvaiOverlay+Rect
        [ConvaiOverlay]::GetWindowRect($window,[ref]$bounds) | Out-Null
        $width=[Math]::Min(1100,[Math]::Max(400,$bounds.Right-$bounds.Left-100))
        $form.SetBounds($bounds.Left+[int](($bounds.Right-$bounds.Left-$width)/2),$bounds.Bottom-220,$width,150)
        if(!$form.Visible){$form.Show()}
    }catch{$form.Hide()}
})
$timer.Start()
try{[Windows.Forms.Application]::Run()}finally{$timer.Dispose();$form.Dispose();$mutex.ReleaseMutex();$mutex.Dispose()}
