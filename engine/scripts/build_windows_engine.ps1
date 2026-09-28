[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$WorkspaceRoot,

  [ValidateSet('debug', 'profile', 'release')]
  [string[]]$Mode = @('debug', 'profile', 'release'),

  [ValidateSet('stock', 'patched')]
  [string]$Variant = 'stock',

  [ValidateRange(0, 256)]
  [int]$Jobs = 0,

  [string]$ProxyUrl,

  [Parameter(Mandatory = $true)]
  [string]$VisualStudioPath,

  [string]$WindowsSdkPath = 'C:\Program Files (x86)\Windows Kits\10'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$lock = Get-EngineLock
$layout = Get-EngineWorkspaceLayout $WorkspaceRoot
Assert-ExternalEngineWorkspace $layout
Assert-WindowsSdkVersion -Lock $lock -WindowsSdkPath $WindowsSdkPath
Assert-VisualStudioVersion -Lock $lock -VisualStudioPath $VisualStudioPath
Assert-MsvcToolsetVersion -Lock $lock -VisualStudioPath $VisualStudioPath
if ($Variant -eq 'stock') {
  if ($layout.Kind -eq 'repository-local') {
    throw 'Repository-local bootstrap builds only the patched Engine. Use the pinned official Flutter SDK for the stock comparison.'
  }
  Assert-PinnedFlutterSource -Lock $lock -Layout $layout -RequireStockTree
} else {
  Assert-AppliedPatchset -Lock $lock -Layout $layout
}

Assert-PinnedDepotTools -Lock $lock -Layout $layout -RequireCleanTree

Set-EngineProcessEnvironment `
  -Layout $layout `
  -ProxyUrl $ProxyUrl `
  -VisualStudioPath $VisualStudioPath `
  -MsvcToolsetVersion $lock.hostBaseline.msvcToolsetVersion `
  -WindowsSdkPath $WindowsSdkPath

$et = Join-Path $layout.EngineSource 'flutter\bin\et.bat'
if ($Variant -eq 'stock' -and -not (
    Test-Path -LiteralPath $et -PathType Leaf
  )) {
  throw "Engine Tool is missing. Run fetch_engine.ps1 first: $et"
}
$gn = Join-Path $layout.EngineSource 'flutter\tools\gn.bat'
$autoninja = Join-Path $layout.DepotTools 'autoninja.bat'
if ($Variant -eq 'patched') {
  foreach ($required in @($gn, $autoninja)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
      throw "Patched Engine build tool is missing: $required"
    }
  }
}

Push-Location $layout.EngineSource
try {
  foreach ($buildMode in $Mode) {
    $build = Get-BuildLock `
      -Lock $lock `
      -Mode $buildMode `
      -Variant $Variant
    if ($Variant -eq 'stock') {
      $arguments = @($build.etArguments)
      if ($Jobs -gt 0) {
        $arguments += @('--concurrency', $Jobs.ToString())
      }
      Write-Host "Building stock Windows Engine mode '$buildMode' as '$($build.localEngine)'..."
      Invoke-CheckedNative $et $arguments `
        "Stock Engine build failed for mode '$buildMode'."
      continue
    }

    $gnArguments = @($build.gnArguments)
    $gnArguments += "--target-dir=$($build.localEngine)"
    if ($layout.Kind -eq 'repository-local') {
      # Flutter's GN wrapper accepts an alternate output root, but an absolute
      # Windows path leaks the drive-colon into generated snapshot paths. Keep
      # the argument relative to the Engine src directory; the resulting
      # output still resolves to the repository-local .kfe/out tree.
      $relativeOutputRoot = [IO.Path]::GetRelativePath(
        $layout.EngineSource,
        $layout.OutputRoot).Replace('\', '/')
      $gnArguments += "--out-dir=$relativeOutputRoot"
    }
    Write-Host "Generating patched Windows Engine mode '$buildMode' as '$($build.localEngine)'..."
    Invoke-CheckedNative $gn $gnArguments `
      "Patched Engine GN generation failed for mode '$buildMode'."

    $outputDirectory = Get-EngineOutputDirectory `
      -Layout $layout `
      -LocalEngine $build.localEngine
    $ninjaArguments = @('-C', $outputDirectory)
    if ($Jobs -gt 0) {
      $ninjaArguments += @('-j', $Jobs.ToString())
    }
    $ninjaArguments += @($build.ninjaTargets)
    Write-Host "Building patched Windows Engine mode '$buildMode'..."
    Invoke-CheckedNative $autoninja $ninjaArguments `
      "Patched Engine build failed for mode '$buildMode'."
  }
} finally {
  Pop-Location
}

Write-Host "Requested $Variant Engine builds completed."
