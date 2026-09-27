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
    [Parameter(Mandatory = $true)][string]$Mode
  )

  $matches = @($Lock.builds | Where-Object { $_.mode -eq $Mode })
  if ($matches.Count -ne 1) {
    throw "Expected exactly one lock entry for build mode '$Mode'."
  }
  return $matches[0]
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
