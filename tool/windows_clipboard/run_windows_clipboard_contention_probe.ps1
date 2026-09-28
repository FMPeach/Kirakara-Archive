[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$FlutterSdkRoot,

  [Parameter(Mandatory = $true)]
  [string]$WorkspaceRoot,

  [string]$LocalEngine = 'host_debug_kirakara_v4'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
. (Join-Path $repositoryRoot 'engine\scripts\common.ps1')

$lock = Get-EngineLock
$flutterRoot = Resolve-UnresolvedPath $FlutterSdkRoot
$flutter = Join-Path $flutterRoot 'bin\flutter.bat'
$layout = Get-EngineWorkspaceLayout $WorkspaceRoot
Assert-ExternalEngineWorkspace $layout
Assert-AppliedPatchset -Lock $lock -Layout $layout

$build = Get-BuildLock -Lock $lock -Mode debug -Variant patched
if ($LocalEngine -ne $build.localEngine) {
  throw "Clipboard Engine mismatch. Expected '$($build.localEngine)', got '$LocalEngine'."
}
$engineOutput = Join-Path $layout.EngineSource "out\$LocalEngine"
Assert-LockedEngineArtifacts -Build $build -OutputDirectory $engineOutput

Write-Warning (
  'This probe temporarily replaces the Windows clipboard and restores only ' +
  'its prior plain-text representation.'
)
Push-Location $repositoryRoot
try {
  & $flutter test `
    integration_test\windows_clipboard_baseline_test.dart `
    -d windows `
    "--local-engine=$LocalEngine" `
    "--local-engine-host=$LocalEngine" `
    "--local-engine-src-path=$($layout.EngineSource)" `
    --dart-define=KIRAKARA_ALLOW_CLIPBOARD_MUTATION=true `
    --dart-define=KIRAKARA_EXPECT_CLIPBOARD_RETRY=true
  if ($LASTEXITCODE -ne 0) {
    throw "Windows clipboard contention probe failed (exit $LASTEXITCODE)."
  }
} finally {
  Pop-Location
}

$bundleDll = Join-Path $repositoryRoot `
  'build\windows\x64\runner\Debug\flutter_windows.dll'
Assert-MatchingFile `
  -ExpectedPath (Join-Path $engineOutput 'flutter_windows.dll') `
  -ActualPath $bundleDll `
  -Label 'clipboard probe Engine DLL'

Write-Host 'Windows clipboard contention and interaction gates passed.'
