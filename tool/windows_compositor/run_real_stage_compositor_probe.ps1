[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$FlutterSdkRoot,

  [Parameter(Mandatory = $true)]
  [string]$WorkspaceRoot,

  [string]$LocalEngine = 'host_debug_kirakara_v4',

  [string]$FixtureRoot = (Join-Path $env:TEMP 'kira_fixtures'),

  [string]$EofMismatchFixtureRoot,

  [string]$ShowHostDll,

  [string]$TitleKrl = (Join-Path $PSScriptRoot 'fixtures\title_probe.krl'),

  [ValidateRange(30, 180)]
  [int]$TimeoutSeconds = 90,

  [string]$ReportPath,

  [switch]$SkipBuild,

  [switch]$LifecycleProbe,

  [switch]$ExitWhileActive,

  [switch]$KeepOpen
)

$ErrorActionPreference = 'Stop'

$repositoryRoot = [IO.Path]::GetFullPath(
  (Join-Path $PSScriptRoot '..\..')
)
. (Join-Path $repositoryRoot 'engine\scripts\common.ps1')

function Resolve-ShowHostDll {
  param([string]$ExplicitPath)

  $candidates = [Collections.Generic.List[string]]::new()
  if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
    $candidates.Add($ExplicitPath)
  } else {
    $environmentPath = [Environment]::GetEnvironmentVariable(
      'KIRAKARA_SHOW_HOST_DLL', 'Process')
    if (-not [string]::IsNullOrWhiteSpace($environmentPath)) {
      $candidates.Add($environmentPath)
    }
    $candidates.Add((Join-Path (Split-Path -Parent $repositoryRoot) `
      'Kirakara Show\build\bin\libshow_host.dll'))
  }
  foreach ($candidate in $candidates) {
    $resolved = Resolve-UnresolvedPath $candidate
    if (Test-Path -LiteralPath $resolved -PathType Leaf) {
      return (Resolve-Path -LiteralPath $resolved).Path
    }
  }
  throw (
    'A current Show host DLL is required for the real composed Stage probe. ' +
    'Pass -ShowHostDll or set the process-only KIRAKARA_SHOW_HOST_DLL variable. ' +
    "Checked: $($candidates -join ', ')")
}

$lock = Get-EngineLock
$flutterRoot = Resolve-UnresolvedPath $FlutterSdkRoot
$flutter = Join-Path $flutterRoot 'bin\flutter.bat'
$layout = Get-EngineWorkspaceLayout $WorkspaceRoot
Assert-ExternalEngineWorkspace $layout
Assert-AppliedPatchset -Lock $lock -Layout $layout
Assert-MatchingTextFile `
  -ExpectedPath (Join-Path $layout.EngineSource `
    'flutter\shell\platform\windows\kirakara_flutter_compositor_api.h') `
  -ActualPath (Join-Path $repositoryRoot `
    'engine\include\kirakara_flutter_compositor_api.h') `
  -Label 'Kirakara compositor ABI header'
$build = Get-BuildLock `
  -Lock $lock `
  -Mode debug `
  -Variant patched
if ($LocalEngine -ne $build.localEngine) {
  throw "Real Stage compositor Engine mismatch. Expected '$($build.localEngine)', got '$LocalEngine'."
}
if ((Get-GitHead $flutterRoot) -ne $lock.flutter.frameworkRevision) {
  throw 'Flutter Framework revision does not match engine.lock.json.'
}
$sdkEngineRevision = (
  Get-Content -Raw -LiteralPath (Join-Path $flutterRoot 'bin\internal\engine.version')
).Trim()
if ($sdkEngineRevision -ne $lock.flutter.engineRevision) {
  throw 'Flutter SDK Engine revision does not match engine.lock.json.'
}

$fixtureDirectory = Resolve-UnresolvedPath $FixtureRoot
$eofMismatchDirectory = $null
if (-not [string]::IsNullOrWhiteSpace($EofMismatchFixtureRoot)) {
  $eofMismatchDirectory = Resolve-UnresolvedPath $EofMismatchFixtureRoot
}
$showDll = Resolve-ShowHostDll -ExplicitPath $ShowHostDll
$showAbi = & (Join-Path $repositoryRoot `
  'engine\scripts\verify_show_host_stage_visual_abi.ps1') `
  -ShowHostDll $showDll
$titleKrlPath = Resolve-UnresolvedPath $TitleKrl
$requiredFixtures = @(
  'v1.mp4', 'l1.krl', 'vocal1.wav', 'inst1.wav',
  'v2.mp4', 'l2.krl', 'vocal2.wav', 'inst2.wav'
)
foreach ($name in $requiredFixtures) {
  $path = Join-Path $fixtureDirectory $name
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "Real Stage fixture is missing: $path. Run the Show repository's tools\make_smoke_fixtures.ps1 first."
  }
}
if ($eofMismatchDirectory) {
  $mismatchManifestPath = Join-Path $eofMismatchDirectory 'manifest.json'
  if (-not (Test-Path -LiteralPath $mismatchManifestPath -PathType Leaf)) {
    throw (
      "EOF mismatch manifest is missing: $mismatchManifestPath. " +
      'Run tool\windows_compositor\make_eof_mismatch_fixtures.ps1 first.')
  }
  $mismatchManifest = Get-Content -Raw -LiteralPath $mismatchManifestPath |
    ConvertFrom-Json
  if (
    [int]$mismatchManifest.schemaVersion -ne 1 -or
    $mismatchManifest.videoMasterClock -ne $true -or
    @($mismatchManifest.cases).Count -ne 2
  ) {
    throw "EOF mismatch manifest contract is invalid: $mismatchManifestPath"
  }
  $mismatchNames = @($mismatchManifest.cases | ForEach-Object {
      [string]$_.name
    } | Sort-Object)
  if (
    @(Compare-Object `
        @('audio-shorter-than-video', 'video-shorter-than-audio') `
        $mismatchNames).Count -ne 0
  ) {
    throw 'EOF mismatch manifest does not contain both required directions.'
  }
  foreach ($fixtureCase in @($mismatchManifest.cases)) {
    foreach ($property in 'video', 'vocal', 'accompaniment') {
      $fileName = [string]$fixtureCase.$property
      $path = Join-Path $eofMismatchDirectory $fileName
      if (
        [string]::IsNullOrWhiteSpace($fileName) -or
        [IO.Path]::GetFileName($fileName) -cne $fileName -or
        -not (Test-Path -LiteralPath $path -PathType Leaf)
      ) {
        throw "EOF mismatch fixture is missing: $path"
      }
    }
    $videoDuration = [double]$fixtureCase.videoDurationSeconds
    $vocalDuration = [double]$fixtureCase.vocalDurationSeconds
    $accompanimentDuration = [double]$fixtureCase.accompanimentDurationSeconds
    foreach ($duration in $videoDuration, $vocalDuration,
        $accompanimentDuration) {
      if (
        [double]::IsNaN($duration) -or
        [double]::IsInfinity($duration) -or
        $duration -le 0 -or
        $duration -gt 20
      ) {
        throw "EOF mismatch manifest has an invalid duration: $duration"
      }
    }
    if (
      [string]$fixtureCase.name -eq 'audio-shorter-than-video' -and
      $videoDuration - [Math]::Max($vocalDuration, $accompanimentDuration) `
        -lt 0.75
    ) {
      throw 'The audio-short EOF fixture does not end both audio tracks first.'
    }
    if (
      [string]$fixtureCase.name -eq 'video-shorter-than-audio' -and
      [Math]::Min($vocalDuration, $accompanimentDuration) - $videoDuration `
        -lt 0.75
    ) {
      throw 'The video-short EOF fixture does not end before both audio tracks.'
    }
  }
}
if (-not (Test-Path -LiteralPath $showDll -PathType Leaf)) {
  throw "Show host DLL is missing: $showDll"
}
if (-not (Test-Path -LiteralPath $titleKrlPath -PathType Leaf)) {
  throw "Titled KRL fixture is missing: $titleKrlPath"
}

$engineSource = $layout.EngineSource
$engineOutput = Get-EngineOutputDirectory `
  -Layout $layout `
  -LocalEngine $LocalEngine
$engineDll = Join-Path $engineOutput 'flutter_windows.dll'
$engineHeader = Join-Path $engineOutput 'flutter_export.h'
foreach ($required in @($flutter, $engineDll, $engineHeader)) {
  if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
    throw "Required real Stage compositor input is missing: $required"
  }
}
Assert-UsableEngineArtifacts `
  -Layout $layout `
  -Lock $lock `
  -Build $build `
  -Mode debug `
  -Variant patched `
  -OutputDirectory $engineOutput

if ([string]::IsNullOrWhiteSpace($ReportPath)) {
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $reportStem = if ($LifecycleProbe -and $eofMismatchDirectory) {
    'real-stage-lifecycle-eof-mismatch'
  } elseif ($LifecycleProbe) {
    'real-stage-lifecycle'
  } elseif ($eofMismatchDirectory) {
    'real-stage-eof-mismatch'
  } else {
    'real-stage-compositor'
  }
  $ReportPath = Join-Path $repositoryRoot `
    "build\diagnostics\$reportStem-$stamp.json"
}
$absoluteReport = Resolve-UnresolvedPath $ReportPath
if (Test-Path -LiteralPath $absoluteReport) {
  throw "ReportPath already exists; preserve it or choose another path: $absoluteReport"
}

if (-not $SkipBuild) {
  Invalidate-StaleFlutterWindowsBuildForSdk `
    -FlutterSdkRoot $flutterRoot `
    -AppRoot $repositoryRoot | Out-Null
  Invalidate-StaleFlutterEphemeralEngine `
    -EngineOutputDirectory $engineOutput `
    -AppRoot $repositoryRoot
  $priorShowHostDll = [Environment]::GetEnvironmentVariable(
    'KIRAKARA_SHOW_HOST_DLL', 'Process')
  try {
    [Environment]::SetEnvironmentVariable(
      'KIRAKARA_SHOW_HOST_DLL', $showDll, 'Process')
    Push-Location $repositoryRoot
    try {
      & $flutter build windows --debug `
        --target lib/windows_compositor_real_stage_main.dart `
        "--local-engine=$LocalEngine" `
        "--local-engine-host=$LocalEngine" `
        "--local-engine-src-path=$($layout.OutputRoot)"
      if ($LASTEXITCODE -ne 0) {
        throw "Real Stage compositor App build failed (exit $LASTEXITCODE)."
      }
    } finally {
      Pop-Location
    }
  } finally {
    [Environment]::SetEnvironmentVariable(
      'KIRAKARA_SHOW_HOST_DLL', $priorShowHostDll, 'Process')
  }
}

$bundle = Join-Path $repositoryRoot 'build\windows\x64\runner\Debug'
$executable = Join-Path $bundle 'kirakara_app.exe'
$bundleDll = Join-Path $bundle 'flutter_windows.dll'
$bundleShowDll = Join-Path $bundle 'libshow_host.dll'
foreach ($required in @($executable, $bundleDll, $bundleShowDll)) {
  if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
    throw "Real Stage compositor App bundle is incomplete: $required"
  }
}
$engineHash = (Get-FileHash -LiteralPath $engineDll -Algorithm SHA256).Hash
$bundleHash = (Get-FileHash -LiteralPath $bundleDll -Algorithm SHA256).Hash
if ($engineHash -ne $bundleHash) {
  throw 'App bundle flutter_windows.dll does not match the selected custom Engine.'
}
Assert-MatchingFile `
  -ExpectedPath (Join-Path $engineOutput 'icudtl.dat') `
  -ActualPath (Join-Path $bundle 'data\icudtl.dat') `
  -Label 'Real Stage compositor icudtl.dat'
Assert-MatchingFile `
  -ExpectedPath $showDll `
  -ActualPath $bundleShowDll `
  -Label 'Real Stage compositor libshow_host.dll'

$startInfo = [Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $executable
$startInfo.WorkingDirectory = $bundle
$startInfo.UseShellExecute = $false
$startInfo.Environment['KIRAKARA_COMPOSITOR_BACKEND'] = 'composed'
$startInfo.Environment['KIRAKARA_COMPOSITOR_TEST_MODE'] = '1'
$startInfo.Environment['KIRAKARA_COMPOSITOR_FIXTURE_ROOT'] = $fixtureDirectory
$startInfo.Environment['KIRAKARA_COMPOSITOR_EOF_MISMATCH_ROOT'] = if (
  $eofMismatchDirectory
) {
  $eofMismatchDirectory
} else {
  ''
}
$startInfo.Environment['KIRAKARA_COMPOSITOR_TITLE_KRL'] = $titleKrlPath
$startInfo.Environment['KIRAKARA_COMPOSITOR_REPORT_PATH'] = $absoluteReport
$startInfo.Environment['KIRAKARA_COMPOSITOR_AUTO_EXIT'] = if ($KeepOpen) {
  '0'
} else {
  '1'
}
$startInfo.Environment['KIRAKARA_COMPOSITOR_KEEP_OPEN'] = if ($KeepOpen) {
  '1'
} else {
  '0'
}
$startInfo.Environment['KIRAKARA_COMPOSITOR_LIFECYCLE_PROBE'] = if (
  $LifecycleProbe
) {
  '1'
} else {
  '0'
}
$startInfo.Environment['KIRAKARA_COMPOSITOR_EXIT_WHILE_ACTIVE'] = if (
  $ExitWhileActive
) {
  '1'
} else {
  '0'
}

$process = [Diagnostics.Process]::new()
$process.StartInfo = $startInfo
if (-not $process.Start()) {
  throw 'Could not start the real Stage compositor App.'
}
Write-Host "Real Stage compositor App started as PID $($process.Id)."

if ($KeepOpen) {
  Write-Host (
    "Interactive probe left open. Show host $($showAbi.dllSha256); " +
    "report will be written to $absoluteReport")
  return
}

$completed = $process.WaitForExit($TimeoutSeconds * 1000)
if (-not $completed) {
  $process.Kill()
  $process.WaitForExit()
  throw "Real Stage compositor App timed out after $TimeoutSeconds seconds."
}
$exitCode = $process.ExitCode
$process.Dispose()
if ($exitCode -ne 0) {
  throw "Real Stage compositor App exited with code $exitCode."
}
if (-not (Test-Path -LiteralPath $absoluteReport -PathType Leaf)) {
  throw "Real Stage compositor App exited without a report: $absoluteReport"
}

$report = Get-Content -Raw -LiteralPath $absoluteReport | ConvertFrom-Json
$report | Add-Member -NotePropertyName showHostArtifact -NotePropertyValue (
  [pscustomobject][ordered]@{
    dllSha256 = [string]$showAbi.dllSha256
    dllSize = [int64]$showAbi.dllSize
    abiVersion = [uint32]$showAbi.abiVersion
    capabilities = [uint64]$showAbi.capabilities
    protocolRevision = [string]$showAbi.protocolRevision
  }) -Force
$report | ConvertTo-Json -Depth 16 | Set-Content `
  -LiteralPath $absoluteReport `
  -Encoding utf8
if ($report.passed -ne $true) {
  $report | ConvertTo-Json -Depth 14 | Write-Host
  throw "Real Stage compositor runtime gates failed. Report: $absoluteReport"
}

Write-Host "Real Stage compositor runtime gates passed. Report: $absoluteReport"
$report.staticSample | Format-List | Out-Host
$report.platformThreadStall | Format-List | Out-Host
$report.resizeSample | Format-List | Out-Host
$report.generationSwitchSample | Format-List | Out-Host
$report.pauseResumeSample | Format-List | Out-Host
$report.replaySample | Format-List | Out-Host
$report.naturalEofSample | Format-List | Out-Host
$report.reloadAfterNaturalEofSample | Format-List | Out-Host
if ($eofMismatchDirectory) {
  $report.eofMismatchSample | Format-List | Out-Host
}
$report.detachReattachSample | Format-List | Out-Host
$report.visibilitySample | Format-List | Out-Host
$report.animationSample | Format-List | Out-Host
if ($LifecycleProbe) {
  $report.lifecycle | Format-List | Out-Host
}
$report.postInteractionStaticSample | Format-List | Out-Host
