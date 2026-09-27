[CmdletBinding()]
param(
  [string]$FlutterExecutable = 'flutter'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$flutter = (Get-Command $FlutterExecutable -ErrorAction Stop).Source
Write-Warning (
  'This test temporarily replaces the Windows clipboard and can only ' +
  'restore its prior plain-text representation.'
)
& $flutter `
  test `
  integration_test\windows_clipboard_baseline_test.dart `
  -d windows `
  --dart-define=KIRAKARA_ALLOW_CLIPBOARD_MUTATION=true
if ($LASTEXITCODE -ne 0) {
  throw "Windows clipboard baseline failed with exit code $LASTEXITCODE."
}
