[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$FlutterSdkRoot,

  [Parameter(Mandatory = $true)]
  [string]$WorkspaceRoot,

  [string]$LocalEngine = 'host_debug_kirakara_v3',

  [string]$FixtureRoot = (Join-Path $env:TEMP 'kira_fixtures'),

  [string]$ShowHostDll = 'D:\仓库\Kirakara Show\build\bin\libshow_host.dll',

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
$showDll = Resolve-UnresolvedPath $ShowHostDll
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
if (-not (Test-Path -LiteralPath $showDll -PathType Leaf)) {
  throw "Show host DLL is missing: $showDll"
}
if (-not (Test-Path -LiteralPath $titleKrlPath -PathType Leaf)) {
  throw "Titled KRL fixture is missing: $titleKrlPath"
}

$engineSource = $layout.EngineSource
$engineOutput = Join-Path $engineSource "out\$LocalEngine"
$engineDll = Join-Path $engineOutput 'flutter_windows.dll'
$engineHeader = Join-Path $engineOutput 'flutter_export.h'
foreach ($required in @($flutter, $engineDll, $engineHeader)) {
  if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
    throw "Required real Stage compositor input is missing: $required"
  }
}
Assert-LockedEngineArtifacts `
  -Build $build `
  -OutputDirectory $engineOutput

if ([string]::IsNullOrWhiteSpace($ReportPath)) {
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $reportStem = if ($LifecycleProbe) {
    'real-stage-lifecycle'
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
  Push-Location $repositoryRoot
  try {
    & $flutter build windows --debug `
      --target lib/windows_compositor_real_stage_main.dart `
      "--local-engine=$LocalEngine" `
      "--local-engine-host=$LocalEngine" `
      "--local-engine-src-path=$engineSource"
    if ($LASTEXITCODE -ne 0) {
      throw "Real Stage compositor App build failed (exit $LASTEXITCODE)."
    }
  } finally {
    Pop-Location
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
  Write-Host "Interactive probe left open. Report will be written to $absoluteReport"
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
$report.detachReattachSample | Format-List | Out-Host
$report.lifecycle | Format-List | Out-Host
$report.postInteractionStaticSample | Format-List | Out-Host
