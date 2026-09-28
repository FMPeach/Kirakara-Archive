[CmdletBinding()]
param(
  [string]$InstallRoot = $PSScriptRoot,

  [switch]$NoShortcutCleanup
)

$ErrorActionPreference = 'Stop'

function Resolve-FullPath {
  param([Parameter(Mandatory = $true)][string]$Path)

  if ([IO.Path]::IsPathRooted($Path)) {
    return [IO.Path]::GetFullPath($Path)
  }
  return [IO.Path]::GetFullPath((Join-Path (Get-Location).Path $Path))
}

$root = Resolve-FullPath $InstallRoot
$driveRoot = [IO.Path]::GetPathRoot($root)
if (
  [string]::IsNullOrWhiteSpace($driveRoot) -or
  $root.TrimEnd('\') -eq $driveRoot.TrimEnd('\') -or
  $root.TrimEnd('\') -eq (Resolve-FullPath $env:USERPROFILE).TrimEnd('\') -or
  $root.TrimEnd('\') -eq (Resolve-FullPath $env:LOCALAPPDATA).TrimEnd('\')
) {
  throw "Refusing unsafe uninstall root: $root"
}

$installationPath = Join-Path $root 'installation.json'
if (-not (Test-Path -LiteralPath $installationPath -PathType Leaf)) {
  throw "Kirakara installation marker is missing: $installationPath"
}
$installation = Get-Content -Raw -LiteralPath $installationPath | ConvertFrom-Json
if (
  $installation.schemaVersion -ne 1 -or
  $installation.productId -ne 'kirakara-app-windows' -or
  (Resolve-FullPath $installation.installRoot) -ne $root
) {
  throw 'Kirakara installation marker does not match the requested uninstall root.'
}

if (-not $NoShortcutCleanup -and $installation.shortcutPath) {
  $shortcut = Resolve-FullPath $installation.shortcutPath
  $startMenu = Resolve-FullPath (
    Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs')
  if ($shortcut.StartsWith(
      $startMenu.TrimEnd('\') + '\',
      [StringComparison]::OrdinalIgnoreCase) -and
      (Test-Path -LiteralPath $shortcut -PathType Leaf)) {
    Remove-Item -LiteralPath $shortcut -Force
  }
}

Set-Location -LiteralPath $env:TEMP
Remove-Item -LiteralPath $root -Recurse -Force
Write-Host "Kirakara uninstalled from $root"
