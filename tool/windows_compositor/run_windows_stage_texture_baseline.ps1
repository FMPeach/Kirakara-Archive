[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$ShowRepository,

  [string]$FlutterExecutable = 'flutter',

  [ValidateSet('debug', 'profile')]
  [string]$Mode = 'debug',

  [ValidateSet('official', 'local')]
  [string]$Engine = 'official',

  [ValidateSet('stock', 'patched')]
  [string]$LocalVariant = 'stock',

  [string]$EngineWorkspaceRoot,

  [switch]$SkipCadenceGate
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$fixtureRoot = Join-Path $ShowRepository 'build\cast_fixtures'
$fixtures = [ordered]@{
  KIRAKARA_TEST_VIDEO = Join-Path $fixtureRoot 'video1.mp4'
  KIRAKARA_TEST_LYRIC = Join-Path $fixtureRoot 'krl1.krl'
  KIRAKARA_TEST_VOCAL = Join-Path $fixtureRoot 'vocal1.wav'
  KIRAKARA_TEST_ACCOMPANIMENT = Join-Path $fixtureRoot 'inst1.wav'
}
foreach ($fixture in $fixtures.Values) {
  if (-not (Test-Path -LiteralPath $fixture)) {
    throw "Missing Show fixture: $fixture"
  }
}

$appRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
. (Join-Path $appRoot 'engine\scripts\common.ps1')
$flutter = (Get-Command $FlutterExecutable -ErrorAction Stop).Source
if ($Mode -eq 'debug') {
  $arguments = @(
    'test',
    'integration_test\windows_stage_texture_baseline_test.dart',
    '-d',
    'windows'
  )
} else {
  $arguments = @(
    'drive',
    '--driver=test_driver\integration_test.dart',
    '--target=integration_test\windows_stage_texture_baseline_test.dart',
    '-d',
    'windows',
    "--$Mode",
    '--no-keep-app-running'
  )
}

$selectedEngineDirectory = $null
if ($Engine -eq 'local') {
  if ([string]::IsNullOrWhiteSpace($EngineWorkspaceRoot)) {
    throw '-EngineWorkspaceRoot is required for -Engine local.'
  }
  $lock = Get-EngineLock
  $layout = Get-EngineWorkspaceLayout $EngineWorkspaceRoot
  Assert-ExternalEngineWorkspace $layout
  if ($LocalVariant -eq 'patched') {
    Assert-AppliedPatchset -Lock $lock -Layout $layout
  } else {
    Assert-PinnedFlutterSource -Lock $lock -Layout $layout
  }
  $build = Get-BuildLock `
    -Lock $lock `
    -Mode $Mode `
    -Variant $LocalVariant
  $selectedEngineDirectory = Join-Path `
    $layout.EngineSource "out\$($build.localEngine)"
  Assert-LockedEngineArtifacts `
    -Build $build `
    -OutputDirectory $selectedEngineDirectory
  $arguments += @(
    "--local-engine=$($build.localEngine)",
    "--local-engine-host=$($build.localEngineHost)",
    "--local-engine-src-path=$($layout.EngineSource)"
  )
}
foreach ($entry in $fixtures.GetEnumerator()) {
  $arguments += "--dart-define=$($entry.Key)=$($entry.Value)"
}

$diagnosticsVariable = 'KIRAKARA_COMPOSITOR_DIAGNOSTICS'
$backendVariable = 'KIRAKARA_COMPOSITOR_BACKEND'
$previousDiagnostics = [Environment]::GetEnvironmentVariable(
  $diagnosticsVariable,
  [EnvironmentVariableTarget]::Process
)
$previousBackend = [Environment]::GetEnvironmentVariable(
  $backendVariable,
  [EnvironmentVariableTarget]::Process
)
$diagnosticsValue = if ($SkipCadenceGate) { '0' } else { '1' }
try {
  [Environment]::SetEnvironmentVariable(
    $diagnosticsVariable,
    $diagnosticsValue,
    [EnvironmentVariableTarget]::Process
  )
  [Environment]::SetEnvironmentVariable(
    $backendVariable,
    'external_texture',
    [EnvironmentVariableTarget]::Process
  )
  Push-Location $appRoot
  try {
    & $flutter @arguments
    if ($LASTEXITCODE -ne 0) {
      throw "Windows Stage texture baseline failed with exit code $LASTEXITCODE."
    }

    $configuration = switch ($Mode) {
      'debug' { 'Debug' }
      'profile' { 'Profile' }
    }
    $bundle = Join-Path $appRoot "build\windows\x64\runner\$configuration"
    $flutterRoot = Split-Path -Parent (Split-Path -Parent $flutter)
    if ($Engine -eq 'official') {
      $officialDirectoryName = switch ($Mode) {
        'debug' { 'windows-x64' }
        'profile' { 'windows-x64-profile' }
      }
      $selectedEngineDirectory = Join-Path $flutterRoot `
        "bin\cache\artifacts\engine\$officialDirectoryName"
    }
    $icuDirectory = if ($Engine -eq 'local') {
      $selectedEngineDirectory
    } else {
      Join-Path $flutterRoot 'bin\cache\artifacts\engine\windows-x64'
    }
    Assert-MatchingFile `
      -ExpectedPath (Join-Path $selectedEngineDirectory 'flutter_windows.dll') `
      -ActualPath (Join-Path $bundle 'flutter_windows.dll') `
      -Label "App $Mode flutter_windows.dll for $Engine Engine"
    Assert-MatchingFile `
      -ExpectedPath (Join-Path $icuDirectory 'icudtl.dat') `
      -ActualPath (Join-Path $bundle 'data\icudtl.dat') `
      -Label "App $Mode icudtl.dat for $Engine Engine"
    Write-Host "Verified integration bundle uses the selected '$Engine' Engine."
  } finally {
    Pop-Location
  }
} finally {
  [Environment]::SetEnvironmentVariable(
    $diagnosticsVariable,
    $previousDiagnostics,
    [EnvironmentVariableTarget]::Process
  )
  [Environment]::SetEnvironmentVariable(
    $backendVariable,
    $previousBackend,
    [EnvironmentVariableTarget]::Process
  )
}
