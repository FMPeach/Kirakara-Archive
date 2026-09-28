[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$FlutterSdkRoot,

  [ValidateSet('official', 'local')]
  [string]$Engine = 'local',

  [ValidateSet('stock', 'patched')]
  [string]$LocalVariant = 'stock',

  [string]$WorkspaceRoot,

  [ValidateSet('debug', 'profile', 'release')]
  [string]$Mode = 'release',

  [string]$BundlePath,

  [ValidateRange(1, 120)]
  [int]$StartupTimeoutSeconds = 30,

  [ValidateRange(1, 120)]
  [int]$ObserveSeconds = 5,

  [ValidateRange(1, 120)]
  [int]$ShutdownTimeoutSeconds = 20,

  [string]$ReportPath,

  [switch]$AllowForcedCleanup
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$lock = Get-EngineLock
$flutterRoot = Resolve-UnresolvedPath $FlutterSdkRoot
$flutter = Join-Path $flutterRoot 'bin\flutter.bat'
if (-not (Test-Path -LiteralPath $flutter -PathType Leaf)) {
  throw "Flutter SDK is missing flutter.bat: $flutterRoot"
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

$buildVariant = if ($Engine -eq 'local') { $LocalVariant } else { 'stock' }
$build = Get-BuildLock `
  -Lock $lock `
  -Mode $Mode `
  -Variant $buildVariant
$layout = $null
$engineDirectory = $null
if ($Engine -eq 'local') {
  if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    throw '-WorkspaceRoot is required for -Engine local.'
  }
  $layout = Get-EngineWorkspaceLayout $WorkspaceRoot
  Assert-ExternalEngineWorkspace $layout
  if ($LocalVariant -eq 'stock') {
    Assert-PinnedFlutterSource -Lock $lock -Layout $layout -RequireStockTree
  } else {
    Assert-AppliedPatchset -Lock $lock -Layout $layout
    Assert-MatchingTextFile `
      -ExpectedPath (Join-Path $layout.EngineSource `
        'flutter\shell\platform\windows\kirakara_flutter_compositor_api.h') `
      -ActualPath (Join-Path (Get-AppRepositoryRoot) `
        'engine\include\kirakara_flutter_compositor_api.h') `
      -Label 'Kirakara compositor ABI header'
  }
  $engineDirectory = Get-EngineOutputDirectory `
    -Layout $layout `
    -LocalEngine $build.localEngine
  Assert-UsableEngineArtifacts `
    -Layout $layout `
    -Lock $lock `
    -Build $build `
    -Mode $Mode `
    -Variant $LocalVariant `
    -OutputDirectory $engineDirectory
} else {
  if ($LocalVariant -ne 'stock') {
    throw '-LocalVariant patched applies only to -Engine local.'
  }
  $officialDirectoryName = switch ($Mode) {
    'debug' { 'windows-x64' }
    'profile' { 'windows-x64-profile' }
    'release' { 'windows-x64-release' }
  }
  $engineDirectory = Join-Path $flutterRoot `
    "bin\cache\artifacts\engine\$officialDirectoryName"
}

$configuration = switch ($Mode) {
  'debug' { 'Debug' }
  'profile' { 'Profile' }
  'release' { 'Release' }
}
$bundle = if ([string]::IsNullOrWhiteSpace($BundlePath)) {
  Join-Path (Get-AppRepositoryRoot) "build\windows\x64\runner\$configuration"
} else {
  Resolve-UnresolvedPath $BundlePath
}
if (-not (Test-Path -LiteralPath $bundle -PathType Container)) {
  throw "Kirakara App bundle directory is missing: $bundle"
}
$executable = Join-Path $bundle 'kirakara_app.exe'
if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
  throw "Kirakara App bundle is missing. Build it before smoke testing: $executable"
}
Assert-MatchingFile `
  -ExpectedPath (Join-Path $engineDirectory 'flutter_windows.dll') `
  -ActualPath (Join-Path $bundle 'flutter_windows.dll') `
  -Label "App $Mode flutter_windows.dll for $Engine Engine"
$icuDirectory = if ($Engine -eq 'local') {
  $engineDirectory
} else {
  Join-Path $flutterRoot 'bin\cache\artifacts\engine\windows-x64'
}
Assert-MatchingFile `
  -ExpectedPath (Join-Path $icuDirectory 'icudtl.dat') `
  -ActualPath (Join-Path $bundle 'data\icudtl.dat') `
  -Label "App $Mode icudtl.dat for $Engine Engine"

if ([string]::IsNullOrWhiteSpace($ReportPath)) {
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $engineLabel = if ($Engine -eq 'local') {
    "$Engine-$LocalVariant"
  } else {
    $Engine
  }
  $ReportPath = Join-Path (Get-AppRepositoryRoot) `
    "build\diagnostics\engine\app-smoke-$engineLabel-$Mode-$stamp.json"
}
$absoluteReport = Resolve-UnresolvedPath $ReportPath
if (Test-Path -LiteralPath $absoluteReport) {
  throw "ReportPath already exists; preserve it or choose another path: $absoluteReport"
}
New-Item -ItemType Directory -Path (Split-Path -Parent $absoluteReport) `
  -Force | Out-Null

$process = [System.Diagnostics.Process]::new()
$process.StartInfo.FileName = $executable
$process.StartInfo.WorkingDirectory = $bundle
$process.StartInfo.UseShellExecute = $false
$process.StartInfo.CreateNoWindow = $false
$startedAt = (Get-Date).ToUniversalTime()
$inputIdle = $false
$mainWindowHandle = 0
$responding = $false
$exitedDuringObservation = $false
$closeRequested = $false
$gracefulExit = $false
$forcedCleanup = $false
$exitCode = $null
$failure = $null
$started = $false
$processId = $null
$startupPollCount = 0
$startupWindowWaitMilliseconds = 0
$closeWindowHandle = 0
$shutdownWaitMilliseconds = 0
try {
  if (-not $process.Start()) {
    throw 'Could not start Kirakara App.'
  }
  $started = $true
  $processId = $process.Id
  try {
    $inputIdle = $process.WaitForInputIdle($StartupTimeoutSeconds * 1000)
  } catch [System.InvalidOperationException] {
    $inputIdle = $false
  }
  if (-not $process.HasExited) {
    # WaitForInputIdle can complete before Flutter presents its first frame and
    # shows the top-level window. Discover it with a bounded startup probe; this
    # is test-only and never becomes an application timer.
    $windowStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    while (
      -not $process.HasExited -and
      $windowStopwatch.Elapsed.TotalSeconds -lt $StartupTimeoutSeconds
    ) {
      $process.Refresh()
      $mainWindowHandle = [long]$process.MainWindowHandle
      if ($mainWindowHandle -ne 0) {
        break
      }
      $startupPollCount++
      Start-Sleep -Milliseconds 100
    }
    $windowStopwatch.Stop()
    $startupWindowWaitMilliseconds = [long]$windowStopwatch.ElapsedMilliseconds
    if ($mainWindowHandle -ne 0) {
      $responding = $process.Responding
    }
    $exitedDuringObservation = $process.WaitForExit($ObserveSeconds * 1000)
  } else {
    $exitedDuringObservation = $true
  }
  if (-not $process.HasExited) {
    # A timed-out WaitForExit can leave Process properties cached. Refresh
    # before resolving the window used by CloseMainWindow; otherwise the smoke
    # harness can report a forced cleanup even though WM_CLOSE exits normally.
    $process.Refresh()
    $closeWindowHandle = [long]$process.MainWindowHandle
    $closeRequested = $process.CloseMainWindow()
    $shutdownStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $gracefulExit = $process.WaitForExit($ShutdownTimeoutSeconds * 1000)
    $shutdownStopwatch.Stop()
    $shutdownWaitMilliseconds = [long]$shutdownStopwatch.ElapsedMilliseconds
  }
  if (-not $process.HasExited) {
    $process.Kill()
    $process.WaitForExit()
    $forcedCleanup = $true
  }
  $exitCode = $process.ExitCode
} catch {
  $failure = $_.Exception.Message
  if ($started -and -not $process.HasExited) {
    $process.Kill()
    $process.WaitForExit()
    $forcedCleanup = $true
    $exitCode = $process.ExitCode
  }
} finally {
  $process.Dispose()
}

$passed = (
  [string]::IsNullOrWhiteSpace($failure) -and
  $inputIdle -and
  $mainWindowHandle -ne 0 -and
  $responding -and
  -not $exitedDuringObservation -and
  $closeRequested -and
  ($gracefulExit -or ($forcedCleanup -and $AllowForcedCleanup))
)
$report = [ordered]@{
  schemaVersion = 2
  generatedAt = (Get-Date).ToUniversalTime().ToString('o')
  startedAt = $startedAt.ToString('o')
  engine = $Engine
  localVariant = if ($Engine -eq 'local') { $LocalVariant } else { $null }
  mode = $Mode
  engineRevision = $lock.flutter.engineRevision
  patchsetRevision = if ($buildVariant -eq 'patched') {
    $lock.patchset.revision
  } else {
    'stock'
  }
  executable = $executable
  executableSha256 = (Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash
  flutterWindowsDllSha256 = (
    Get-FileHash -LiteralPath (Join-Path $bundle 'flutter_windows.dll') `
      -Algorithm SHA256
  ).Hash
  processId = $processId
  inputIdle = $inputIdle
  startupPollCount = $startupPollCount
  startupWindowWaitMilliseconds = $startupWindowWaitMilliseconds
  mainWindowHandle = $mainWindowHandle
  responding = $responding
  exitedDuringObservation = $exitedDuringObservation
  closeWindowHandle = $closeWindowHandle
  closeRequested = $closeRequested
  gracefulExit = $gracefulExit
  shutdownWaitMilliseconds = $shutdownWaitMilliseconds
  forcedCleanup = $forcedCleanup
  allowForcedCleanup = [bool]$AllowForcedCleanup
  exitCode = $exitCode
  failure = $failure
  passed = $passed
}
$report | ConvertTo-Json -Depth 5 | Set-Content `
  -LiteralPath $absoluteReport -Encoding utf8
Write-Host "App smoke report saved to $absoluteReport"

if (-not $passed) {
  throw "Kirakara App $Engine/$Mode smoke did not meet its gate. See $absoluteReport"
}
