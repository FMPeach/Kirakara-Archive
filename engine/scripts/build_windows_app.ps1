[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$FlutterSdkRoot,

  [ValidateSet('official', 'local')]
  [string]$Engine = 'local',

  [string]$WorkspaceRoot,

  [ValidateSet('debug', 'profile', 'release')]
  [string[]]$Mode = @('debug', 'profile', 'release')
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$lock = Get-EngineLock
$flutterRoot = Resolve-UnresolvedPath $FlutterSdkRoot
$flutter = Join-Path $flutterRoot 'bin\flutter.bat'
if (-not (Test-Path -LiteralPath $flutter -PathType Leaf)) {
  throw "Flutter SDK is missing flutter.bat: $flutterRoot"
}

$frameworkHead = Get-GitHead $flutterRoot
if ($frameworkHead -ne $lock.flutter.frameworkRevision) {
  throw "Flutter Framework revision mismatch. Expected $($lock.flutter.frameworkRevision), got $frameworkHead."
}
$sdkEngineRevision = (
  Get-Content -Raw -LiteralPath (Join-Path $flutterRoot 'bin\internal\engine.version')
).Trim()
if ($sdkEngineRevision -ne $lock.flutter.engineRevision) {
  throw "Flutter SDK Engine revision mismatch. Expected $($lock.flutter.engineRevision), got $sdkEngineRevision."
}

$layout = $null
if ($Engine -eq 'local') {
  if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    throw '-WorkspaceRoot is required for -Engine local.'
  }
  $layout = Get-EngineWorkspaceLayout $WorkspaceRoot
  Assert-ExternalEngineWorkspace $layout
  Assert-PinnedFlutterSource `
    -Lock $lock `
    -Layout $layout `
    -RequireStockTree:($lock.patchset.patches.Count -eq 0)
}

function Get-OfficialEngineDirectory {
  param([Parameter(Mandatory = $true)][string]$BuildMode)

  $directoryName = switch ($BuildMode) {
    'debug' { 'windows-x64' }
    'profile' { 'windows-x64-profile' }
    'release' { 'windows-x64-release' }
  }
  return Join-Path $flutterRoot "bin\cache\artifacts\engine\$directoryName"
}

function Get-AppBundleDirectory {
  param([Parameter(Mandatory = $true)][string]$BuildMode)

  $configuration = switch ($BuildMode) {
    'debug' { 'Debug' }
    'profile' { 'Profile' }
    'release' { 'Release' }
  }
  return Join-Path (Get-AppRepositoryRoot) `
    "build\windows\x64\runner\$configuration"
}

Push-Location (Get-AppRepositoryRoot)
try {
  foreach ($buildMode in $Mode) {
    $build = Get-BuildLock -Lock $lock -Mode $buildMode
    $engineDirectory = if ($Engine -eq 'local') {
      Join-Path $layout.EngineSource "out\$($build.localEngine)"
    } else {
      Get-OfficialEngineDirectory -BuildMode $buildMode
    }
    if ($Engine -eq 'local') {
      Assert-LockedEngineArtifacts `
        -Build $build `
        -OutputDirectory $engineDirectory
    }

    $arguments = @('build', 'windows', "--$buildMode")
    if ($Engine -eq 'local') {
      $arguments += @(
        "--local-engine=$($build.localEngine)",
        "--local-engine-host=$($build.localEngineHost)",
        "--local-engine-src-path=$($layout.EngineSource)"
      )
    }
    Write-Host "Building Kirakara App mode '$buildMode' with '$Engine' Engine..."
    Invoke-CheckedNative $flutter $arguments `
      "Kirakara App build failed for mode '$buildMode' with '$Engine' Engine."

    $bundle = Get-AppBundleDirectory -BuildMode $buildMode
    Assert-MatchingFile `
      -ExpectedPath (Join-Path $engineDirectory 'flutter_windows.dll') `
      -ActualPath (Join-Path $bundle 'flutter_windows.dll') `
      -Label 'flutter_windows.dll'
    $icuDirectory = if ($Engine -eq 'local') {
      $engineDirectory
    } else {
      Join-Path $flutterRoot 'bin\cache\artifacts\engine\windows-x64'
    }
    Assert-MatchingFile `
      -ExpectedPath (Join-Path $icuDirectory 'icudtl.dat') `
      -ActualPath (Join-Path $bundle 'data\icudtl.dat') `
      -Label 'icudtl.dat'
    Write-Host "Verified App bundle uses the selected '$Engine' Engine for '$buildMode'."
  }
} finally {
  Pop-Location
}
