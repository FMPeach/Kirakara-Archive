[CmdletBinding()]
param(
  [string]$PayloadPath = (Join-Path $PSScriptRoot 'payload'),

  [string]$Destination = (Join-Path $env:LOCALAPPDATA 'Programs\Kirakara'),

  [switch]$NoShortcut
)

$ErrorActionPreference = 'Stop'

function Resolve-FullPath {
  param([Parameter(Mandatory = $true)][string]$Path)

  if ([IO.Path]::IsPathRooted($Path)) {
    return [IO.Path]::GetFullPath($Path)
  }
  return [IO.Path]::GetFullPath((Join-Path (Get-Location).Path $Path))
}

function Assert-SafeInstallRoot {
  param([Parameter(Mandatory = $true)][string]$Path)

  $fullPath = Resolve-FullPath $Path
  $root = [IO.Path]::GetPathRoot($fullPath)
  if (
    [string]::IsNullOrWhiteSpace($root) -or
    $fullPath.TrimEnd('\') -eq $root.TrimEnd('\') -or
    $fullPath.TrimEnd('\') -eq (Resolve-FullPath $env:USERPROFILE).TrimEnd('\') -or
    $fullPath.TrimEnd('\') -eq (Resolve-FullPath $env:LOCALAPPDATA).TrimEnd('\')
  ) {
    throw "Refusing unsafe install destination: $fullPath"
  }
  return $fullPath
}

$payload = Resolve-FullPath $PayloadPath
if (-not (Test-Path -LiteralPath $payload -PathType Container)) {
  throw "Installer payload directory is missing: $payload"
}
$manifestPath = Join-Path $payload 'release-manifest.json'
$checksumsPath = Join-Path $payload 'SHA256SUMS.txt'
if (
  -not (Test-Path -LiteralPath $manifestPath -PathType Leaf) -or
  -not (Test-Path -LiteralPath $checksumsPath -PathType Leaf)
) {
  throw 'Installer payload is missing release-manifest.json or SHA256SUMS.txt.'
}

$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1 -or $manifest.productId -ne 'kirakara-app-windows') {
  throw 'Installer payload manifest is not a supported Kirakara Windows release.'
}

$expectedFiles = [Collections.Generic.HashSet[string]]::new(
  [StringComparer]::OrdinalIgnoreCase)
$checksumLines = Get-Content -LiteralPath $checksumsPath
foreach ($line in $checksumLines) {
  if ($line -notmatch '^([0-9A-F]{64}) \*(.+)$') {
    throw "Invalid SHA256SUMS entry: $line"
  }
  $expectedHash = $Matches[1]
  $relativePath = $Matches[2].Replace('/', [IO.Path]::DirectorySeparatorChar)
  if (
    [IO.Path]::IsPathRooted($relativePath) -or
    $relativePath.Split([IO.Path]::DirectorySeparatorChar) -contains '..'
  ) {
    throw "Unsafe SHA256SUMS path: $relativePath"
  }
  $file = Resolve-FullPath (Join-Path $payload $relativePath)
  $payloadPrefix = $payload.TrimEnd('\') + '\'
  if (-not $file.StartsWith($payloadPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "SHA256SUMS path escapes the payload: $relativePath"
  }
  if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
    throw "Installer payload file is missing: $relativePath"
  }
  $actualHash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
  if ($actualHash -ne $expectedHash) {
    throw "Installer payload hash mismatch: $relativePath"
  }
  $null = $expectedFiles.Add($relativePath)
}

$actualFiles = Get-ChildItem -LiteralPath $payload -File -Recurse | ForEach-Object {
  [IO.Path]::GetRelativePath($payload, $_.FullName)
} | Where-Object { $_ -ne 'SHA256SUMS.txt' }
$unexpectedFiles = @($actualFiles | Where-Object { -not $expectedFiles.Contains($_) })
if ($unexpectedFiles.Count -ne 0) {
  throw "Installer payload contains unhashed files: $($unexpectedFiles -join ', ')"
}

$installRoot = Assert-SafeInstallRoot $Destination
if (Test-Path -LiteralPath $installRoot) {
  throw "Install destination already exists; uninstall it first: $installRoot"
}
$installParent = Split-Path -Parent $installRoot
New-Item -ItemType Directory -Path $installParent -Force | Out-Null
$staging = "$installRoot.installing-$([Guid]::NewGuid().ToString('N'))"
if ((Split-Path -Parent $staging) -ne $installParent) {
  throw 'Internal installer staging path validation failed.'
}

try {
  New-Item -ItemType Directory -Path $staging | Out-Null
  foreach ($item in Get-ChildItem -LiteralPath $payload -Force) {
    Copy-Item -LiteralPath $item.FullName -Destination $staging -Recurse
  }
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'uninstall_windows_portable.ps1') `
    -Destination (Join-Path $staging 'Uninstall-Kirakara.ps1')

  $shortcutPath = $null
  if (-not $NoShortcut) {
    $startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
    New-Item -ItemType Directory -Path $startMenu -Force | Out-Null
    $shortcutPath = Join-Path $startMenu 'Kirakara.lnk'
  }
  $installation = [ordered]@{
    schemaVersion = 1
    productId = 'kirakara-app-windows'
    packageId = $manifest.packageId
    version = $manifest.version
    installRoot = $installRoot
    shortcutPath = $shortcutPath
    installedAt = (Get-Date).ToUniversalTime().ToString('o')
  }
  $installation | ConvertTo-Json -Depth 5 | Set-Content `
    -LiteralPath (Join-Path $staging 'installation.json') -Encoding utf8

  Move-Item -LiteralPath $staging -Destination $installRoot
  if ($shortcutPath) {
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = Join-Path $installRoot 'kirakara_app.exe'
    $shortcut.WorkingDirectory = $installRoot
    $shortcut.Description = 'Kirakara'
    $shortcut.Save()
  }
} finally {
  if (Test-Path -LiteralPath $staging) {
    $validatedParent = Split-Path -Parent (Resolve-FullPath $staging)
    if ($validatedParent -ne $installParent) {
      throw 'Refusing to clean an unexpected installer staging path.'
    }
    Remove-Item -LiteralPath $staging -Recurse -Force
  }
}

Write-Host "Kirakara installed to $installRoot"
