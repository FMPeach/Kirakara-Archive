[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$WorkspaceRoot,

  [ValidateSet('critical', 'compositor', 'adapter-isolated', 'full')]
  [string[]]$Suite = @('critical', 'compositor', 'adapter-isolated'),

  [ValidateRange(1, 1800)]
  [int]$TimeoutSeconds = 360,

  [string]$ReportPath,

  [switch]$AllowKnownFullSuiteOrderFailures
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

function Invoke-GTestProcess {
  param(
    [Parameter(Mandatory = $true)][string]$Executable,
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Filter,
    [Parameter(Mandatory = $true)][int]$ExpectedTestCount,
    [Parameter(Mandatory = $true)][string]$LogDirectory,
    [Parameter(Mandatory = $true)][int]$TimeoutSeconds
  )

  $stdoutPath = Join-Path $LogDirectory "$Name.stdout.txt"
  $stderrPath = Join-Path $LogDirectory "$Name.stderr.txt"
  $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
  $startInfo.FileName = $Executable
  $startInfo.Arguments = "--gtest_color=no --gtest_filter=$Filter"
  $startInfo.UseShellExecute = $false
  $startInfo.CreateNoWindow = $true
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true

  $process = [System.Diagnostics.Process]::new()
  $process.StartInfo = $startInfo
  $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
  try {
    if (-not $process.Start()) {
      throw "Could not start Windows Engine tests: $Name"
    }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $completed = $process.WaitForExit($TimeoutSeconds * 1000)
    if (-not $completed) {
      $process.Kill()
      $process.WaitForExit()
    } else {
      # Flush asynchronous stdout/stderr handlers before reading the tasks.
      $process.WaitForExit()
    }
    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    $exitCode = if ($completed) { $process.ExitCode } else { $null }
  } finally {
    $stopwatch.Stop()
    $process.Dispose()
  }

  Set-Content -LiteralPath $stdoutPath -Value $stdout -Encoding utf8
  Set-Content -LiteralPath $stderrPath -Value $stderr -Encoding utf8
  $failedTests = @([regex]::Matches(
      $stdout,
      '(?m)^\[\s+FAILED\s+\]\s+([^\s]+)(?:\s+\(\d+ ms\))?\s*$'
    ) | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
  $countMatches = @([regex]::Matches(
      $stdout,
      '(?m)^\[==========\]\s+Running\s+(\d+)\s+tests?\s+from\s+'
    ))
  $testCount = if ($countMatches.Count -eq 1) {
    [int]$countMatches[0].Groups[1].Value
  } else {
    $null
  }

  return [ordered]@{
    name = $Name
    filter = $Filter
    timedOut = -not $completed
    timeoutSeconds = $TimeoutSeconds
    durationMilliseconds = [long]$stopwatch.ElapsedMilliseconds
    exitCode = $exitCode
    expectedTestCount = $ExpectedTestCount
    testCount = $testCount
    failedTests = $failedTests
    stdout = $stdoutPath
    stderr = $stderrPath
  }
}

$lock = Get-EngineLock
$layout = Get-EngineWorkspaceLayout $WorkspaceRoot
Assert-ExternalEngineWorkspace $layout
Assert-PinnedFlutterSource `
  -Lock $lock `
  -Layout $layout `
  -RequireStockTree:($lock.patchset.patches.Count -eq 0)

$debugBuild = Get-BuildLock -Lock $lock -Mode 'debug'
$debugOutput = Join-Path $layout.EngineSource "out\$($debugBuild.localEngine)"
Assert-LockedEngineArtifacts -Build $debugBuild -OutputDirectory $debugOutput
$testExecutable = Join-Path $debugOutput 'flutter_windows_unittests.exe'
if (-not (Test-Path -LiteralPath $testExecutable -PathType Leaf)) {
  throw "Windows Engine unit test executable is missing: $testExecutable"
}

if ([string]::IsNullOrWhiteSpace($ReportPath)) {
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $ReportPath = Join-Path (Get-AppRepositoryRoot) `
    "build\diagnostics\engine\stock-engine-tests-$stamp.json"
}
$absoluteReport = Resolve-UnresolvedPath $ReportPath
if (Test-Path -LiteralPath $absoluteReport) {
  throw "ReportPath already exists; preserve it or choose another path: $absoluteReport"
}
$reportDirectory = Split-Path -Parent $absoluteReport
$logDirectory = Join-Path $reportDirectory `
  ([System.IO.Path]::GetFileNameWithoutExtension($absoluteReport) + '-logs')
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null

$definitions = [ordered]@{
  critical = @(
    [ordered]@{
      name = 'critical'
      filter = 'FlutterWindowsEngineTest.TaskRunnerDelayedTask:WindowsTest.NextFrameCallback'
      expectedTestCount = 2
    }
  )
  compositor = @(
    [ordered]@{
      name = 'compositor'
      filter = 'CompositorOpenGLTest.*:CompositorSoftwareTest.*:DisplayManagerWin32Test.*:DpiUtilsTest.*:FlutterWindowsTextureRegistrarTest.*'
      expectedTestCount = 25
    }
  )
  'adapter-isolated' = @(
    [ordered]@{
      name = 'adapter-low-power-isolated'
      filter = 'WindowsTest.GetGraphicsAdapterWithLowPowerPreference'
      expectedTestCount = 1
    },
    [ordered]@{
      name = 'engine-adapter-low-power-isolated'
      filter = 'WindowsTest.GetEngineGraphicsAdapterWithLowPowerPreference'
      expectedTestCount = 1
    }
  )
  full = @(
    [ordered]@{
      name = 'full'
      filter = '*'
      expectedTestCount = 354
    }
  )
}

$requestedSuites = @($Suite | Select-Object -Unique)
if (
  $AllowKnownFullSuiteOrderFailures -and
  $requestedSuites -contains 'full' -and
  $requestedSuites -notcontains 'adapter-isolated'
) {
  throw '-AllowKnownFullSuiteOrderFailures requires -Suite adapter-isolated,full so the isolated controls are recorded in the same report.'
}
$runs = @()
foreach ($suiteName in $requestedSuites) {
  foreach ($definition in $definitions[$suiteName]) {
    Write-Host "Running stock Windows Engine test suite '$($definition.name)'..."
    $runs += Invoke-GTestProcess `
      -Executable $testExecutable `
      -Name $definition.name `
      -Filter $definition.filter `
      -ExpectedTestCount $definition.expectedTestCount `
      -LogDirectory $logDirectory `
      -TimeoutSeconds $TimeoutSeconds
  }
}

$knownFullSuiteFailures = @(
  'WindowsTest.GetEngineGraphicsAdapterWithLowPowerPreference',
  'WindowsTest.GetGraphicsAdapterWithLowPowerPreference'
)
$unexpectedRuns = @()
foreach ($run in $runs) {
  $acceptedKnownFailure = $false
  if (
    $run.name -eq 'full' -and
    $AllowKnownFullSuiteOrderFailures -and
    -not $run.timedOut -and
    $run.exitCode -eq 1
  ) {
    $difference = @(Compare-Object `
        -ReferenceObject $knownFullSuiteFailures `
        -DifferenceObject @($run.failedTests))
    $acceptedKnownFailure = $difference.Count -eq 0
  }
  $run.acceptedKnownOrderDependentFailures = $acceptedKnownFailure
  if (
    $run.timedOut -or
    $run.testCount -ne $run.expectedTestCount -or
    ($run.exitCode -ne 0 -and -not $acceptedKnownFailure)
  ) {
    $unexpectedRuns += $run.name
  }
}

$report = [ordered]@{
  schemaVersion = 1
  generatedAt = (Get-Date).ToUniversalTime().ToString('o')
  engineRevision = Get-GitHead $layout.FlutterCheckout
  engineSourceTree = Get-GitTree $layout.FlutterCheckout
  patchsetRevision = $lock.patchset.revision
  debugEngine = $debugBuild.localEngine
  testExecutable = $testExecutable
  testExecutableSha256 = (
    Get-FileHash -LiteralPath $testExecutable -Algorithm SHA256
  ).Hash
  requestedSuites = $requestedSuites
  allowKnownFullSuiteOrderFailures = [bool]$AllowKnownFullSuiteOrderFailures
  knownFullSuiteOrderFailures = $knownFullSuiteFailures
  runs = $runs
  allProcessesExitedZero = @($runs | Where-Object {
      $_.timedOut -or $_.testCount -ne $_.expectedTestCount -or $_.exitCode -ne 0
    }).Count -eq 0
  gatePassed = $unexpectedRuns.Count -eq 0
}
$report | ConvertTo-Json -Depth 8 | Set-Content `
  -LiteralPath $absoluteReport -Encoding utf8
Write-Host "Windows Engine test report saved to $absoluteReport"

if ($unexpectedRuns.Count -ne 0) {
  throw "Windows Engine test run failed or timed out: $($unexpectedRuns -join ', ')"
}
