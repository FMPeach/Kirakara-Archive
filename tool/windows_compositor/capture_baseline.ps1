[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$OutputPath,

  [string]$AppRepository = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,

  [Parameter(Mandatory = $true)]
  [string]$ShowRepository,

  [string]$FlutterExecutable = 'flutter'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Invoke-Captured {
  param(
    [Parameter(Mandatory = $true)][string]$Executable,
    [Parameter(Mandatory = $true)][string[]]$Arguments
  )
  $output = & $Executable @Arguments 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "$Executable failed with exit code $LASTEXITCODE.`n$output"
  }
  return ($output -join "`n").Trim()
}

function Get-GitSnapshot {
  param([Parameter(Mandatory = $true)][string]$Repository)
  $resolved = (Resolve-Path -LiteralPath $Repository).Path
  return [ordered]@{
    path = $resolved
    head = Invoke-Captured git @('-C', $resolved, 'rev-parse', 'HEAD')
    branch = Invoke-Captured git @('-C', $resolved, 'branch', '--show-current')
    status = Invoke-Captured git @('-C', $resolved, 'status', '--porcelain=v2', '--branch')
  }
}

function Get-ArtifactRecord {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  $file = Get-Item -LiteralPath $Path
  return [ordered]@{
    path = $file.FullName
    length = $file.Length
    sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
  }
}

$flutterCommand = (Get-Command $FlutterExecutable -ErrorAction Stop).Source
$flutter = Invoke-Captured $flutterCommand @('--version', '--machine') |
  ConvertFrom-Json
$flutterRoot = $flutter.flutterRoot
$engineArtifacts = @(
  'windows-x64',
  'windows-x64-profile',
  'windows-x64-release'
) | ForEach-Object {
  Get-ArtifactRecord (Join-Path $flutterRoot "bin\cache\artifacts\engine\$_\flutter_windows.dll")
} | Where-Object { $null -ne $_ }

$os = Get-CimInstance Win32_OperatingSystem
$currentVersion = Get-ItemProperty `
  'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$gpus = Get-CimInstance Win32_VideoController | ForEach-Object {
  [ordered]@{
    name = $_.Name
    driverVersion = $_.DriverVersion
    driverDate = $_.DriverDate
    horizontalResolution = $_.CurrentHorizontalResolution
    verticalResolution = $_.CurrentVerticalResolution
    refreshRate = $_.CurrentRefreshRate
  }
}

$toolNames = @('cmake', 'ninja', 'git', 'python', 'wpr', 'wpa')
$tools = foreach ($name in $toolNames) {
  $command = Get-Command $name -ErrorAction SilentlyContinue |
    Select-Object -First 1
  if ($null -eq $command) { continue }
  [ordered]@{
    name = $name
    path = $command.Source
    version = $command.Version.ToString()
  }
}

$record = [ordered]@{
  schemaVersion = 1
  capturedAt = (Get-Date).ToUniversalTime().ToString('o')
  app = Get-GitSnapshot $AppRepository
  show = Get-GitSnapshot $ShowRepository
  flutter = $flutter
  windows = [ordered]@{
    caption = $os.Caption
    version = $os.Version
    build = $os.BuildNumber
    ubr = $currentVersion.UBR
    architecture = $os.OSArchitecture
  }
  videoControllers = @($gpus)
  engineArtifacts = @($engineArtifacts)
  tools = @($tools)
}

$absoluteOutput = [System.IO.Path]::GetFullPath($OutputPath)
$outputDirectory = Split-Path -Parent $absoluteOutput
if (-not (Test-Path -LiteralPath $outputDirectory)) {
  New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}
$record | ConvertTo-Json -Depth 8 |
  Set-Content -LiteralPath $absoluteOutput -Encoding utf8
Write-Host "Baseline saved to $absoluteOutput"
