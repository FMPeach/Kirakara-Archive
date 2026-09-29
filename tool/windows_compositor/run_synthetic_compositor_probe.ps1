[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$FlutterSdkRoot,

  [Parameter(Mandatory = $true)]
  [string]$WorkspaceRoot,

  [string]$LocalEngine = 'host_debug_kirakara_v4',

  [ValidateRange(10, 14500)]
  [int]$TimeoutSeconds = 45,

  [ValidateRange(0, 14400)]
  [int]$SoakSeconds = 0,

  [ValidateSet(100, 125, 150, 175, 200)]
  [int]$ExpectedScalePercent,

  [switch]$RequireMixedDpi,

  [string]$ReportPath,

  [switch]$SkipBuild,

  [switch]$KeepOpen
)

$ErrorActionPreference = 'Stop'

if ($SoakSeconds -gt 0 -and $SoakSeconds -lt 30) {
  throw 'SoakSeconds must be zero or between 30 and 14400 seconds.'
}
if ($KeepOpen -and $SoakSeconds -gt 0) {
  throw 'KeepOpen and SoakSeconds are separate modes; choose one.'
}

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
  throw "Synthetic compositor Engine mismatch. Expected '$($build.localEngine)', got '$LocalEngine'."
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

$engineSource = $layout.EngineSource
$engineOutput = Get-EngineOutputDirectory `
  -Layout $layout `
  -LocalEngine $LocalEngine
$engineDll = Join-Path $engineOutput 'flutter_windows.dll'
$engineHeader = Join-Path $engineOutput 'flutter_export.h'
foreach ($required in @($flutter, $engineDll, $engineHeader)) {
  if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
    throw "Required synthetic compositor input is missing: $required"
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
  $suffix = if ($SoakSeconds -gt 0) { "-soak-$($SoakSeconds)s" } else { '' }
  $ReportPath = Join-Path $repositoryRoot `
    "build\diagnostics\synthetic-compositor$suffix-$stamp.json"
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
  Push-Location $repositoryRoot
  try {
    & $flutter build windows --debug `
      --target lib/windows_compositor_synthetic_main.dart `
      "--local-engine=$LocalEngine" `
      "--local-engine-host=$LocalEngine" `
      "--local-engine-src-path=$($layout.OutputRoot)"
    if ($LASTEXITCODE -ne 0) {
      throw "Synthetic compositor App build failed (exit $LASTEXITCODE)."
    }
  } finally {
    Pop-Location
  }
}

$bundle = Join-Path $repositoryRoot 'build\windows\x64\runner\Debug'
$executable = Join-Path $bundle 'kirakara_app.exe'
$bundleDll = Join-Path $bundle 'flutter_windows.dll'
foreach ($required in @($executable, $bundleDll)) {
  if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
    throw "Synthetic compositor App bundle is incomplete: $required"
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
  -Label 'Synthetic compositor icudtl.dat'

$startInfo = [Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $executable
$startInfo.WorkingDirectory = $bundle
$startInfo.UseShellExecute = $false
$startInfo.Environment['KIRAKARA_COMPOSITOR_BACKEND'] = 'synthetic'
$startInfo.Environment['KIRAKARA_COMPOSITOR_TEST_MODE'] = '1'
$startInfo.Environment['KIRAKARA_COMPOSITOR_REPORT_PATH'] = $absoluteReport
$startInfo.Environment['KIRAKARA_COMPOSITOR_SOAK_SECONDS'] = `
  $SoakSeconds.ToString([Globalization.CultureInfo]::InvariantCulture)
$startInfo.Environment['KIRAKARA_COMPOSITOR_AUTO_EXIT'] = if ($KeepOpen) {
  '0'
} else {
  '1'
}

$powerRequestActive = $false
if ($SoakSeconds -gt 0) {
  if (-not ('Kirakara.TestPowerRequest' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace Kirakara {
  public static class TestPowerRequest {
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern uint SetThreadExecutionState(uint executionState);
  }
}
'@
  }
  $executionState = [Kirakara.TestPowerRequest]::SetThreadExecutionState(
    [uint32]2147483651
  )
  if ($executionState -eq 0) {
    throw "Could not keep the system and display awake (Win32 $([Runtime.InteropServices.Marshal]::GetLastWin32Error()))."
  }
  $powerRequestActive = $true
  Write-Host "Bounded $SoakSeconds-second soak will keep the system and display awake until the child exits."
  Write-Host 'Keep the probe window visible and unobscured for the entire bounded soak.'
}

$process = [Diagnostics.Process]::new()
$process.StartInfo = $startInfo
try {
  if (-not $process.Start()) {
    throw 'Could not start the synthetic compositor App.'
  }
  Write-Host "Synthetic compositor App started as PID $($process.Id)."

  if ($KeepOpen) {
    Write-Host "Interactive probe left open. Report will be written to $absoluteReport"
    return
  }

  $effectiveTimeoutSeconds = [Math]::Max(
    $TimeoutSeconds,
    $SoakSeconds + 45
  )
  $completed = $process.WaitForExit($effectiveTimeoutSeconds * 1000)
  if (-not $completed) {
    $process.Kill()
    $process.WaitForExit()
    throw "Synthetic compositor App timed out after $effectiveTimeoutSeconds seconds."
  }
  $exitCode = $process.ExitCode
} finally {
  if ($powerRequestActive) {
    [void][Kirakara.TestPowerRequest]::SetThreadExecutionState(
      [uint32]2147483648
    )
  }
}
$process.Dispose()
if ($exitCode -ne 0) {
  throw "Synthetic compositor App exited with code $exitCode."
}
if (-not (Test-Path -LiteralPath $absoluteReport -PathType Leaf)) {
  throw "Synthetic compositor App exited without a report: $absoluteReport"
}

$report = Get-Content -Raw -LiteralPath $absoluteReport | ConvertFrom-Json
if ($report.passed -ne $true) {
  $report | ConvertTo-Json -Depth 12 | Write-Host
  if (
    $report.staticSample.after.stageOccludedCount -gt 0 -or
    $report.gates.noStageOcclusion -eq $false
  ) {
    throw "The compositor clock reported STATUS_GRAPHICS_PRESENT_OCCLUDED. Wake the target display, keep the probe window visible, and rerun with -SkipBuild. Report: $absoluteReport"
  }
  throw "Synthetic compositor runtime gates failed. Report: $absoluteReport"
}

if ($PSBoundParameters.ContainsKey('ExpectedScalePercent')) {
  $actualScale = [int]$report.backend.windowScalePercent
  if ($actualScale -ne $ExpectedScalePercent) {
    throw "Synthetic compositor window scale mismatch. Expected $ExpectedScalePercent%, got $actualScale%. Report: $absoluteReport"
  }
}
if ($RequireMixedDpi) {
  $monitorScales = @(
    $report.backend.monitors |
      ForEach-Object { [int]$_.scalePercent } |
      Sort-Object -Unique
  )
  if ($monitorScales.Count -lt 2) {
    throw "Mixed-DPI validation requires at least two distinct monitor scales. Observed: $($monitorScales -join ', ')%. Report: $absoluteReport"
  }
  if (
    $report.monitorMoveSample.skipped -eq $true -or
    [int]$report.monitorMoveSample.targetBackend.windowDpi -eq
      [int]$report.backend.windowDpi -or
    [int]$report.monitorMoveSample.restoredBackend.windowDpi -ne
      [int]$report.backend.windowDpi
  ) {
    throw "Mixed-DPI monitor migration did not reach a different DPI and return to the original DPI. Report: $absoluteReport"
  }
}

Write-Host "Synthetic compositor runtime gates passed. Report: $absoluteReport"
$report.staticSample | Format-List | Out-Host
$report.platformThreadStall | Format-List | Out-Host
$report.resizeSample | Format-List | Out-Host
$report.overlaySample | Format-List | Out-Host
$report.pageSample | Format-List | Out-Host
$report.monitorMoveSample | Format-List | Out-Host
$report.postInteractionStaticSample | Format-List | Out-Host
if ($null -ne $report.soakSample) {
  $report.soakSample | Format-List | Out-Host
}
