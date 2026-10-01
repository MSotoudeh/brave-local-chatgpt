$ErrorActionPreference='Stop'
$PluginRoot=$env:PLUGIN_ROOT
if(-not $PluginRoot){$PluginRoot=Split-Path -Parent $PSScriptRoot}
$DataRoot=$env:PLUGIN_DATA
if(-not $DataRoot){$DataRoot=Join-Path $env:LOCALAPPDATA 'BraveLocal'}
$env:BRAVE_LOCAL_DATA=$DataRoot
New-Item -ItemType Directory -Force $DataRoot,(Join-Path $DataRoot 'tmp')|Out-Null

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
  $worker=Join-Path $PluginRoot 'scripts\uia-command.ps1'
  if(-not (Test-Path $worker)){return Tool-Error 'worker_missing' 'UI Automation worker is missing.'}
  try {
    [ordered]@{id=$id;command=$command;params=$params} |
      ConvertTo-Json -Depth 12 -Compress |
      Set-Content -Path $reqPath -Encoding UTF8
    & $worker -RequestPath $reqPath -ResponsePath $resPath
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
  if($null -eq $req.id -and [string]$req.method -ne 'initialize'){
    if([string]$req.method -eq 'notifications/initialized'){continue}
  }
  try {
    $out=Handle-Request $req
  } catch {
    $out=Rpc-Error $req.id -32603 $_.Exception.Message
  }
  if($null -ne $out){
    [Console]::Out.WriteLine($out)
    [Console]::Out.Flush()
  }
}
