param([Int64]$NativeWindowHandle,[string]$ResponsePath)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class BraveLocalWin32 {
  [DllImport("user32.dll", SetLastError=true)]
  public static extern bool PrintWindow(IntPtr hwnd, IntPtr hdcBlt, uint nFlags);
}
'@
try {
  $root=[System.Windows.Automation.AutomationElement]::RootElement
  $wins=$root.FindAll([System.Windows.Automation.TreeScope]::Children,[System.Windows.Automation.Condition]::TrueCondition)
  $w=$null
  foreach($candidate in $wins){
    if([int64]$candidate.Current.NativeWindowHandle -eq $NativeWindowHandle){$w=$candidate;break}
  }
  if(-not $w){throw 'window_id_not_found'}
  $rect=$w.Current.BoundingRectangle; $hwnd=[IntPtr]$w.Current.NativeWindowHandle
  $width=[Math]::Max(1,[int][Math]::Round($rect.Width)); $height=[Math]::Max(1,[int][Math]::Round($rect.Height))
  $base=$env:BRAVE_LOCAL_DATA
  if(-not $base){$base=Split-Path $ResponsePath -Parent}
  $dir=Join-Path $base 'screenshots'; New-Item -ItemType Directory -Force $dir|Out-Null
  $path=Join-Path $dir (([guid]::NewGuid().ToString('N'))+'.png')
  $bmp=[System.Drawing.Bitmap]::new($width,$height)
  $g=[System.Drawing.Graphics]::FromImage($bmp)
  $hdc=$g.GetHdc()
  try { $ok=[BraveLocalWin32]::PrintWindow($hwnd,$hdc,2) }
  finally { $g.ReleaseHdc($hdc); $g.Dispose() }
  if(-not $ok){$bmp.Dispose();throw 'print_window_failed'}
  try{$bmp.Save($path,[System.Drawing.Imaging.ImageFormat]::Png)}
  finally{$bmp.Dispose()}
  $res=[ordered]@{
    ok=$true;path=$path;width=$width;height=$height;hwnd=$hwnd.ToInt64()
  }
} catch {
  $res=[ordered]@{ok=$false;error=$_.Exception.Message}
}
$res|ConvertTo-Json|Set-Content $ResponsePath -Encoding UTF8
