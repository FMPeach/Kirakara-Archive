[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$WorkspaceRoot,

  [ValidateSet('stock', 'patched')]
  [string]$Variant = 'patched'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$lock = Get-EngineLock
$layout = Get-EngineWorkspaceLayout $WorkspaceRoot
Assert-ExternalEngineWorkspace $layout

$patchsetPatches = @($lock.patchset.patches)
$bootstrapPatches = if ($layout.Kind -eq 'repository-local') {
  @($lock.projectBootstrap.engineSourcePatches)
} else {
  @()
}
$patches = @($patchsetPatches) + @($bootstrapPatches)
if ($patches.Count -eq 0) {
  Assert-PinnedFlutterSource -Lock $lock -Layout $layout -RequireStockTree
  Write-Host 'The lock has no Engine behavior patches; source is stock.'
  exit 0
}

if ($Variant -eq 'patched') {
  try {
    Assert-PinnedFlutterSource -Lock $lock -Layout $layout -RequireStockTree
  } catch {
    if ($layout.Kind -ne 'repository-local' -or
        $bootstrapPatches.Count -eq 0) {
      throw
    }
    Assert-AppliedPatchset `
      -Lock $lock `
      -Layout $layout `
      -ExcludeRepositoryBootstrap
    $patches = @($bootstrapPatches)
    Write-Host 'The compositor patchset is already applied; adding the locked repository-local bootstrap patch.'
  }
} else {
  Assert-AppliedPatchset -Lock $lock -Layout $layout
  [array]::Reverse($patches)
}

$appRoot = Get-AppRepositoryRoot
foreach ($patch in $patches) {
  $patchPath = Join-Path $appRoot $patch.path
  if (-not (Test-Path -LiteralPath $patchPath -PathType Leaf)) {
    throw "Patch is missing: $patchPath"
  }
  $actualHash = (Get-FileHash -LiteralPath $patchPath -Algorithm SHA256).Hash
  if ($actualHash -ne $patch.sha256) {
    throw "Patch hash mismatch for $($patch.path). Expected $($patch.sha256), got $actualHash."
  }
  $direction = if ($Variant -eq 'stock') { @('--reverse') } else { @() }
  $preflightArguments = @('-C', $layout.FlutterCheckout, 'apply')
  $preflightArguments += $direction
  $preflightArguments += @('--check', '--whitespace=error-all', $patchPath)
  Invoke-CheckedNative git $preflightArguments `
    "Patch $Variant preflight failed: $($patch.path)"
  $applyArguments = @('-C', $layout.FlutterCheckout, 'apply')
  $applyArguments += $direction
  $applyArguments += @('--whitespace=error-all', $patchPath)
  Invoke-CheckedNative git $applyArguments `
    "Patch $Variant transition failed: $($patch.path)"
}

if ($Variant -eq 'patched') {
  Assert-AppliedPatchset -Lock $lock -Layout $layout
  Write-Host "Applied patchset $($lock.patchset.revision) v$($lock.patchset.version)."
} else {
  Assert-PinnedFlutterSource -Lock $lock -Layout $layout -RequireStockTree
  Write-Host 'Reversed the locked patchset; Engine source is stock.'
}
