param(
  [Parameter(Mandatory=$true)][string]$RequestPath,
  [Parameter(Mandatory=$true)][string]$ResponsePath
)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName System.Drawing

function Find-BraveWindows {
  $root=[System.Windows.Automation.AutomationElement]::RootElement
  $wins=$root.FindAll([System.Windows.Automation.TreeScope]::Children,[System.Windows.Automation.Condition]::TrueCondition)
  $out=@()
  foreach($w in $wins){
    if($w.Current.ClassName -eq 'Chrome_WidgetWin_1' -and $w.Current.Name -match 'Brave' -and $w.Current.Name -notmatch '^Extensions'){ $out += $w }
  }
  return $out
}
function TypeName($e){ return $e.Current.ControlType.ProgrammaticName -replace '^ControlType\.','' }
function Ok($id,$value){ return [ordered]@{id=$id;ok=$true;result=$value} }
function Fail($id,$code,$message){ return [ordered]@{id=$id;ok=$false;error=[ordered]@{code=$code;message=$message}} }
function FocusedBraveIndex($wins){
  try {
    $e=[System.Windows.Automation.AutomationElement]::FocusedElement
    $walker=[System.Windows.Automation.TreeWalker]::RawViewWalker
    while($e){
      $parent=$walker.GetParent($e)
      if(-not $parent -or $parent -eq [System.Windows.Automation.AutomationElement]::RootElement){ break }
      $e=$parent
    }
    if($e){
      $hwnd=$e.Current.NativeWindowHandle
      for($i=0;$i -lt $wins.Count;$i++){
        if($wins[$i].Current.NativeWindowHandle -eq $hwnd){ return $i }
      }
    }
  } catch {}
  return -1
}
function WindowAt($wins,$params){
  if($null -ne $params.windowId){
    for($i=0;$i -lt $wins.Count;$i++){
      if([int64]$wins[$i].Current.NativeWindowHandle -eq [int64]$params.windowId){ return $wins[$i] }
    }
    throw 'window_id_not_found'
  }
  if($null -ne $params.window){
    $wi=[int]$params.window
    if($wi -lt 0 -or $wi -ge $wins.Count){ throw 'window_index_out_of_range' }
    return $wins[$wi]
  }
  if($wins.Count -eq 1){ return $wins[0] }
  $fi=FocusedBraveIndex $wins
  if($fi -ge 0){ return $wins[$fi] }
  throw 'ambiguous_window'
}
function RootDoc($w){
  $cond=[System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::AutomationIdProperty,'RootWebArea')
  $doc=$w.FindFirst([System.Windows.Automation.TreeScope]::Descendants,$cond)
  if(-not $doc){ throw 'root_web_area_not_found' }
  return $doc
}
function FindNamed($doc,$name,$role){
  $cond=[System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::NameProperty,$name)
  $els=$doc.FindAll([System.Windows.Automation.TreeScope]::Descendants,$cond)
  $m=@()
  for($i=0;$i -lt $els.Count;$i++){
    $e=$els.Item($i); if(-not $role -or (TypeName $e) -eq $role){ $m += $e }
  }
  return $m
}
function RequireOne($items){
  if($items.Count -eq 0){ throw 'no_matches' }
  if($items.Count -gt 1){ throw "ambiguous_target:$($items.Count)" }
  return $items[0]
}
function Snapshot($w){
  $doc=RootDoc $w
  $nodes=@()
  $all=$doc.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
  for($i=0;$i -lt $all.Count -and $nodes.Count -lt 500;$i++){
    $e=$all.Item($i); $name=$e.Current.Name; $role=TypeName $e
    if($name -or $role -match 'Button|Hyperlink|Edit|Text|Heading|CheckBox|RadioButton|ComboBox'){
      $nodes += [ordered]@{index=$i;role=$role;name=$name;automationId=$e.Current.AutomationId;class=$e.Current.ClassName;offscreen=$e.Current.IsOffscreen}
    }
  }
  return [ordered]@{windowTitle=$w.Current.Name;documentName=$doc.Current.Name;nodes=$nodes}
}
function Navigate($w,$url){
  $bar=$w.FindFirst([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::NameProperty,'Address and search bar'))
  if(-not $bar){ $bar=$w.FindFirst([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::AutomationIdProperty,'view_1012')) }
  if(-not $bar){ throw 'address_bar_not_found' }
  $bar.SetFocus(); $bar.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue($url)
  $root=[System.Windows.Automation.AutomationElement]::RootElement; $match=$null; $deadline=(Get-Date).AddSeconds(4)
  do {
    Start-Sleep -Milliseconds 150
    $items=$root.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::ListItem))
    $m=@(); for($i=0;$i -lt $items.Count;$i++){ $e=$items.Item($i); $n=$e.Current.Name; if($e.Current.ClassName -eq 'BraveOmniboxResultView' -and $n.StartsWith($url) -and $n -ne "$url search"){$m += $e} }
    if($m.Count -eq 1){$match=$m[0]}
  } while(-not $match -and (Get-Date) -lt $deadline)
  if(-not $match){ throw 'omnibox_result_not_found' }
  $match.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); Start-Sleep -Milliseconds 500
}
try {
  $req=Get-Content $RequestPath -Raw | ConvertFrom-Json
  $wins=Find-BraveWindows
  if(-not $wins){ throw 'no_brave_window' }
  switch($req.command){
    'tabs.list' {
      $items=@(); $wi=0
      foreach($w in $wins){
        $cond=[System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::TabItem)
        $tabs=$w.FindAll([System.Windows.Automation.TreeScope]::Descendants,$cond)
        for($i=0;$i -lt $tabs.Count;$i++){
          $t=$tabs.Item($i); $selected=$false
          try{$selected=$t.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Current.IsSelected}catch{}
          $items += [ordered]@{window=$wi;windowId=[int64]$w.Current.NativeWindowHandle;windowTitle=$w.Current.Name;tab=$i;title=$t.Current.Name;selected=$selected;automationId=$t.Current.AutomationId}
        }
        $wi++
      }
      $res=Ok $req.id $items
    }
    'tabs.activate' {
      $w=WindowAt $wins $req.params; $ti=[int]$req.params.tab
      $cond=[System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::TabItem)
      $tabs=$w.FindAll([System.Windows.Automation.TreeScope]::Descendants,$cond)
      if($ti -lt 0 -or $ti -ge $tabs.Count){ throw 'tab_index_out_of_range' }
      $t=$tabs.Item($ti); $t.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
      $res=Ok $req.id ([ordered]@{tab=$ti;title=$t.Current.Name})
    }
    'page.open' {
      $w=WindowAt $wins $req.params; Navigate $w ([string]$req.params.url)
      $res=Ok $req.id ([ordered]@{title=$w.Current.Name;url=[string]$req.params.url})
    }
    'page.snapshot' {
      $w=WindowAt $wins $req.params; $res=Ok $req.id (Snapshot $w)
    }
    'page.text' {
      $w=WindowAt $wins $req.params; $snap=Snapshot $w
      $parts=@($snap.nodes | Where-Object {$_.role -eq 'Text' -and $_.name} | ForEach-Object {$_.name})
      $res=Ok $req.id ([ordered]@{documentName=$snap.documentName;text=($parts -join "`n")})
    }
    'element.click' {
      $w=WindowAt $wins $req.params; $doc=RootDoc $w
      $one=RequireOne (FindNamed $doc ([string]$req.params.name) ([string]$req.params.role))
      $one.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); Start-Sleep -Milliseconds 250
      $res=Ok $req.id ([ordered]@{clicked=$true;name=[string]$req.params.name})
    }
    'element.type' {
      $w=WindowAt $wins $req.params; $doc=RootDoc $w
      $one=RequireOne (FindNamed $doc ([string]$req.params.name) 'Edit')
      $one.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue([string]$req.params.value)
      Start-Sleep -Milliseconds 100; $res=Ok $req.id ([ordered]@{typed=$true;name=[string]$req.params.name})
    }
    'keyboard.press' {
      $key=[string]$req.params.key
      if($key -ne 'Enter'){ throw "unsupported_key:$key" }
      $w=WindowAt $wins $req.params; $doc=RootDoc $w
      $name=[string]$req.params.name; if(-not $name){$name='Submit'}
      $role=[string]$req.params.role; if(-not $role){$role='Button'}
      $one=RequireOne (FindNamed $doc $name $role)
      $one.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); Start-Sleep -Milliseconds 250
      $res=Ok $req.id ([ordered]@{pressed='Enter';invoked=$name})
    }
    'page.scroll' {
      $w=WindowAt $wins $req.params; $doc=RootDoc $w
      $sp=$doc.GetCurrentPattern([System.Windows.Automation.ScrollPattern]::Pattern)
      $direction=[string]$req.params.direction; if(-not $direction){$direction='down'}
      $pages=1; if($null -ne $req.params.pages){$pages=[Math]::Max(1,[int]$req.params.pages)}
      $before=$sp.Current.VerticalScrollPercent
      for($i=0;$i -lt $pages;$i++){
        $v=[System.Windows.Automation.ScrollAmount]::LargeIncrement
        if($direction -eq 'up'){$v=[System.Windows.Automation.ScrollAmount]::LargeDecrement}
        $sp.Scroll([System.Windows.Automation.ScrollAmount]::NoAmount,$v)
      }
      Start-Sleep -Milliseconds 150; $res=Ok $req.id ([ordered]@{before=$before;after=$sp.Current.VerticalScrollPercent;direction=$direction;pages=$pages})
    }
    'page.wait' {
      $w=WindowAt $wins $req.params; $name=[string]$req.params.name; $role=[string]$req.params.role
      $timeout=5000; if($null -ne $req.params.timeoutMs){$timeout=[Math]::Min(15000,[Math]::Max(0,[int]$req.params.timeoutMs))}
      $deadline=(Get-Date).AddMilliseconds($timeout); $found=$null
      do {
        $doc=RootDoc $w; $m=FindNamed $doc $name $role
        if($m.Count -eq 1){$found=$m[0];break}; if($m.Count -gt 1){throw "ambiguous_target:$($m.Count)"}
        Start-Sleep -Milliseconds 100
      } while((Get-Date) -lt $deadline)
      if(-not $found){throw 'wait_timeout'}
      $res=Ok $req.id ([ordered]@{found=$true;name=$name;role=(TypeName $found)})
    }
    'page.screenshot' {
      $w=WindowAt $wins $req.params
      $helper=Join-Path $PSScriptRoot 'uia-printwindow.ps1'
      $tmp=Join-Path (Split-Path $ResponsePath -Parent) (([guid]::NewGuid().ToString('N'))+'.shot.json')
      & $helper -NativeWindowHandle ([int64]$w.Current.NativeWindowHandle) -ResponsePath $tmp
      $shot=Get-Content $tmp -Raw|ConvertFrom-Json
      Remove-Item $tmp -Force -ErrorAction SilentlyContinue
      if(-not $shot.ok){throw $shot.error}
      $res=Ok $req.id ([ordered]@{path=$shot.path;width=$shot.width;height=$shot.height})
    }
    default { $res=Fail $req.id 'unknown_command' 'Unsupported UIA command' }
  }
} catch {
  $id=$null; try{$id=$req.id}catch{}
  $msg=$_.Exception.Message; $code='uia_error'
  if($msg -like 'ambiguous_target:*'){$code='ambiguous_target'}
  elseif($msg -eq 'ambiguous_window'){$code='ambiguous_window'}
  elseif($msg -eq 'no_matches'){$code='no_matches'}
  elseif($msg -like '*_index_out_of_range' -or $msg -eq 'window_id_not_found'){$code='stale_target'}
  elseif($msg -eq 'wait_timeout'){$code='wait_timeout'}
  elseif($msg -like 'unsupported_key:*'){$code='unsupported_key'}
  $res=Fail $id $code $msg
}
$res | ConvertTo-Json -Depth 9 | Set-Content $ResponsePath -Encoding UTF8
