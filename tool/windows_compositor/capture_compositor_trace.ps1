[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$OutputPath,

  [ValidateRange(5, 120)]
  [int]$DurationSeconds = 20
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]$identity
$performanceLogUsers = [Security.Principal.SecurityIdentifier]'S-1-5-32-559'
$hasTracePrivilege =
  $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) -or
  $principal.IsInRole($performanceLogUsers)
if (-not $hasTracePrivilege) {
  throw @'
GPU/DWM WPR capture requires an elevated PowerShell (or membership in the
Performance Log Users group). Changing directory does not elevate the shell.
Open a new PowerShell with "Run as administrator", verify the elevation as
documented in phase0_trace_method.md, and run this command there.
'@
}

$targetProcesses = @(Get-Process -Name 'kirakara_app' -ErrorAction SilentlyContinue)
if ($targetProcesses.Count -eq 0) {
  throw @'
No kirakara_app.exe process is running. Start the debug/profile App with
KIRAKARA_COMPOSITOR_DIAGNOSTICS=1, load the documented preview scenario, and
only then start the WPR capture. A trace without the App cannot establish the
Show -> Flutter -> Present baseline.
'@
}

$wpr = (Get-Command wpr.exe -ErrorAction Stop).Source
$absoluteOutput =
  $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath(
    $OutputPath
  )
if ([System.IO.Path]::GetExtension($absoluteOutput) -ne '.etl') {
  throw 'OutputPath must end in .etl.'
}
if (Test-Path -LiteralPath $absoluteOutput) {
  throw "OutputPath already exists; preserve or remove it first: $absoluteOutput"
}

$outputDirectory = Split-Path -Parent $absoluteOutput
if (-not (Test-Path -LiteralPath $outputDirectory)) {
  New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}

$profileSource = Join-Path $PSScriptRoot 'kirakara_compositor_trace.wprp'
$profile = Join-Path ([System.IO.Path]::GetTempPath()) `
  "kirakara-compositor-$([guid]::NewGuid().ToString('N')).wprp"
$temporaryTrace = Join-Path ([System.IO.Path]::GetTempPath()) `
  "kirakara-compositor-$([guid]::NewGuid().ToString('N')).etl"
Copy-Item -LiteralPath $profileSource -Destination $profile

$started = $false
$preserveTemporaryTrace = $false
try {
  $targetProcessIds = ($targetProcesses.Id | Sort-Object) -join ', '
  Write-Host "Capturing kirakara_app.exe process ID(s): $targetProcessIds"
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

  # Some WPR builds reject a result path that traverses a junction. Let WPR
  # merge into its local temporary directory, then move the completed ETL to
  # the caller's requested path.
  & $wpr -stop $temporaryTrace
  if ($LASTEXITCODE -ne 0) {
    throw "WPR could not save the trace (exit code $LASTEXITCODE)."
  }
  $started = $false
  if (-not (Test-Path -LiteralPath $temporaryTrace)) {
    throw "WPR reported success but did not create: $temporaryTrace"
  }
  $temporaryTraceInfo = Get-Item -LiteralPath $temporaryTrace
  if ($temporaryTraceInfo.Length -eq 0) {
    throw "WPR created an empty trace: $temporaryTrace"
  }

  $preserveTemporaryTrace = $true
  try {
    Move-Item -LiteralPath $temporaryTrace -Destination $absoluteOutput
    $preserveTemporaryTrace = $false
  } catch {
    throw "WPR completed, but the trace could not be moved to '$absoluteOutput'. " +
      "The completed trace is preserved at '$temporaryTrace'. $($_.Exception.Message)"
  }
  Write-Host "Trace saved to $absoluteOutput"
} finally {
  if ($started) {
    & $wpr -cancel | Out-Null
  }
  Remove-Item -LiteralPath $profile -Force -ErrorAction SilentlyContinue
  if (-not $preserveTemporaryTrace) {
    Remove-Item -LiteralPath $temporaryTrace -Force -ErrorAction SilentlyContinue
  }
}
