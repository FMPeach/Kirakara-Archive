[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$ShowRepository,

  [string]$FlutterExecutable = 'flutter'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$fixtureRoot = Join-Path $ShowRepository 'build\cast_fixtures'
$fixtures = [ordered]@{
  KIRAKARA_TEST_VIDEO = Join-Path $fixtureRoot 'video1.mp4'
  KIRAKARA_TEST_LYRIC = Join-Path $fixtureRoot 'krl1.krl'
  KIRAKARA_TEST_VOCAL = Join-Path $fixtureRoot 'vocal1.wav'
  KIRAKARA_TEST_ACCOMPANIMENT = Join-Path $fixtureRoot 'inst1.wav'
}
foreach ($fixture in $fixtures.Values) {
  if (-not (Test-Path -LiteralPath $fixture)) {
    throw "Missing Show fixture: $fixture"
  }
}

$flutter = (Get-Command $FlutterExecutable -ErrorAction Stop).Source
$arguments = @(
  'test',
  'integration_test\windows_stage_texture_baseline_test.dart',
  '-d',
  'windows'
)
foreach ($entry in $fixtures.GetEnumerator()) {
  $arguments += "--dart-define=$($entry.Key)=$($entry.Value)"
}

& $flutter @arguments
if ($LASTEXITCODE -ne 0) {
  throw "Windows Stage texture baseline failed with exit code $LASTEXITCODE."
}
