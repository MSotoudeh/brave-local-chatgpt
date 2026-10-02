$ErrorActionPreference='Stop'
$RepoRoot=Split-Path -Parent $PSScriptRoot
$PluginRoot=Join-Path $RepoRoot 'plugins\brave-local'
$Server=Join-Path $PluginRoot 'scripts\brave-local-mcp.ps1'
$env:PLUGIN_ROOT=$PluginRoot
$env:PLUGIN_DATA=Join-Path $env:TEMP 'BraveLocalProtocolTest'

$msg=@(
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}',
  '{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}',
  '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
)
$payload=[string]::Join([Environment]::NewLine,$msg)+[Environment]::NewLine
$raw=@($payload | powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Server)
$lines=@($raw | Where-Object {$_})
if($lines.Count -ne 2){throw "Expected 2 MCP responses, got $($lines.Count)"}
$init=$lines[0]|ConvertFrom-Json
$tools=$lines[1]|ConvertFrom-Json
if($init.result.serverInfo.name -ne 'brave-local'){throw 'Bad server name'}
if($init.result.serverInfo.version -ne '0.2.1'){throw 'Bad server version'}
if(@($tools.result.tools).Count -ne 11){throw "Expected 11 tools"}
'MCP_PROTOCOL_PASS'
