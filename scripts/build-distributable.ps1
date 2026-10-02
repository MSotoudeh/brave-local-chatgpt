param([string]$Version='0.2.0')
$ErrorActionPreference='Stop'
$RepoRoot=Split-Path -Parent $PSScriptRoot
$PluginRoot=Join-Path $RepoRoot 'plugins\brave-local'
$Bin=Join-Path $PluginRoot 'bin\windows\brave-local-mcp.exe'
$Dist=Join-Path $RepoRoot 'dist'
$Zip=Join-Path $Dist "brave-local-$Version-windows.zip"

New-Item -ItemType Directory -Force (Split-Path $Bin -Parent),(Join-Path $PluginRoot 'scripts'),$Dist | Out-Null
Push-Location $RepoRoot
try {
  & go build -trimpath -o $Bin .\cmd\brave-local-mcp
  if($LASTEXITCODE -ne 0){throw 'go build failed'}
} finally { Pop-Location }

Copy-Item (Join-Path $RepoRoot 'scripts\uia-command.ps1') (Join-Path $PluginRoot 'scripts\uia-command.ps1') -Force
Copy-Item (Join-Path $RepoRoot 'scripts\uia-printwindow.ps1') (Join-Path $PluginRoot 'scripts\uia-printwindow.ps1') -Force

Remove-Item $Zip -Force -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$stream=[IO.File]::Open($Zip,[IO.FileMode]::CreateNew)
$archive=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$false)
try {
  Get-ChildItem $PluginRoot -Recurse -File | ForEach-Object {
    $rel=$_.FullName.Substring($PluginRoot.Length+1).Replace('\','/')
    $entry=$archive.CreateEntry($rel,[IO.Compression.CompressionLevel]::Optimal)
    $source=[IO.File]::OpenRead($_.FullName)
    $target=$entry.Open()
    try { $source.CopyTo($target) }
    finally { $target.Dispose(); $source.Dispose() }
  }
} finally {
  $archive.Dispose()
  $stream.Dispose()
}

[ordered]@{
  Version=$Version
  PluginRoot=$PluginRoot
  Archive=$Zip
  Binary=$Bin
  Size=(Get-Item $Zip).Length
} | ConvertTo-Json
