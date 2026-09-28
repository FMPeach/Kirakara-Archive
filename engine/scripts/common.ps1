Set-StrictMode -Version Latest

function Resolve-UnresolvedPath {
  param([Parameter(Mandatory = $true)][string]$Path)

  return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath(
    $Path
  )
}

function Get-AppRepositoryRoot {
  return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
}

function Get-EngineLockPath {
  return Join-Path (Get-AppRepositoryRoot) 'engine\engine.lock.json'
}

function Get-EngineLock {
  $lockPath = Get-EngineLockPath
  if (-not (Test-Path -LiteralPath $lockPath -PathType Leaf)) {
    throw "Engine lock file is missing: $lockPath"
  }

  $lock = Get-Content -Raw -LiteralPath $lockPath | ConvertFrom-Json
  if ($lock.schemaVersion -ne 1) {
    throw "Unsupported engine lock schema: $($lock.schemaVersion)"
  }
  $patchsetProperty = $lock.PSObject.Properties['patchset']
  $patchset = if ($patchsetProperty) { $patchsetProperty.Value } else { $null }
  if (
    -not $patchset -or
    -not $patchset.PSObject.Properties['abiVersion'] -or
    -not $patchset.PSObject.Properties['version'] -or
    -not $patchset.PSObject.Properties['revision'] -or
    [uint32]$patchset.abiVersion -eq 0 -or
    [uint32]$patchset.version -eq 0 -or
    [string]::IsNullOrWhiteSpace([string]$patchset.revision)
  ) {
    throw 'engine.lock.json is missing the versioned Kirakara patchset contract.'
  }
  return $lock
}

function Get-EngineWorkspaceLayout {
  param([Parameter(Mandatory = $true)][string]$WorkspaceRoot)

  $root = Resolve-UnresolvedPath $WorkspaceRoot
  return [pscustomobject]@{
    Root = $root
    FlutterCheckout = Join-Path $root 'flutter'
    EngineSource = Join-Path $root 'flutter\engine\src'
    DepotTools = Join-Path $root 'depot_tools'
  }
}

function Test-PathWithin {
  param(
    [Parameter(Mandatory = $true)][string]$Candidate,
    [Parameter(Mandatory = $true)][string]$Parent
  )

  $candidateFull = [System.IO.Path]::GetFullPath($Candidate).TrimEnd('\', '/')
  $parentFull = [System.IO.Path]::GetFullPath($Parent).TrimEnd('\', '/')
  if ($candidateFull.Equals(
      $parentFull,
      [System.StringComparison]::OrdinalIgnoreCase
    )) {
    return $true
  }
  return $candidateFull.StartsWith(
    "$parentFull$([System.IO.Path]::DirectorySeparatorChar)",
    [System.StringComparison]::OrdinalIgnoreCase
  )
}

function Assert-ExternalEngineWorkspace {
  param([Parameter(Mandatory = $true)][pscustomobject]$Layout)

  $appRoot = Get-AppRepositoryRoot
  if (Test-PathWithin $Layout.Root $appRoot) {
    throw "Engine workspace must be outside the App repository: $($Layout.Root)"
  }

  if ($Layout.Root -match '^[A-Za-z]:\\?$') {
    throw "Refusing to use a drive root as the Engine workspace: $($Layout.Root)"
  }
}

function Invoke-CheckedNative {
  param(
    [Parameter(Mandatory = $true)][string]$FilePath,
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Arguments,
    [string]$FailureMessage = 'Native command failed.'
  )

  & $FilePath @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "$FailureMessage Exit code: $LASTEXITCODE"
  }
}

function Get-GitHead {
  param([Parameter(Mandatory = $true)][string]$Repository)

  $head = & git -C $Repository rev-parse HEAD
  if ($LASTEXITCODE -ne 0) {
    throw "Cannot read Git HEAD: $Repository"
  }
  return ($head | Select-Object -First 1).Trim()
}

function Get-GitTree {
  param([Parameter(Mandatory = $true)][string]$Repository)

  $tree = & git -C $Repository show -s '--format=%T' HEAD
  if ($LASTEXITCODE -ne 0) {
    throw "Cannot read Git tree: $Repository"
  }
  return ($tree | Select-Object -First 1).Trim()
}

function Get-TrackedGitChanges {
  param([Parameter(Mandatory = $true)][string]$Repository)

  $status = @(& git -C $Repository status --porcelain=v1 --untracked-files=no)
  if ($LASTEXITCODE -ne 0) {
    throw "Cannot read Git status: $Repository"
  }
  return @($status | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Assert-PinnedFlutterBootstrap {
  param(
    [Parameter(Mandatory = $true)]$Lock,
    [Parameter(Mandatory = $true)][pscustomobject]$Layout
  )

  if (-not (Test-Path -LiteralPath (Join-Path $Layout.FlutterCheckout '.git'))) {
    throw "Flutter bootstrap checkout is missing: $($Layout.FlutterCheckout)"
  }
  $bootstrapHead = Get-GitHead $Layout.FlutterCheckout
  if ($bootstrapHead -ne $Lock.flutter.engineRevision) {
    throw "Flutter bootstrap revision mismatch. Expected $($Lock.flutter.engineRevision), got $bootstrapHead."
  }
}

function Assert-PinnedFlutterSource {
  param(
    [Parameter(Mandatory = $true)]$Lock,
    [Parameter(Mandatory = $true)][pscustomobject]$Layout,
    [switch]$RequireStockTree
  )

  Assert-PinnedFlutterBootstrap -Lock $Lock -Layout $Layout

  $engineTree = Get-GitTree $Layout.FlutterCheckout
  if ($engineTree -ne $Lock.flutter.engineSourceTree) {
    throw "Engine source tree mismatch. Expected $($Lock.flutter.engineSourceTree), got $engineTree."
  }

  if ($RequireStockTree) {
    $changes = @(Get-TrackedGitChanges $Layout.FlutterCheckout)
    if ($changes.Count -ne 0) {
      throw "Stock Engine source has tracked changes:`n$($changes -join [Environment]::NewLine)"
    }
  }
}

function Assert-PinnedDepotTools {
  param(
    [Parameter(Mandatory = $true)]$Lock,
    [Parameter(Mandatory = $true)][pscustomobject]$Layout,
    [switch]$RequireCleanTree
  )

  if (-not (Test-Path -LiteralPath (Join-Path $Layout.DepotTools '.git'))) {
    throw "depot_tools checkout is missing: $($Layout.DepotTools)"
  }
  $head = Get-GitHead $Layout.DepotTools
  if ($head -ne $Lock.depotTools.revision) {
    throw "depot_tools revision mismatch. Expected $($Lock.depotTools.revision), got $head."
  }
  if ($RequireCleanTree) {
    $changes = @(Get-TrackedGitChanges $Layout.DepotTools)
    if ($changes.Count -ne 0) {
      throw "depot_tools has tracked changes:`n$($changes -join [Environment]::NewLine)"
    }
  }
}

function Get-BuildLock {
  param(
    [Parameter(Mandatory = $true)]$Lock,
    [Parameter(Mandatory = $true)][string]$Mode,
    [ValidateSet('stock', 'patched')]
    [string]$Variant = 'stock'
  )

  $builds = if ($Variant -eq 'stock') {
    @($Lock.builds)
  } else {
    @($Lock.patchset.builds)
  }
  $matches = @($builds | Where-Object { $_.mode -eq $Mode })
  if ($matches.Count -ne 1) {
    throw "Expected exactly one $Variant lock entry for build mode '$Mode'."
  }
  return $matches[0]
}

function Remove-TemporaryGitIndex {
  param([Parameter(Mandatory = $true)][string]$IndexPath)

  $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
  foreach ($candidate in @($IndexPath, "$IndexPath.lock")) {
    if (-not (Test-Path -LiteralPath $candidate)) {
      continue
    }
    $resolved = [IO.Path]::GetFullPath($candidate)
    if (-not $resolved.StartsWith(
        $tempRoot,
        [StringComparison]::OrdinalIgnoreCase
      )) {
      throw "Refusing to remove a temporary Git index outside the temp directory: $resolved"
    }
    Remove-Item -LiteralPath $resolved -Force
  }
}

function Get-PatchsetExpectedTree {
  param(
    [Parameter(Mandatory = $true)]$Lock,
    [Parameter(Mandatory = $true)][string]$Repository
  )

  $patches = @($Lock.patchset.patches)
  if ($patches.Count -eq 0) {
    throw 'The patched Engine variant has no locked patches.'
  }
  $indexPath = Join-Path ([IO.Path]::GetTempPath()) `
    "kirakara-engine-expected-$([guid]::NewGuid().ToString('N')).index"
  $previousIndex = [Environment]::GetEnvironmentVariable(
    'GIT_INDEX_FILE',
    'Process'
  )
  try {
    $env:GIT_INDEX_FILE = $indexPath
    Invoke-CheckedNative git @('-C', $Repository, 'read-tree', 'HEAD') `
      'Could not initialize the expected patch index.'
    foreach ($patch in $patches) {
      $patchPath = Join-Path (Get-AppRepositoryRoot) $patch.path
      if (-not (Test-Path -LiteralPath $patchPath -PathType Leaf)) {
        throw "Patch is missing: $patchPath"
      }
      $actualHash = (
        Get-FileHash -LiteralPath $patchPath -Algorithm SHA256
      ).Hash
      if ($actualHash -ne $patch.sha256) {
        throw "Patch hash mismatch for $($patch.path). Expected $($patch.sha256), got $actualHash."
      }
      Invoke-CheckedNative git @(
        '-C', $Repository, 'apply', '--cached', '--check',
        '--whitespace=error-all', $patchPath
      ) "Patch preflight failed: $($patch.path)"
      Invoke-CheckedNative git @(
        '-C', $Repository, 'apply', '--cached',
        '--whitespace=error-all', $patchPath
      ) "Could not build the expected tree for patch: $($patch.path)"
    }
    $tree = @(& git -C $Repository write-tree)
    if ($LASTEXITCODE -ne 0 -or $tree.Count -ne 1) {
      throw 'Could not compute the expected patched Engine tree.'
    }
    return $tree[0].Trim()
  } finally {
    if ($null -eq $previousIndex) {
      Remove-Item Env:GIT_INDEX_FILE -ErrorAction SilentlyContinue
    } else {
      $env:GIT_INDEX_FILE = $previousIndex
    }
    Remove-TemporaryGitIndex -IndexPath $indexPath
  }
}

function Get-WorkingTreeSnapshot {
  param([Parameter(Mandatory = $true)][string]$Repository)

  $indexPath = Join-Path ([IO.Path]::GetTempPath()) `
    "kirakara-engine-working-$([guid]::NewGuid().ToString('N')).index"
  $previousIndex = [Environment]::GetEnvironmentVariable(
    'GIT_INDEX_FILE',
    'Process'
  )
  try {
    $env:GIT_INDEX_FILE = $indexPath
    Invoke-CheckedNative git @('-C', $Repository, 'read-tree', 'HEAD') `
      'Could not initialize the working-tree snapshot index.'
    Invoke-CheckedNative git @('-C', $Repository, 'add', '-A', '--', '.') `
      'Could not snapshot the Engine working tree.'
    $tree = @(& git -C $Repository write-tree)
    if ($LASTEXITCODE -ne 0 -or $tree.Count -ne 1) {
      throw 'Could not compute the current Engine working-tree snapshot.'
    }
    return $tree[0].Trim()
  } finally {
    if ($null -eq $previousIndex) {
      Remove-Item Env:GIT_INDEX_FILE -ErrorAction SilentlyContinue
    } else {
      $env:GIT_INDEX_FILE = $previousIndex
    }
    Remove-TemporaryGitIndex -IndexPath $indexPath
  }
}

function Assert-AppliedPatchset {
  param(
    [Parameter(Mandatory = $true)]$Lock,
    [Parameter(Mandatory = $true)][pscustomobject]$Layout
  )

  Assert-PinnedFlutterSource -Lock $Lock -Layout $Layout
  $expectedTree = Get-PatchsetExpectedTree `
    -Lock $Lock `
    -Repository $Layout.FlutterCheckout
  $lockedTree = [string]$Lock.patchset.sourceTree
  if (
    -not [string]::IsNullOrWhiteSpace($lockedTree) -and
    $expectedTree -ne $lockedTree
  ) {
    throw "Locked patchset tree mismatch. Expected $lockedTree, patches produce $expectedTree."
  }
  $workingTree = Get-WorkingTreeSnapshot -Repository $Layout.FlutterCheckout
  if ($workingTree -ne $expectedTree) {
    $status = @(& git -C $Layout.FlutterCheckout status --short)
    throw (
      "Engine working tree does not exactly match the locked patchset. " +
      "Expected tree $expectedTree, got $workingTree.`n$($status -join [Environment]::NewLine)"
    )
  }
}

function Assert-LockedEngineArtifacts {
  param(
    [Parameter(Mandatory = $true)]$Build,
    [Parameter(Mandatory = $true)][string]$OutputDirectory
  )

  foreach ($artifact in $Build.artifacts) {
    $lockedHash = [string]$artifact.sha256
    if ([string]::IsNullOrWhiteSpace($lockedHash)) {
      throw "Engine artifact is not locked: $($Build.mode)/$($artifact.path)"
    }
    $artifactPath = Join-Path $OutputDirectory $artifact.path
    if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
      throw "Locked Engine artifact is missing: $artifactPath"
    }
    $item = Get-Item -LiteralPath $artifactPath
    if ([long]$item.Length -ne [long]$artifact.size) {
      throw "Engine artifact size mismatch for $($Build.mode)/$($artifact.path). Expected $($artifact.size), got $($item.Length)."
    }
    $actualHash = (
      Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256
    ).Hash
    if ($actualHash -ne $lockedHash) {
      throw "Engine artifact hash mismatch for $($Build.mode)/$($artifact.path). Expected $lockedHash, got $actualHash."
    }
  }
}

function Assert-MatchingFile {
  param(
    [Parameter(Mandatory = $true)][string]$ExpectedPath,
    [Parameter(Mandatory = $true)][string]$ActualPath,
    [Parameter(Mandatory = $true)][string]$Label
  )

  if (-not (Test-Path -LiteralPath $ExpectedPath -PathType Leaf)) {
    throw "Expected $Label is missing: $ExpectedPath"
  }
  if (-not (Test-Path -LiteralPath $ActualPath -PathType Leaf)) {
    throw "Actual $Label is missing: $ActualPath"
  }
  $expectedHash = (Get-FileHash -LiteralPath $ExpectedPath -Algorithm SHA256).Hash
  $actualHash = (Get-FileHash -LiteralPath $ActualPath -Algorithm SHA256).Hash
  if ($expectedHash -ne $actualHash) {
    throw "$Label mismatch. Expected $expectedHash, got $actualHash."
  }
}

function Assert-MatchingTextFile {
  param(
    [Parameter(Mandatory = $true)][string]$ExpectedPath,
    [Parameter(Mandatory = $true)][string]$ActualPath,
    [Parameter(Mandatory = $true)][string]$Label
  )

  if (-not (Test-Path -LiteralPath $ExpectedPath -PathType Leaf)) {
    throw "Expected $Label is missing: $ExpectedPath"
  }
  if (-not (Test-Path -LiteralPath $ActualPath -PathType Leaf)) {
    throw "Actual $Label is missing: $ActualPath"
  }
  $expected = [IO.File]::ReadAllText($ExpectedPath).Replace("`r`n", "`n")
  $actual = [IO.File]::ReadAllText($ActualPath).Replace("`r`n", "`n")
  if ($expected -cne $actual) {
    throw "$Label content mismatch. Keep the Runner ABI header synchronized with the patched Engine source."
  }
}

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
      # Flush redirected output before reading the asynchronous tasks.
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

function Set-EngineProcessEnvironment {
  param(
    [Parameter(Mandatory = $true)][pscustomobject]$Layout,
    [string]$ProxyUrl,
    [string]$VisualStudioPath,
    [string]$MsvcToolsetVersion,
    [string]$WindowsSdkPath
  )

  $env:DEPOT_TOOLS_UPDATE = '0'
  $env:DEPOT_TOOLS_WIN_TOOLCHAIN = '0'
  $env:Path = "$($Layout.DepotTools);$env:Path"
  if (-not [string]::IsNullOrWhiteSpace($ProxyUrl)) {
    $env:HTTP_PROXY = $ProxyUrl
    $env:HTTPS_PROXY = $ProxyUrl
  }
  if (-not [string]::IsNullOrWhiteSpace($VisualStudioPath)) {
    $env:GYP_MSVS_OVERRIDE_PATH = Resolve-UnresolvedPath $VisualStudioPath
  }
  if (-not [string]::IsNullOrWhiteSpace($MsvcToolsetVersion)) {
    $env:VCToolsVersion = $MsvcToolsetVersion
  }
  if (-not [string]::IsNullOrWhiteSpace($WindowsSdkPath)) {
    $env:WINDOWSSDKDIR = Resolve-UnresolvedPath $WindowsSdkPath
  }
}

function Assert-MsvcToolsetVersion {
  param(
    [Parameter(Mandatory = $true)]$Lock,
    [Parameter(Mandatory = $true)][string]$VisualStudioPath
  )

  $visualStudio = Resolve-UnresolvedPath $VisualStudioPath
  $version = [string]$Lock.hostBaseline.msvcToolsetVersion
  if ([string]::IsNullOrWhiteSpace($version)) {
    throw 'engine.lock.json does not pin an MSVC toolset version.'
  }
  $toolset = Join-Path $visualStudio "VC\Tools\MSVC\$version"
  $cl = Join-Path $toolset 'bin\Hostx64\x64\cl.exe'
  $requiredPaths = @(
    (Join-Path $toolset 'include'),
    (Join-Path $toolset 'lib\x64'),
    (Join-Path $toolset 'atlmfc\include\atlbase.h'),
    (Join-Path $toolset 'atlmfc\lib\x64\atls.lib'),
    $cl,
    (Join-Path $toolset 'bin\Hostx64\x64\link.exe')
  )
  $missing = @($requiredPaths | Where-Object {
      -not (Test-Path -LiteralPath $_)
    })
  if ($missing.Count -ne 0) {
    throw "The pinned Engine requires MSVC $version. Missing:`n$($missing -join [Environment]::NewLine)"
  }
  $compilerVersion = (Get-Item -LiteralPath $cl).VersionInfo.FileVersion
  if ($compilerVersion -ne [string]$Lock.hostBaseline.msvcCompilerVersion) {
    throw "MSVC compiler version mismatch. Expected $($Lock.hostBaseline.msvcCompilerVersion), got $compilerVersion."
  }
}

function Assert-WindowsSdkVersion {
  param(
    [Parameter(Mandatory = $true)]$Lock,
    [Parameter(Mandatory = $true)][string]$WindowsSdkPath
  )

  $sdkRoot = Resolve-UnresolvedPath $WindowsSdkPath
  $version = [string]$Lock.hostBaseline.engineBuildWindowsSdkVersion
  $requiredPaths = @(
    (Join-Path $sdkRoot "Include\$version\um"),
    (Join-Path $sdkRoot "Include\$version\ucrt"),
    (Join-Path $sdkRoot "Lib\$version\um\x64"),
    (Join-Path $sdkRoot "Lib\$version\ucrt\x64"),
    (Join-Path $sdkRoot "bin\$version\x64")
  )
  $missing = @($requiredPaths | Where-Object {
      -not (Test-Path -LiteralPath $_ -PathType Container)
    })
  if ($missing.Count -ne 0) {
    throw "The pinned Engine requires Windows SDK $version. Missing:`n$($missing -join [Environment]::NewLine)"
  }
}

function Assert-WindowsAppPerMonitorV2 {
  param(
    [Parameter(Mandatory = $true)]$Lock,
    [Parameter(Mandatory = $true)][string]$Executable,
    [Parameter(Mandatory = $true)][string]$WindowsSdkPath
  )

  $executablePath = Resolve-UnresolvedPath $Executable
  if (-not (Test-Path -LiteralPath $executablePath -PathType Leaf)) {
    throw "Windows App executable is missing: $executablePath"
  }
  $sdkRoot = Resolve-UnresolvedPath $WindowsSdkPath
  $sdkVersion = [string]$Lock.hostBaseline.engineBuildWindowsSdkVersion
  $manifestTool = Join-Path $sdkRoot "bin\$sdkVersion\x64\mt.exe"
  if (-not (Test-Path -LiteralPath $manifestTool -PathType Leaf)) {
    throw "The pinned Windows manifest tool is missing: $manifestTool"
  }

  $manifestPath = Join-Path ([IO.Path]::GetTempPath()) `
    "kirakara-app-manifest-$([Guid]::NewGuid().ToString('N')).xml"
  try {
    $arguments = @(
      '-nologo',
      "-inputresource:$executablePath;#1",
      "-out:$manifestPath"
    )
    $output = @(& $manifestTool @arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
      throw "Could not extract the Windows App manifest from $executablePath.`n$($output -join [Environment]::NewLine)"
    }
    [xml]$manifest = Get-Content -Raw -LiteralPath $manifestPath
    $dpiAwareness = $manifest.SelectSingleNode(
      "//*[local-name()='dpiAwareness']"
    )
    if ($null -eq $dpiAwareness) {
      throw "Windows App manifest has no dpiAwareness element: $executablePath"
    }
    $value = $dpiAwareness.InnerText.Trim()
    if ($value -cne 'PerMonitorV2') {
      throw "Windows App manifest must embed PerMonitorV2, got '$value': $executablePath"
    }
  } finally {
    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
      Remove-Item -LiteralPath $manifestPath -Force
    }
  }
}

function Assert-VisualStudioVersion {
  param(
    [Parameter(Mandatory = $true)]$Lock,
    [Parameter(Mandatory = $true)][string]$VisualStudioPath
  )

  $installPath = Resolve-UnresolvedPath $VisualStudioPath
  if (-not (Test-Path -LiteralPath $installPath -PathType Container)) {
    throw "Visual Studio installation is missing: $installPath"
  }
  $vswhere = Join-Path ${env:ProgramFiles(x86)} `
    'Microsoft Visual Studio\Installer\vswhere.exe'
  if (-not (Test-Path -LiteralPath $vswhere -PathType Leaf)) {
    throw "Visual Studio Installer is missing vswhere.exe: $vswhere"
  }

  $versionOutput = @(& $vswhere `
      -path $installPath -property installationVersion)
  $versionExitCode = $LASTEXITCODE
  $version = ($versionOutput | Select-Object -First 1).Trim()
  if ($versionExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($version)) {
    throw "Cannot identify Visual Studio installation: $installPath"
  }
  if ($version -ne [string]$Lock.hostBaseline.visualStudioVersion) {
    throw "Visual Studio version mismatch. Expected $($Lock.hostBaseline.visualStudioVersion), got $version."
  }

  $productOutput = @(& $vswhere -path $installPath -property displayName)
  $productExitCode = $LASTEXITCODE
  $product = ($productOutput | Select-Object -First 1).Trim()
  if ($productExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($product)) {
    throw "Cannot identify Visual Studio product: $installPath"
  }
  if ($product -ne [string]$Lock.hostBaseline.visualStudioProduct) {
    throw "Visual Studio product mismatch. Expected $($Lock.hostBaseline.visualStudioProduct), got $product."
  }
}
