$ErrorActionPreference='Stop'
$RepoRoot=Split-Path -Parent $PSScriptRoot
$PluginRoot=Join-Path $RepoRoot 'plugins\brave-local'
$Zip=Join-Path $RepoRoot 'dist\brave-local-0.2.0-windows.zip'

$plugin=Get-Content (Join-Path $PluginRoot 'plugin.json') -Raw | ConvertFrom-Json
$mcp=Get-Content (Join-Path $PluginRoot 'mcp.json') -Raw | ConvertFrom-Json
if($plugin.name -ne 'brave-local'){throw 'bad plugin name'}
if($mcp.mcpServers.'brave-local'.type -ne 'stdio'){throw 'MCP is not stdio'}
if($mcp.mcpServers.'brave-local'.command -ne './bin/windows/brave-local-mcp.exe'){throw 'bad MCP command'}

$required=@(
  'plugin.json',
  'mcp.json',
  'skills/brave-control/SKILL.md',
  'scripts/uia-command.ps1',
  'scripts/uia-printwindow.ps1',
  'bin/windows/brave-local-mcp.exe'
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
} finally {$z.Dispose()}

$parseErrors=$null
[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PluginRoot 'scripts\uia-command.ps1'),[ref]$null,[ref]$parseErrors)|Out-Null
if($parseErrors.Count){throw "uia-command parse error: $($parseErrors[0])"}
$parseErrors=$null
[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PluginRoot 'scripts\uia-printwindow.ps1'),[ref]$null,[ref]$parseErrors)|Out-Null
if($parseErrors.Count){throw "uia-printwindow parse error: $($parseErrors[0])"}
'PACKAGE_VERIFY_PASS'
