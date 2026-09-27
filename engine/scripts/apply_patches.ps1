[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$WorkspaceRoot
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$lock = Get-EngineLock
$layout = Get-EngineWorkspaceLayout $WorkspaceRoot
Assert-ExternalEngineWorkspace $layout
Assert-PinnedFlutterSource -Lock $lock -Layout $layout -RequireStockTree

$patches = @($lock.patchset.patches)
if ($patches.Count -eq 0) {
  Write-Host 'Patchset is stock; no Engine behavior patches were applied.'
  exit 0
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
  Invoke-CheckedNative git @(
    '-C', $layout.FlutterCheckout, 'apply', '--check',
    '--whitespace=error-all', $patchPath
  ) "Patch preflight failed: $($patch.path)"
  Invoke-CheckedNative git @(
    '-C', $layout.FlutterCheckout, 'apply',
    '--whitespace=error-all', $patchPath
  ) "Patch application failed: $($patch.path)"
}

Write-Host "Applied patchset $($lock.patchset.revision) v$($lock.patchset.version)."
