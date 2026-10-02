$ErrorActionPreference='Stop'
$RepoRoot=Split-Path -Parent $PSScriptRoot
$PluginRoot=Join-Path $RepoRoot 'plugins\brave-local'
$Zip=Join-Path $RepoRoot 'dist\brave-local-0.2.1-windows.zip'

$plugin=Get-Content (Join-Path $PluginRoot 'plugin.json') -Raw | ConvertFrom-Json
$mcp=Get-Content (Join-Path $PluginRoot 'mcp.json') -Raw | ConvertFrom-Json
if($plugin.name -ne 'brave-local'){throw 'bad plugin name'}
if($plugin.version -ne '0.2.1'){throw 'bad plugin version'}
if($mcp.mcpServers.'brave-local'.type -ne 'stdio'){throw 'MCP is not stdio'}
if($mcp.mcpServers.'brave-local'.command -ne 'powershell.exe'){throw 'bad MCP command'}
$args=@($mcp.mcpServers.'brave-local'.args)
if($args -notcontains '-File'){throw 'MCP missing -File'}
if(-not ($args -match 'brave-local-mcp\.ps1')){throw 'MCP script argument missing'}

$required=@(
  'plugin.json',
  'mcp.json',
  'skills/brave-control/SKILL.md',
  'scripts/brave-local-mcp.ps1',
  'scripts/uia-command.ps1',
  'scripts/uia-printwindow.ps1'
)
foreach($rel in $required){
  $native=$rel.Replace('/','\')
  if(-not (Test-Path (Join-Path $PluginRoot $native))){throw "missing $rel"}
}
$forbidden=@('mmsot','OPS\','C:\Users\','BraveChatGPTBridge')
$textFiles=Get-ChildItem $PluginRoot -Recurse -File | Where-Object {$_.Extension -in @('.json','.md','.ps1')}
foreach($f in $textFiles){
  $text=Get-Content $f.FullName -Raw
  foreach($token in $forbidden){
    if($text.IndexOf($token,[StringComparison]::OrdinalIgnoreCase) -ge 0){throw "$($f.FullName) contains $token"}
  }
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$z=[IO.Compression.ZipFile]::OpenRead($Zip)
try {
  $names=@($z.Entries | ForEach-Object {$_.FullName})
  foreach($name in $names){if($name.Contains('\')){throw "unsafe ZIP path: $name"}}
  foreach($rel in $required){if($names -notcontains $rel){throw "ZIP missing $rel"}}
  if($names | Where-Object {$_.EndsWith('.exe',[StringComparison]::OrdinalIgnoreCase)}){throw 'ZIP unexpectedly contains executable'}
} finally {$z.Dispose()}

foreach($script in @('brave-local-mcp.ps1','uia-command.ps1','uia-printwindow.ps1')){
  $parseErrors=$null
  [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PluginRoot "scripts\$script"),[ref]$null,[ref]$parseErrors)|Out-Null
  if($parseErrors.Count){throw "$script parse error: $($parseErrors[0])"}
}
'PACKAGE_VERIFY_PASS'
