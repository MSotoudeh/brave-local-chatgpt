$ErrorActionPreference='Stop'
$PluginRoot=$env:PLUGIN_ROOT
if(-not $PluginRoot){$PluginRoot=Split-Path -Parent $PSScriptRoot}
$DataRoot=$env:PLUGIN_DATA
if(-not $DataRoot){$DataRoot=Join-Path $env:LOCALAPPDATA 'BraveLocal'}
$env:BRAVE_LOCAL_DATA=$DataRoot
New-Item -ItemType Directory -Force $DataRoot,(Join-Path $DataRoot 'tmp')|Out-Null
$script:TraceEnabled=($env:BRAVE_MCP_TRACE -eq '1')
$TraceRoot=Join-Path $env:LOCALAPPDATA 'BraveLocalRecovery\20261015'
$TracePath=Join-Path $TraceRoot 'mcp-rpc-trace.log'
if($script:TraceEnabled){New-Item -ItemType Directory -Force $TraceRoot|Out-Null}
$script:TraceEmptyMethodCount=0
$script:TraceInvalidShapeCount=0
function Trace-Rpc($phase,$method,$id){
  if(-not $script:TraceEnabled){return}
  try{
    if($phase -eq 'received' -and [string]::IsNullOrEmpty([string]$method)){
      $script:TraceEmptyMethodCount++
      if($script:TraceEmptyMethodCount -notin @(1,10,100,1000)){return}
    }elseif($phase -eq 'handled' -and [string]::IsNullOrEmpty([string]$method)){return}
    $line='{0:o} pid={1} phase={2} method={3} id={4}{5}' -f (Get-Date),$PID,$phase,$method,$id,[Environment]::NewLine
    [IO.File]::AppendAllText($TracePath,$line,[Text.UTF8Encoding]::new($false))
  }catch{}
}
Trace-Rpc 'started' '' ''

function Rpc-Result($id,$result){
  [ordered]@{jsonrpc='2.0';id=$id;result=$result}|ConvertTo-Json -Depth 20 -Compress
}
function Rpc-Error($id,$code,$message){
  [ordered]@{jsonrpc='2.0';id=$id;error=[ordered]@{code=$code;message=$message}}|ConvertTo-Json -Depth 10 -Compress
}
function Obj-Schema($properties,$required=@()){
  $s=[ordered]@{type='object';properties=$properties;additionalProperties=$false}
  if($required.Count){$s.required=$required}
  return $s
}
function Window-Props(){
  [ordered]@{
    window=[ordered]@{type='integer';minimum=0}
    windowId=[ordered]@{type='integer'}
  }
}
function Merge-Props($extra){
  $p=Window-Props
  foreach($k in $extra.Keys){$p[$k]=$extra[$k]}
  return $p
}
function Tool($name,$description,$schema){
  [ordered]@{name=$name;description=$description;inputSchema=$schema}
}
function Str($description){
  [ordered]@{type='string';description=$description}
}
function Int($description){
  [ordered]@{type='integer';minimum=0;description=$description}
}

$Tools=@(
  (Tool 'list_tabs' 'List tabs across every currently open Brave window/profile.' (Obj-Schema @{})),
  (Tool 'activate_tab' 'Activate one Brave tab.' (Obj-Schema (Merge-Props @{
    tab=(Int 'Tab index returned by list_tabs')
  }) @('tab'))),
  (Tool 'open_url' 'Open a URL in the selected or specified Brave window.' (Obj-Schema (Merge-Props @{
    url=(Str 'Absolute URL')
  }) @('url'))),
  (Tool 'snapshot' 'Read semantic page elements from the selected tab.' (Obj-Schema (Window-Props))),
  (Tool 'get_text' 'Read visible semantic text from the selected tab.' (Obj-Schema (Window-Props)))
)
$Tools += @(
  (Tool 'click' 'Click a unique semantic element by accessible name and optional role.' (Obj-Schema (Merge-Props @{
    name=(Str 'Accessible name'); role=(Str 'Optional UI Automation role')
  }) @('name'))),
  (Tool 'type_text' 'Set text in a unique editable field by accessible name.' (Obj-Schema (Merge-Props @{
    name=(Str 'Accessible name'); text=(Str 'Text to enter')
  }) @('name','text'))),
  (Tool 'press_key' 'Invoke a supported key action on a semantic target.' (Obj-Schema (Merge-Props @{
    key=(Str 'Currently Enter'); name=(Str 'Optional target name'); role=(Str 'Optional target role')
  }) @('key'))),
  (Tool 'scroll' 'Scroll the selected page.' (Obj-Schema (Merge-Props @{
    direction=[ordered]@{type='string';enum=@('up','down')}
    pages=(Int 'Number of page-sized scroll steps')
  }))),
  (Tool 'wait_for' 'Wait until a unique semantic element appears.' (Obj-Schema (Merge-Props @{
    name=(Str 'Accessible name'); role=(Str 'Optional role'); timeoutMs=(Int 'Timeout in milliseconds, maximum 15000')
  }) @('name'))),
  (Tool 'screenshot' 'Capture the selected Brave window.' (Obj-Schema (Window-Props)))
)

$ToolMap=@{
  list_tabs='tabs.list'; activate_tab='tabs.activate'; open_url='page.open'
  snapshot='page.snapshot'; get_text='page.text'; click='element.click'
  type_text='element.type'; press_key='keyboard.press'; scroll='page.scroll'
  wait_for='page.wait'; screenshot='page.screenshot'
}
function Tool-Error($code,$message){
  [ordered]@{
    content=@([ordered]@{type='text';text=($code + ': ' + $message)})
    structuredContent=[ordered]@{error=[ordered]@{code=$code;message=$message}}
    isError=$true
  }
}
function Tool-Result($value){
  $text=$value|ConvertTo-Json -Depth 20 -Compress
  [ordered]@{
    content=@([ordered]@{type='text';text=$text})
    structuredContent=[ordered]@{result=$value}
    isError=$false
  }
}
function Copy-Arguments($argsObject){
  $h=[ordered]@{}
  if($null -eq $argsObject){return $h}
  foreach($prop in $argsObject.PSObject.Properties){$h[$prop.Name]=$prop.Value}
  return $h
}

function Call-Bridge($toolName,$argsObject){
  $command=$ToolMap[$toolName]
  if(-not $command){return Tool-Error 'unknown_tool' ('Unknown tool: ' + $toolName)}
  $params=Copy-Arguments $argsObject
  if($toolName -eq 'type_text' -and $params.Contains('text')){
    $params['value']=$params['text']; $params.Remove('text')
  }
  $id=[guid]::NewGuid().ToString('N')
  $tmp=Join-Path $DataRoot 'tmp'
  $reqPath=Join-Path $tmp ($id + '.req.json')
  $resPath=Join-Path $tmp ($id + '.res.json')
  $proc=$null
  $stdoutRead=$null
  $stderrRead=$null
  $worker=Join-Path $PluginRoot 'scripts\uia-command.ps1'
  if(-not (Test-Path $worker)){return Tool-Error 'worker_missing' 'UI Automation worker is missing.'}
  try {
    [ordered]@{id=$id;command=$command;params=$params} |
      ConvertTo-Json -Depth 12 -Compress |
      Set-Content -Path $reqPath -Encoding UTF8
    $hostExe=Join-Path $PSHOME $(if($PSVersionTable.PSEdition -eq 'Core'){'pwsh.exe'}else{'powershell.exe'})
    $startInfo=New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName=$hostExe
    $startInfo.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -RequestPath "{1}" -ResponsePath "{2}"' -f $worker,$reqPath,$resPath
    $startInfo.UseShellExecute=$false
    $startInfo.CreateNoWindow=$true
    $startInfo.RedirectStandardOutput=$true
    $startInfo.RedirectStandardError=$true
    $proc=[System.Diagnostics.Process]::Start($startInfo)
    Trace-Rpc 'worker-started' $command $id
    $stdoutRead=$proc.StandardOutput.ReadToEndAsync()
    $stderrRead=$proc.StandardError.ReadToEndAsync()
    if(-not $proc.WaitForExit(20000)){
      $proc.Refresh()
      if(-not $proc.HasExited){
        try{$proc.Kill();$proc.WaitForExit()}catch{}
        Trace-Rpc 'worker-timeout' $command $id
        return Tool-Error 'worker_timeout' 'UI Automation worker exceeded its 20 second limit and was stopped.'
      }
    }
    $proc.WaitForExit()
    $null=$stdoutRead.GetAwaiter().GetResult()
    $null=$stderrRead.GetAwaiter().GetResult()
    Trace-Rpc 'worker-finished' $command $id
    if(-not (Test-Path $resPath)){return Tool-Error 'bridge_error' 'UI Automation worker produced no response.'}
    $resp=Get-Content $resPath -Raw | ConvertFrom-Json
    if(-not $resp.ok){
      $code='bridge_error'; $message='Bridge operation failed.'
      if($resp.error){$code=[string]$resp.error.code; $message=[string]$resp.error.message}
      return Tool-Error $code $message
    }
    return Tool-Result $resp.result
  } catch {
    return Tool-Error 'bridge_error' $_.Exception.Message
  } finally {
    if($proc){
      try{if(-not $proc.HasExited){$proc.Kill();$proc.WaitForExit(2000)}}catch{}
      $proc.Dispose()
    }
    Remove-Item $reqPath,$resPath -Force -ErrorAction SilentlyContinue
  }
}
function Handle-Request($req){
  $id=$req.id
  switch([string]$req.method){
    'initialize' {
      $version='2025-06-18'
      if($req.params -and $req.params.protocolVersion){$version=[string]$req.params.protocolVersion}
      return Rpc-Result $id ([ordered]@{
        protocolVersion=$version
        capabilities=[ordered]@{tools=[ordered]@{listChanged=$false}}
        serverInfo=[ordered]@{name='brave-local';version='0.2.1'}
      })
    }
    'tools/list' {
      return Rpc-Result $id ([ordered]@{tools=$Tools})
    }
    'tools/call' {
      if(-not $req.params -or -not $req.params.name){
        return Rpc-Error $id -32602 'Missing tool name.'
      }
      $result=Call-Bridge ([string]$req.params.name) $req.params.arguments
      return Rpc-Result $id $result
    }
    'ping' {
      return Rpc-Result $id ([ordered]@{})
    }
    'notifications/initialized' {
      return $null
    }
    default {
      return Rpc-Error $id -32601 'Method not found.'
    }
  }
}
while($true){
  $line=[Console]::In.ReadLine()
  if($null -eq $line){break}
  if([string]::IsNullOrWhiteSpace($line)){continue}
  try {
    $req=$line | ConvertFrom-Json
  } catch {
    [Console]::Out.WriteLine((Rpc-Error $null -32700 'Parse error.'))
    [Console]::Out.Flush()
    continue
  }
  # Responses and miscellaneous non-request frames have no method. If fed
  # back into stdin by a broken host pipe, answering them creates an error
  # feedback loop. Never emit another frame for such input.
  $methodProperty=if($null -ne $req){$req.PSObject.Properties['method']}else{$null}
  $methodValue=if($null -ne $methodProperty){[string]$methodProperty.Value}else{''}
  if([string]::IsNullOrWhiteSpace($methodValue)){
    $script:TraceInvalidShapeCount++
    if($script:TraceInvalidShapeCount -in @(1,10,100,1000)){
      Trace-Rpc 'ignored-nonrequest' '' ''
    }
    continue
  }
  # All JSON-RPC notifications must be one-way.
  if($methodValue.StartsWith('notifications/',[StringComparison]::Ordinal)){
    continue
  }
  try {
    if($null -eq $req -or [string]::IsNullOrEmpty([string]$req.method)){
      if($script:TraceInvalidShapeCount -lt 3){
        $script:TraceInvalidShapeCount++
        $keys='null'
        if($null -ne $req){$keys=(@($req.PSObject.Properties | ForEach-Object {$_.Name}) -join ',')}
        Trace-Rpc 'invalid-shape' ('length='+$line.Length+' keys='+$keys) ([string]$req.id)
      }
    }
    Trace-Rpc 'received' ([string]$req.method) ([string]$req.id)
    $out=Handle-Request $req
    Trace-Rpc 'handled' ([string]$req.method) ([string]$req.id)
  } catch {
    $out=Rpc-Error $req.id -32603 $_.Exception.Message
  }
  if($null -ne $out){
    Trace-Rpc 'response-ready' ([string]$req.method) ('id='+[string]$req.id+' chars='+$out.Length)
    [Console]::Out.WriteLine($out)
    [Console]::Out.Flush()
    Trace-Rpc 'response-flushed' ([string]$req.method) ([string]$req.id)
  }
}
