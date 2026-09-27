[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$OutputPath,

  [ValidateRange(5, 120)]
  [int]$DurationSeconds = 20
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$wpr = (Get-Command wpr.exe -ErrorAction Stop).Source
$absoluteOutput = [System.IO.Path]::GetFullPath($OutputPath)
if ([System.IO.Path]::GetExtension($absoluteOutput) -ne '.etl') {
  throw 'OutputPath must end in .etl.'
}

$outputDirectory = Split-Path -Parent $absoluteOutput
if (-not (Test-Path -LiteralPath $outputDirectory)) {
  New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}

$profileSource = Join-Path $PSScriptRoot 'kirakara_compositor_trace.wprp'
$profile = Join-Path ([System.IO.Path]::GetTempPath()) `
  "kirakara-compositor-$([guid]::NewGuid().ToString('N')).wprp"
Copy-Item -LiteralPath $profileSource -Destination $profile

$started = $false
try {
  & $wpr `
    -start GPU.Light `
    -start DesktopComposition.Light `
    -start "$profile!KirakaraCompositor.Verbose" `
    -filemode
  if ($LASTEXITCODE -ne 0) {
    throw "WPR could not start (exit code $LASTEXITCODE)."
  }
  $started = $true

  Write-Host "Capturing for $DurationSeconds seconds. Exercise exactly one documented scenario now."
  Start-Sleep -Seconds $DurationSeconds

  & $wpr -stop $absoluteOutput
  if ($LASTEXITCODE -ne 0) {
    throw "WPR could not save the trace (exit code $LASTEXITCODE)."
  }
  $started = $false
  Write-Host "Trace saved to $absoluteOutput"
} finally {
  if ($started) {
    & $wpr -cancel | Out-Null
  }
  Remove-Item -LiteralPath $profile -Force -ErrorAction SilentlyContinue
}
