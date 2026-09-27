[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$WorkspaceRoot,

  [ValidateSet('debug', 'profile', 'release')]
  [string[]]$Mode = @('debug', 'profile', 'release'),

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
Assert-PinnedFlutterSource `
  -Lock $lock `
  -Layout $layout `
  -RequireStockTree:($lock.patchset.patches.Count -eq 0)

Assert-PinnedDepotTools -Lock $lock -Layout $layout -RequireCleanTree

Set-EngineProcessEnvironment `
  -Layout $layout `
  -ProxyUrl $ProxyUrl `
  -VisualStudioPath $VisualStudioPath `
  -MsvcToolsetVersion $lock.hostBaseline.msvcToolsetVersion `
  -WindowsSdkPath $WindowsSdkPath

$et = Join-Path $layout.EngineSource 'flutter\bin\et.bat'
if (-not (Test-Path -LiteralPath $et -PathType Leaf)) {
  throw "Engine Tool is missing. Run fetch_engine.ps1 first: $et"
}

Push-Location $layout.EngineSource
try {
  foreach ($buildMode in $Mode) {
    $build = Get-BuildLock -Lock $lock -Mode $buildMode
    $arguments = @($build.etArguments)
    if ($Jobs -gt 0) {
      $arguments += @('--concurrency', $Jobs.ToString())
    }
    Write-Host "Building stock Windows Engine mode '$buildMode' as '$($build.localEngine)'..."
    Invoke-CheckedNative $et $arguments "Engine build failed for mode '$buildMode'."
  }
} finally {
  Pop-Location
}

Write-Host 'Requested stock Engine builds completed.'
