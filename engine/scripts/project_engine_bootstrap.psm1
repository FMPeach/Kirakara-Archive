Set-StrictMode -Version Latest

$script:RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
. (Join-Path $PSScriptRoot 'common.ps1')

function Get-KirakaraProjectLayout {
  $layout = Get-EngineWorkspaceLayout (Join-Path $script:RepositoryRoot '.kfe')
  Assert-ExternalEngineWorkspace $layout
  if ($layout.Kind -ne 'repository-local') {
    throw 'The Kirakara project Engine layout was not recognized as repository-local.'
  }
  return $layout
}

function Resolve-KirakaraCanonicalDirectoryPath {
  param([Parameter(Mandatory = $true)][string]$Path)

  $currentPath = [IO.Path]::GetFullPath((Resolve-UnresolvedPath $Path))
  foreach ($pass in 0..15) {
    $pathRoot = [IO.Path]::GetPathRoot($currentPath)
    $relative = $currentPath.Substring($pathRoot.Length)
    $segments = @($relative.Split(
        @([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar),
        [StringSplitOptions]::RemoveEmptyEntries))
    $resolved = $pathRoot
    $changed = $false
    foreach ($segment in $segments) {
      $candidate = Join-Path $resolved $segment
      $item = Get-Item -LiteralPath $candidate -Force
      if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) {
        $resolved = $candidate
        continue
      }
      $targets = @($item.Target)
      if ($targets.Count -ne 1 -or
          [string]::IsNullOrWhiteSpace([string]$targets[0])) {
        throw "Cannot resolve repository reparse point: $candidate"
      }
      $target = [string]$targets[0]
      if ($target.StartsWith('\??\')) {
        $target = $target.Substring(4)
      }
      if (-not [IO.Path]::IsPathRooted($target)) {
        $target = Join-Path (Split-Path -Parent $candidate) $target
      }
      $resolved = [IO.Path]::GetFullPath($target)
      $changed = $true
    }
    $resolved = [IO.Path]::GetFullPath($resolved)
    if (-not $changed -or $resolved.Equals(
        $currentPath, [StringComparison]::OrdinalIgnoreCase)) {
      return $resolved
    }
    $currentPath = $resolved
  }
  throw "Repository reparse-point chain is too deep: $Path"
}

function Get-KirakaraModeFromArguments {
  param(
    [Parameter(Mandatory = $true)][string[]]$Arguments,
    [Parameter(Mandatory = $true)]
    [ValidateSet('debug', 'release')]
    [string]$DefaultMode
  )

  $modes = [System.Collections.Generic.List[string]]::new()
  foreach ($argument in $Arguments) {
    switch ($argument) {
      '--debug' { $modes.Add('debug') }
      '--profile' { $modes.Add('profile') }
      '--release' { $modes.Add('release') }
    }
  }
  $selected = @($modes | Sort-Object -Unique)
  if ($selected.Count -gt 1) {
    throw "Conflicting Flutter build modes: $($selected -join ', ')."
  }
  if ($selected.Count -eq 1) {
    return $selected[0]
  }
  return $DefaultMode
}

function Get-KirakaraDeviceId {
  param([Parameter(Mandatory = $true)][string[]]$Arguments)

  for ($index = 0; $index -lt $Arguments.Count; $index++) {
    $argument = $Arguments[$index]
    if ($argument -in @('-d', '--device-id')) {
      if ($index + 1 -ge $Arguments.Count) {
        throw "$argument requires a device id."
      }
      return $Arguments[$index + 1]
    }
    if ($argument -match '^(?:-d|--device-id)=(.+)$') {
      return $Matches[1]
    }
  }
  return $null
}

function Get-KirakaraFlutterInvocationPlan {
  param([Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Arguments)

  $commandIndex = -1
  $command = $null
  for ($index = 0; $index -lt $Arguments.Count; $index++) {
    if ($Arguments[$index] -in @('pub', 'run', 'build')) {
      $commandIndex = $index
      $command = $Arguments[$index]
      break
    }
  }

  $needsEngine = $false
  $injectEngine = $false
  $mode = $null
  $reason = 'Flutter command does not require the custom Windows Engine.'
  if ($command -eq 'pub') {
    $subcommand = if ($commandIndex + 1 -lt $Arguments.Count) {
      $Arguments[$commandIndex + 1]
    } else { $null }
    if ($subcommand -eq 'get') {
      $needsEngine = $true
      $mode = 'debug'
      $reason = 'First pub get prepares the debug Engine for the next development run.'
    }
  } elseif ($command -eq 'run') {
    $deviceId = Get-KirakaraDeviceId -Arguments $Arguments
    if ($null -eq $deviceId -or $deviceId -eq 'windows') {
      $needsEngine = $true
      $injectEngine = $true
      $mode = Get-KirakaraModeFromArguments `
        -Arguments $Arguments `
        -DefaultMode debug
      $reason = 'Windows run requires the matching custom Engine mode.'
    } else {
      $reason = "Explicit non-Windows device '$deviceId' uses the official Flutter Engine."
    }
  } elseif ($command -eq 'build') {
    $subcommand = if ($commandIndex + 1 -lt $Arguments.Count) {
      $Arguments[$commandIndex + 1]
    } else { $null }
    if ($subcommand -eq 'windows') {
      $needsEngine = $true
      $injectEngine = $true
      $mode = Get-KirakaraModeFromArguments `
        -Arguments $Arguments `
        -DefaultMode release
      $reason = 'Windows build requires the matching custom Engine mode.'
    }
  }

  if ($needsEngine) {
    $conflicting = @($Arguments | Where-Object {
        $_ -match '^--local-(?:engine|engine-host|engine-src-path)(?:=|$)'
      })
    if ($conflicting.Count -ne 0) {
      throw (
        'flutterw owns local Engine selection; remove explicit flags: ' +
        ($conflicting -join ', ')
      )
    }
  }

  return [pscustomobject]@{
    command = $command
    needsEngine = $needsEngine
    injectEngine = $injectEngine
    mode = $mode
    reason = $reason
  }
}

function Set-KirakaraGitProcessConfiguration {
  $existingCount = 0
  $rawCount = [Environment]::GetEnvironmentVariable('GIT_CONFIG_COUNT', 'Process')
  if (-not [string]::IsNullOrWhiteSpace($rawCount)) {
    if (-not [int]::TryParse($rawCount, [ref]$existingCount)) {
      throw "Invalid process GIT_CONFIG_COUNT: $rawCount"
    }
  }
  for ($index = 0; $index -lt $existingCount; $index++) {
    $key = [Environment]::GetEnvironmentVariable(
      "GIT_CONFIG_KEY_$index", 'Process')
    if ($key -eq 'core.longpaths') {
      return
    }
  }
  [Environment]::SetEnvironmentVariable(
    "GIT_CONFIG_KEY_$existingCount", 'core.longpaths', 'Process')
  [Environment]::SetEnvironmentVariable(
    "GIT_CONFIG_VALUE_$existingCount", 'true', 'Process')
  [Environment]::SetEnvironmentVariable(
    'GIT_CONFIG_COUNT', ($existingCount + 1).ToString(), 'Process')
}

function Get-KirakaraOfficialEngineDirectoryName {
  param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('debug', 'profile', 'release')]
    [string]$Mode
  )

  switch ($Mode) {
    'debug' { return 'windows-x64' }
    'profile' { return 'windows-x64-profile' }
    'release' { return 'windows-x64-release' }
  }
}

function Assert-KirakaraPinnedFlutterSdk {
  param(
    [Parameter(Mandatory = $true)][string]$SdkRoot,
    [Parameter(Mandatory = $true)]$Lock,
    [ValidateSet('debug', 'profile', 'release')]
    [string]$RequiredMode = 'debug'
  )

  $root = Resolve-UnresolvedPath $SdkRoot
  $flutter = Join-Path $root 'bin\flutter.bat'
  if (-not (Test-Path -LiteralPath $flutter -PathType Leaf)) {
    throw "Flutter SDK is missing flutter.bat: $root"
  }
  if (-not (Test-Path -LiteralPath (Join-Path $root '.git'))) {
    throw "Flutter SDK must retain its Git metadata for revision validation: $root"
  }
  $frameworkHead = Get-GitHead $root
  if ($frameworkHead -ne [string]$Lock.flutter.frameworkRevision) {
    throw "Flutter Framework revision mismatch at '$root'. Expected $($Lock.flutter.frameworkRevision), got $frameworkHead."
  }
  $engineVersionPath = Join-Path $root 'bin\internal\engine.version'
  if (-not (Test-Path -LiteralPath $engineVersionPath -PathType Leaf)) {
    throw "Flutter SDK is missing engine.version: $engineVersionPath"
  }
  $engineRevision = (Get-Content -Raw -LiteralPath $engineVersionPath).Trim()
  if ($engineRevision -ne [string]$Lock.flutter.engineRevision) {
    throw "Flutter SDK Engine revision mismatch at '$root'. Expected $($Lock.flutter.engineRevision), got $engineRevision."
  }
  $dart = Join-Path $root 'bin\cache\dart-sdk\bin\dart.exe'
  if (-not (Test-Path -LiteralPath $dart -PathType Leaf)) {
    throw "Flutter SDK has not bootstrapped its locked Dart SDK: $dart"
  }
  $officialDirectory = Join-Path $root (
    'bin\cache\artifacts\engine\' +
    (Get-KirakaraOfficialEngineDirectoryName -Mode $RequiredMode)
  )
  $officialDll = Join-Path $officialDirectory 'flutter_windows.dll'
  if (-not (Test-Path -LiteralPath $officialDll -PathType Leaf)) {
    throw "Flutter SDK has not precached the official $RequiredMode Windows Engine: $officialDll"
  }
  return $root
}

function Get-KirakaraPathFlutterSdk {
  $command = Get-Command flutter.bat, flutter -ErrorAction SilentlyContinue |
    Select-Object -First 1
  if ($null -eq $command) {
    return $null
  }
  $bin = Split-Path -Parent $command.Source
  return Split-Path -Parent $bin
}

function Initialize-KirakaraLocalFlutterSdk {
  param(
    [Parameter(Mandatory = $true)][pscustomobject]$Layout,
    [Parameter(Mandatory = $true)]$Lock,
    [Parameter(Mandatory = $true)]
    [ValidateSet('debug', 'profile', 'release')]
    [string]$RequiredMode
  )

  $sdk = $Layout.FlutterSdk
  New-Item -ItemType Directory -Path $Layout.Root -Force | Out-Null
  $null = Repair-InterruptedManagedGitCheckout `
    -Path $sdk `
    -ManagedRoot $Layout.Root `
    -Repository ([string]$Lock.flutter.repository) `
    -Revision ([string]$Lock.flutter.frameworkRevision) `
    -Label 'project Flutter SDK'
  if (Test-Path -LiteralPath $sdk) {
    $changes = @(Get-TrackedGitChanges $sdk)
    if ($changes.Count -ne 0) {
      throw "Project Flutter SDK has tracked changes and will not be overwritten:`n$($changes -join [Environment]::NewLine)"
    }
  } else {
    Write-Host '[Kirakara Engine] Cloning the locked official Flutter SDK into .kfe/sdk...'
    Invoke-CheckedNative git @(
      'clone', '--filter=blob:none', '--no-checkout',
      [string]$Lock.flutter.repository, $sdk
    ) 'Could not clone the locked Flutter SDK.' | Out-Host
  }

  Invoke-CheckedNative git @(
    '-C', $sdk, 'fetch', '--depth=1', 'origin',
    [string]$Lock.flutter.frameworkRevision
  ) 'Could not fetch the locked Flutter Framework revision.' | Out-Host
  Invoke-CheckedNative git @(
    '-C', $sdk, 'checkout', '--detach',
    [string]$Lock.flutter.frameworkRevision
  ) 'Could not check out the locked Flutter Framework revision.' | Out-Host

  $flutter = Join-Path $sdk 'bin\flutter.bat'
  Write-Host '[Kirakara Engine] Precaching the official Windows Flutter artifacts inside .kfe/sdk...'
  Invoke-CheckedNative $flutter @('precache', '--windows') `
    'Could not precache the official Windows Flutter artifacts.' | Out-Host
  return Assert-KirakaraPinnedFlutterSdk `
    -SdkRoot $sdk `
    -Lock $Lock `
    -RequiredMode $RequiredMode
}

function Resolve-KirakaraFlutterSdk {
  param(
    [Parameter(Mandatory = $true)][pscustomobject]$Layout,
    [Parameter(Mandatory = $true)]$Lock,
    [Parameter(Mandatory = $true)]
    [ValidateSet('debug', 'profile', 'release')]
    [string]$RequiredMode,
    [switch]$NoInstall
  )

  $explicit = [Environment]::GetEnvironmentVariable(
    'KIRAKARA_FLUTTER_SDK_ROOT', 'Process')
  if (-not [string]::IsNullOrWhiteSpace($explicit)) {
    return [pscustomobject]@{
      root = Assert-KirakaraPinnedFlutterSdk `
        -SdkRoot $explicit -Lock $Lock -RequiredMode $RequiredMode
      source = 'explicit process environment'
      repositoryLocal = (Test-PathWithin $explicit $Layout.Root)
    }
  }

  $candidates = @()
  $pathSdk = Get-KirakaraPathFlutterSdk
  if (-not [string]::IsNullOrWhiteSpace($pathSdk)) {
    $candidates += [pscustomobject]@{ source = 'PATH'; root = $pathSdk }
  }
  if (Test-Path -LiteralPath $Layout.FlutterSdk -PathType Container) {
    $candidates += [pscustomobject]@{ source = '.kfe/sdk'; root = $Layout.FlutterSdk }
  }

  foreach ($candidate in $candidates) {
    try {
      $root = Assert-KirakaraPinnedFlutterSdk `
        -SdkRoot $candidate.root `
        -Lock $Lock `
        -RequiredMode $RequiredMode
      return [pscustomobject]@{
        root = $root
        source = $candidate.source
        repositoryLocal = (Test-PathWithin $root $Layout.Root)
      }
    } catch {
      Write-Warning "Ignoring $($candidate.source) Flutter SDK: $($_.Exception.Message)"
    }
  }

  if ($NoInstall) {
    throw 'No complete Flutter SDK matches engine.lock.json. A normal flutterw invocation would prepare .kfe/sdk.'
  }
  $handle = Enter-KirakaraBootstrapLock -Layout $Layout
  try {
    if (Test-Path -LiteralPath $Layout.FlutterSdk -PathType Container) {
      try {
        $root = Assert-KirakaraPinnedFlutterSdk `
          -SdkRoot $Layout.FlutterSdk `
          -Lock $Lock `
          -RequiredMode $RequiredMode
        return [pscustomobject]@{
          root = $root
          source = '.kfe/sdk (prepared by another process)'
          repositoryLocal = $true
        }
      } catch {
        Write-Warning (
          'The project Flutter SDK still needs preparation after acquiring ' +
          "the bootstrap lock: $($_.Exception.Message)")
      }
    }
    $null = Assert-KirakaraBootstrapPreflight -Layout $Layout -Lock $Lock
    $root = Initialize-KirakaraLocalFlutterSdk `
      -Layout $Layout `
      -Lock $Lock `
      -RequiredMode $RequiredMode
  } finally {
    Exit-KirakaraBootstrapLock -Handle $handle
  }
  return [pscustomobject]@{
    root = $root
    source = '.kfe/sdk (prepared)'
    repositoryLocal = $true
  }
}

function Get-KirakaraPinnedVisualStudioPath {
  param([Parameter(Mandatory = $true)]$Lock)

  $vswhere = Join-Path ${env:ProgramFiles(x86)} `
    'Microsoft Visual Studio\Installer\vswhere.exe'
  if (-not (Test-Path -LiteralPath $vswhere -PathType Leaf)) {
    throw "Visual Studio Installer is missing vswhere.exe: $vswhere"
  }
  $json = @(& $vswhere -format json -products '*') -join [Environment]::NewLine
  if ($LASTEXITCODE -ne 0) {
    throw 'Could not enumerate Visual Studio installations.'
  }
  $matches = @($json | ConvertFrom-Json | Where-Object {
      $_.displayName -eq [string]$Lock.hostBaseline.visualStudioProduct -and
      $_.installationVersion -eq [string]$Lock.hostBaseline.visualStudioVersion
    })
  if ($matches.Count -ne 1) {
    throw (
      'Expected exactly one pinned Visual Studio installation: ' +
      "$($Lock.hostBaseline.visualStudioProduct) " +
      "$($Lock.hostBaseline.visualStudioVersion). Found $($matches.Count)."
    )
  }
  $path = [string]$matches[0].installationPath
  Assert-VisualStudioVersion -Lock $Lock -VisualStudioPath $path
  Assert-MsvcToolsetVersion -Lock $Lock -VisualStudioPath $path
  return $path
}

function Assert-KirakaraBootstrapPreflight {
  param(
    [Parameter(Mandatory = $true)][pscustomobject]$Layout,
    [Parameter(Mandatory = $true)]$Lock,
    [string]$WindowsSdkPath = 'C:\Program Files (x86)\Windows Kits\10'
  )

  foreach ($command in @('git', 'pwsh')) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
      throw "Required command is missing from PATH: $command"
    }
  }
  $bootstrap = $Lock.PSObject.Properties['projectBootstrap']
  if ($null -eq $bootstrap -or $bootstrap.Value.schemaVersion -ne 1) {
    throw 'engine.lock.json has no supported projectBootstrap contract.'
  }
  if ([string]$bootstrap.Value.workspace -ne '.kfe') {
    throw "Unsupported project bootstrap workspace: $($bootstrap.Value.workspace)"
  }
  $rootPath = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Layout.Root))
  $drive = [IO.DriveInfo]::new($rootPath)
  $minimum = [long]$bootstrap.Value.minimumFreeSpaceBytes
  if ($drive.AvailableFreeSpace -lt $minimum) {
    $requiredGiB = [math]::Round($minimum / 1GB, 1)
    $availableGiB = [math]::Round($drive.AvailableFreeSpace / 1GB, 1)
    throw "Repository-local Engine bootstrap requires at least $requiredGiB GiB free on $rootPath; only $availableGiB GiB is available."
  }
  Assert-WindowsSdkVersion -Lock $Lock -WindowsSdkPath $WindowsSdkPath
  $visualStudio = Get-KirakaraPinnedVisualStudioPath -Lock $Lock
  return [pscustomobject]@{
    visualStudioPath = $visualStudio
    windowsSdkPath = Resolve-UnresolvedPath $WindowsSdkPath
    availableFreeBytes = [long]$drive.AvailableFreeSpace
    minimumFreeBytes = $minimum
  }
}

function Get-KirakaraSha256Text {
  param([Parameter(Mandatory = $true)][string]$Text)

  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    $hash = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))
    return ([BitConverter]::ToString($hash)).Replace('-', '')
  } finally {
    $sha.Dispose()
  }
}

function Get-KirakaraBootstrapFingerprint {
  param(
    [Parameter(Mandatory = $true)]$Lock,
    [Parameter(Mandatory = $true)]
    [ValidateSet('debug', 'profile', 'release')]
    [string]$Mode
  )

  $relativeFiles = [System.Collections.Generic.List[string]]::new()
  foreach ($path in @(
      'engine/engine.lock.json',
      'engine/include/kirakara_flutter_compositor_api.h',
      'engine/scripts/common.ps1',
      'engine/scripts/fetch_engine.ps1',
      'engine/scripts/apply_patches.ps1',
      'engine/scripts/build_windows_engine.ps1',
      'engine/scripts/verify_engine_bundle.ps1',
      'engine/scripts/test_engine_abi_gate.ps1',
      'engine/scripts/project_engine_bootstrap.psm1',
      'flutterw.ps1',
      'flutterw.cmd'
    )) {
    $relativeFiles.Add($path)
  }
  foreach ($patch in @($Lock.patchset.patches)) {
    if (-not $relativeFiles.Contains([string]$patch.path)) {
      $relativeFiles.Add([string]$patch.path)
    }
  }
  foreach ($patch in @($Lock.projectBootstrap.engineSourcePatches)) {
    if (-not $relativeFiles.Contains([string]$patch.path)) {
      $relativeFiles.Add([string]$patch.path)
    }
  }
  $bootstrapPatch = [string]$Lock.projectBootstrap.vpythonVirtualenv.patch
  if (-not $relativeFiles.Contains($bootstrapPatch)) {
    $relativeFiles.Add($bootstrapPatch)
  }
  $fileHashes = [ordered]@{}
  foreach ($relative in @($relativeFiles | Sort-Object)) {
    $path = Join-Path $script:RepositoryRoot $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
      throw "Bootstrap fingerprint input is missing: $path"
    }
    $fileHashes[$relative] = (
      Get-FileHash -LiteralPath $path -Algorithm SHA256
    ).Hash
  }
  $build = Get-BuildLock -Lock $Lock -Mode $Mode -Variant patched
  $inputs = [ordered]@{
    schemaVersion = 1
    mode = $Mode
    frameworkRevision = [string]$Lock.flutter.frameworkRevision
    engineRevision = [string]$Lock.flutter.engineRevision
    engineSourceTree = [string]$Lock.flutter.engineSourceTree
    patchsetSourceTree = [string]$Lock.patchset.sourceTree
    repositoryLocalEngineSourceTree = [string]$Lock.projectBootstrap.engineSourceTree
    patchsetVersion = [uint32]$Lock.patchset.version
    abiVersion = [uint32]$Lock.patchset.abiVersion
    localEngine = [string]$build.localEngine
    gnArguments = @($build.gnArguments)
    ninjaTargets = @($build.ninjaTargets)
    visualStudioVersion = [string]$Lock.hostBaseline.visualStudioVersion
    msvcToolsetVersion = [string]$Lock.hostBaseline.msvcToolsetVersion
    msvcCompilerVersion = [string]$Lock.hostBaseline.msvcCompilerVersion
    windowsSdkVersion = [string]$Lock.hostBaseline.engineBuildWindowsSdkVersion
    targetOs = [string]$Lock.target.os
    targetArchitecture = [string]$Lock.target.architecture
    files = $fileHashes
  }
  $canonical = $inputs | ConvertTo-Json -Depth 10 -Compress
  return [pscustomobject]@{
    value = Get-KirakaraSha256Text -Text $canonical
    inputs = $inputs
  }
}

function Repair-KirakaraVpythonVirtualenv {
  param(
    [Parameter(Mandatory = $true)][pscustomobject]$Layout,
    [Parameter(Mandatory = $true)]$Lock
  )

  $contract = $Lock.projectBootstrap.vpythonVirtualenv
  $store = Join-Path $Layout.Cache 'vpython\store'
  $candidates = @()
  if (Test-Path -LiteralPath $store -PathType Container) {
    foreach ($package in @(Get-ChildItem -LiteralPath $store -Directory `
        -Filter 'virtualenv+*')) {
      $candidate = Join-Path $package.FullName (
        "contents\virtualenv-$($contract.version)\virtualenv.py")
      if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        $candidates += $candidate
      }
    }
  }
  if ($candidates.Count -ne 1) {
    throw "Expected exactly one pinned vpython virtualenv $($contract.version) script, found $($candidates.Count) under $store."
  }

  $target = $candidates[0]
  $actualHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
  if ($actualHash -eq [string]$contract.patchedSha256) {
    return
  }
  if ($actualHash -ne [string]$contract.sourceSha256) {
    throw (
      "Pinned vpython virtualenv source hash mismatch. Expected " +
      "$($contract.sourceSha256) or already-patched $($contract.patchedSha256), " +
      "got ${actualHash}: $target"
    )
  }

  $patchPath = Join-Path $script:RepositoryRoot ([string]$contract.patch)
  if (-not (Test-Path -LiteralPath $patchPath -PathType Leaf)) {
    throw "Pinned vpython compatibility patch is missing: $patchPath"
  }
  $patchHash = (Get-FileHash -LiteralPath $patchPath -Algorithm SHA256).Hash
  if ($patchHash -ne [string]$contract.patchSha256) {
    throw "Pinned vpython compatibility patch hash mismatch. Expected $($contract.patchSha256), got $patchHash."
  }
  $targetDirectory = Split-Path -Parent $target
  $relativeDirectory = [IO.Path]::GetRelativePath(
    $script:RepositoryRoot, $targetDirectory).Replace('\', '/')
  if ($relativeDirectory.StartsWith('../') -or
      [IO.Path]::IsPathRooted($relativeDirectory)) {
    throw "Refusing to patch vpython outside the App repository: $target"
  }
  Write-Host (
    '[Kirakara Engine] Applying the locked Windows code-page fix to the ' +
    'project-local vpython virtualenv...'
  )
  Invoke-CheckedNative git @(
    '-C', $script:RepositoryRoot,
    'apply', '--check', "--directory=$relativeDirectory", $patchPath
  ) 'vpython compatibility patch preflight failed.' | Out-Host
  Invoke-CheckedNative git @(
    '-C', $script:RepositoryRoot,
    'apply', "--directory=$relativeDirectory", $patchPath
  ) 'Could not apply the vpython compatibility patch.' | Out-Host
  $patchedHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
  if ($patchedHash -ne [string]$contract.patchedSha256) {
    throw "Patched vpython virtualenv hash mismatch. Expected $($contract.patchedSha256), got $patchedHash."
  }
}

function Get-KirakaraReadyStampPath {
  param(
    [Parameter(Mandatory = $true)][pscustomobject]$Layout,
    [Parameter(Mandatory = $true)][string]$Mode
  )
  return Join-Path $Layout.State "$Mode-ready.json"
}

function Test-KirakaraReadyStamp {
  param(
    [Parameter(Mandatory = $true)][pscustomobject]$Layout,
    [Parameter(Mandatory = $true)]$Lock,
    [Parameter(Mandatory = $true)][string]$Mode,
    [Parameter(Mandatory = $true)][string]$Fingerprint
  )

  $stampPath = Get-KirakaraReadyStampPath -Layout $Layout -Mode $Mode
  if (-not (Test-Path -LiteralPath $stampPath -PathType Leaf)) {
    return [pscustomobject]@{ ready = $false; reason = 'ready stamp is missing' }
  }
  try {
    $stamp = Get-Content -Raw -LiteralPath $stampPath | ConvertFrom-Json
    if ($stamp.schemaVersion -ne 1) {
      throw "unsupported ready stamp schema $($stamp.schemaVersion)"
    }
    if ($stamp.mode -ne $Mode) {
      throw "ready stamp mode is '$($stamp.mode)'"
    }
    if ($stamp.fingerprint -ne $Fingerprint) {
      throw 'bootstrap fingerprint changed'
    }
    $build = Get-BuildLock -Lock $Lock -Mode $Mode -Variant patched
    $output = Get-EngineOutputDirectory `
      -Layout $Layout `
      -LocalEngine $build.localEngine
    $expectedArtifacts = @($build.artifacts | ForEach-Object {
        [string]$_.path
      } | Sort-Object)
    $stampArtifacts = @($stamp.artifacts)
    $stampArtifactPaths = @($stampArtifacts | ForEach-Object {
        [string]$_.path
      } | Sort-Object)
    if ($stampArtifactPaths.Count -ne $expectedArtifacts.Count -or
        @(Compare-Object $expectedArtifacts $stampArtifactPaths).Count -ne 0) {
      throw 'ready stamp artifact set does not match engine.lock.json'
    }
    if (@($stampArtifactPaths | Sort-Object -Unique).Count -ne
        $stampArtifactPaths.Count) {
      throw 'ready stamp contains duplicate artifact paths'
    }
    if ([string]$stamp.argsGnSha256 -ne [string]$build.argsGnSha256) {
      throw 'ready stamp GN arguments do not match engine.lock.json'
    }
    foreach ($artifact in $stampArtifacts) {
      $path = Join-Path $output ([string]$artifact.path)
      if (-not (Test-PathWithin $path $output)) {
        throw "artifact path escapes Engine output: $($artifact.path)"
      }
      if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "artifact is missing: $($artifact.path)"
      }
      $item = Get-Item -LiteralPath $path
      if ([long]$item.Length -ne [long]$artifact.size) {
        throw "artifact size changed: $($artifact.path)"
      }
      $shouldVerifyHash = -not ([string]$artifact.path).EndsWith(
        '.pdb', [StringComparison]::OrdinalIgnoreCase)
      if ([bool]$artifact.verifyHash -ne $shouldVerifyHash) {
        throw "artifact hash policy changed: $($artifact.path)"
      }
      if ($shouldVerifyHash) {
        $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        if ($hash -ne [string]$artifact.sha256) {
          throw "artifact hash changed: $($artifact.path)"
        }
      }
    }
    $argsGn = Join-Path $output 'args.gn'
    if (-not (Test-Path -LiteralPath $argsGn -PathType Leaf)) {
      throw 'args.gn is missing'
    }
    $argsHash = (Get-FileHash -LiteralPath $argsGn -Algorithm SHA256).Hash
    if ($argsHash -ne [string]$stamp.argsGnSha256) {
      throw 'args.gn changed'
    }
    Assert-AppliedPatchset -Lock $Lock -Layout $Layout
    Assert-PinnedDepotTools -Lock $Lock -Layout $Layout -RequireCleanTree
    return [pscustomobject]@{ ready = $true; reason = 'all ready-stamp gates passed' }
  } catch {
    return [pscustomobject]@{ ready = $false; reason = $_.Exception.Message }
  }
}

function Enter-KirakaraBootstrapLock {
  param([Parameter(Mandatory = $true)][pscustomobject]$Layout)

  New-Item -ItemType Directory -Path $Layout.Locks -Force | Out-Null
  $canonicalRoot = Resolve-KirakaraCanonicalDirectoryPath `
    -Path $script:RepositoryRoot
  $identity = Get-KirakaraSha256Text -Text $canonicalRoot.ToUpperInvariant()
  $mutex = [Threading.Mutex]::new($false, "Local\KirakaraEngine-$($identity.Substring(0, 24))")
  $acquired = $false
  try {
    Write-Host '[Kirakara Engine] Waiting for the repository bootstrap lock...'
    try {
      $acquired = $mutex.WaitOne([TimeSpan]::FromHours(6))
    } catch [Threading.AbandonedMutexException] {
      $acquired = $true
    }
    if (-not $acquired) {
      throw 'Timed out waiting for the repository bootstrap lock after six hours.'
    }
    $ownerPath = Join-Path $Layout.Locks 'owner.json'
    [ordered]@{
      schemaVersion = 1
      processId = $PID
      acquiredAt = (Get-Date).ToUniversalTime().ToString('o')
    } | ConvertTo-Json | Set-Content -LiteralPath $ownerPath -Encoding utf8
    return [pscustomobject]@{
      mutex = $mutex
      ownerPath = $ownerPath
      acquired = $true
    }
  } catch {
    if ($acquired) {
      $mutex.ReleaseMutex()
    }
    $mutex.Dispose()
    throw
  }
}

function Exit-KirakaraBootstrapLock {
  param([Parameter(Mandatory = $true)]$Handle)

  if ($Handle.acquired) {
    if (Test-Path -LiteralPath $Handle.ownerPath -PathType Leaf) {
      Remove-Item -LiteralPath $Handle.ownerPath -Force
    }
    $Handle.mutex.ReleaseMutex()
  }
  $Handle.mutex.Dispose()
}

function Assert-KirakaraEngineSourceReady {
  param(
    [Parameter(Mandatory = $true)][pscustomobject]$Layout,
    [Parameter(Mandatory = $true)]$Lock,
    [Parameter(Mandatory = $true)][string]$VisualStudioPath,
    [Parameter(Mandatory = $true)][string]$WindowsSdkPath,
    [string]$ProxyUrl
  )

  $sourcePresent = Test-Path -LiteralPath (
    Join-Path $Layout.FlutterCheckout '.git')
  $depotPresent = Test-Path -LiteralPath (Join-Path $Layout.DepotTools '.git')
  $patched = $false
  $patchsetOnly = $false
  $stock = $false
  if ($sourcePresent) {
    try {
      Assert-AppliedPatchset -Lock $Lock -Layout $Layout
      $patched = $true
    } catch {
      try {
        Assert-PinnedFlutterSource -Lock $Lock -Layout $Layout -RequireStockTree
        $stock = $true
      } catch {
        try {
          Assert-AppliedPatchset `
            -Lock $Lock `
            -Layout $Layout `
            -ExcludeRepositoryBootstrap
          $patchsetOnly = $true
        } catch {
          throw (
            'Repository-local Engine source is neither the locked stock tree nor ' +
            "the exact patchset. Refusing to reset it automatically.`n$($_.Exception.Message)"
          )
        }
      }
    }
  }

  $dependencyMarkers = @(
    (Join-Path $Layout.EngineSource 'flutter\tools\gn.bat'),
    (Join-Path $Layout.EngineSource 'flutter\buildtools\windows-x64\clang\bin\llvm-readobj.exe'),
    (Join-Path $Layout.DepotTools 'autoninja.bat')
  )
  $dependenciesPresent = $depotPresent -and @(
    $dependencyMarkers | Where-Object {
      -not (Test-Path -LiteralPath $_ -PathType Leaf)
    }
  ).Count -eq 0

  if (-not $sourcePresent -or -not $dependenciesPresent) {
    if ($patchsetOnly) {
      Write-Host '[Kirakara Engine] Completing the repository-local source patch before dependency synchronization...'
      & (Join-Path $PSScriptRoot 'apply_patches.ps1') `
        -WorkspaceRoot $Layout.Root `
        -Variant patched | Out-Host
      $patched = $true
      $patchsetOnly = $false
    }
    if ($patched) {
      Write-Host '[Kirakara Engine] Temporarily reversing the exact patchset before gclient sync...'
      & (Join-Path $PSScriptRoot 'apply_patches.ps1') `
        -WorkspaceRoot $Layout.Root `
        -Variant stock | Out-Host
      $patched = $false
      $stock = $true
    }
    Write-Host '[Kirakara Engine] Fetching and synchronizing the locked Engine source...'
    & (Join-Path $PSScriptRoot 'fetch_engine.ps1') `
      -WorkspaceRoot $Layout.Root `
      -ProxyUrl $ProxyUrl `
      -VisualStudioPath $VisualStudioPath `
      -WindowsSdkPath $WindowsSdkPath | Out-Host
    $stock = $true
  }

  if (-not $patched) {
    if (-not $stock -and -not $patchsetOnly) {
      Assert-PinnedFlutterSource -Lock $Lock -Layout $Layout -RequireStockTree
    }
    Write-Host '[Kirakara Engine] Applying the locked Kirakara patch stack...'
    & (Join-Path $PSScriptRoot 'apply_patches.ps1') `
      -WorkspaceRoot $Layout.Root `
      -Variant patched | Out-Host
  }
  Assert-AppliedPatchset -Lock $Lock -Layout $Layout
  Assert-PinnedDepotTools -Lock $Lock -Layout $Layout -RequireCleanTree
}

function Write-KirakaraReadyStamp {
  param(
    [Parameter(Mandatory = $true)][pscustomobject]$Layout,
    [Parameter(Mandatory = $true)]$Lock,
    [Parameter(Mandatory = $true)][string]$Mode,
    [Parameter(Mandatory = $true)]$Fingerprint,
    [Parameter(Mandatory = $true)][string]$VerificationReport,
    [Parameter(Mandatory = $true)][string]$AbiReport
  )

  $verification = Get-Content -Raw -LiteralPath $VerificationReport |
    ConvertFrom-Json
  $modeReport = @($verification.modes | Where-Object { $_.mode -eq $Mode })
  if ($modeReport.Count -ne 1) {
    throw "Verification report has no unique '$Mode' result: $VerificationReport"
  }
  $artifacts = @($modeReport[0].artifacts | ForEach-Object {
      [ordered]@{
        path = [string]$_.path
        size = [long]$_.size
        sha256 = [string]$_.sha256
        verifyHash = -not ([string]$_.path).EndsWith(
          '.pdb', [StringComparison]::OrdinalIgnoreCase)
      }
    })
  $stamp = [ordered]@{
    schemaVersion = 1
    generatedAt = (Get-Date).ToUniversalTime().ToString('o')
    mode = $Mode
    fingerprint = $Fingerprint.value
    fingerprintInputs = $Fingerprint.inputs
    argsGnSha256 = [string]$modeReport[0].argsGnSha256
    artifacts = $artifacts
    verificationReport = [IO.Path]::GetRelativePath(
      $Layout.Root, $VerificationReport).Replace('\', '/')
    abiReport = [IO.Path]::GetRelativePath(
      $Layout.Root, $AbiReport).Replace('\', '/')
  }
  New-Item -ItemType Directory -Path $Layout.State -Force | Out-Null
  $destination = Get-KirakaraReadyStampPath -Layout $Layout -Mode $Mode
  $temporary = Join-Path $Layout.State (
    ".$Mode-ready-$([Guid]::NewGuid().ToString('N')).tmp")
  try {
    $stamp | ConvertTo-Json -Depth 12 | Set-Content `
      -LiteralPath $temporary `
      -Encoding utf8
    Move-Item -LiteralPath $temporary -Destination $destination -Force
  } finally {
    if (Test-Path -LiteralPath $temporary -PathType Leaf) {
      Remove-Item -LiteralPath $temporary -Force
    }
  }
}

function Remove-KirakaraExpiredLogs {
  param(
    [Parameter(Mandatory = $true)][pscustomobject]$Layout,
    [Parameter(Mandatory = $true)]$Lock
  )

  $limitProperty = $Lock.projectBootstrap.PSObject.Properties['maxLogFiles']
  if ($null -eq $limitProperty -or [int]$limitProperty.Value -lt 1) {
    throw 'projectBootstrap.maxLogFiles must be a positive integer.'
  }
  $limit = [int]$limitProperty.Value
  if (-not (Test-Path -LiteralPath $Layout.Logs -PathType Container)) {
    return
  }

  $protected = [Collections.Generic.HashSet[string]]::new(
    [StringComparer]::OrdinalIgnoreCase)
  if (Test-Path -LiteralPath $Layout.State -PathType Container) {
    foreach ($stampPath in @(Get-ChildItem -LiteralPath $Layout.State `
        -Filter '*-ready.json' -File)) {
      try {
        $stamp = Get-Content -Raw -LiteralPath $stampPath.FullName |
          ConvertFrom-Json
        foreach ($property in 'verificationReport', 'abiReport') {
          $relative = [string]$stamp.$property
          if ([string]::IsNullOrWhiteSpace($relative)) {
            continue
          }
          $candidate = [IO.Path]::GetFullPath((Join-Path $Layout.Root $relative))
          if (Test-PathWithin $candidate $Layout.Logs) {
            $null = $protected.Add($candidate)
          }
        }
      } catch {
        Write-Warning "Ignoring unreadable ready stamp during log retention: $($stampPath.FullName)"
      }
    }
  }

  $files = @(Get-ChildItem -LiteralPath $Layout.Logs -File | Sort-Object `
      @{ Expression = 'LastWriteTimeUtc'; Descending = $true }, `
      @{ Expression = 'Name'; Descending = $true })
  $remaining = $files.Count
  for ($index = $files.Count - 1; $index -ge 0; $index--) {
    if ($remaining -le $limit) {
      break
    }
    $file = $files[$index]
    $absolute = [IO.Path]::GetFullPath($file.FullName)
    if ($protected.Contains($absolute)) {
      continue
    }
    if (-not (Test-PathWithin $absolute $Layout.Logs)) {
      throw "Refusing to remove a log outside .kfe/logs: $absolute"
    }
    Remove-Item -LiteralPath $absolute -Force
    $remaining--
  }
  if ($remaining -gt $limit) {
    Write-Warning (
      "Log retention kept $remaining files because current ready stamps protect " +
      "more than the configured limit of $limit.")
  }
}

function Ensure-KirakaraProjectEngine {
  param(
    [Parameter(Mandatory = $true)][pscustomobject]$Layout,
    [Parameter(Mandatory = $true)]$Lock,
    [Parameter(Mandatory = $true)][string]$FlutterSdkRoot,
    [Parameter(Mandatory = $true)]
    [ValidateSet('debug', 'profile', 'release')]
    [string]$Mode,
    [ValidateRange(0, 256)][int]$Jobs = 0,
    [string]$ProxyUrl,
    [string]$WindowsSdkPath = 'C:\Program Files (x86)\Windows Kits\10'
  )

  $fingerprint = Get-KirakaraBootstrapFingerprint -Lock $Lock -Mode $Mode
  $ready = Test-KirakaraReadyStamp `
    -Layout $Layout `
    -Lock $Lock `
    -Mode $Mode `
    -Fingerprint $fingerprint.value
  if ($ready.ready) {
    Write-Host "[Kirakara Engine] Reusing verified $Mode Engine ($($fingerprint.value.Substring(0, 12)))."
    return
  }

  $handle = Enter-KirakaraBootstrapLock -Layout $Layout
  try {
    $fingerprint = Get-KirakaraBootstrapFingerprint -Lock $Lock -Mode $Mode
    $ready = Test-KirakaraReadyStamp `
      -Layout $Layout `
      -Lock $Lock `
      -Mode $Mode `
      -Fingerprint $fingerprint.value
    if ($ready.ready) {
      Write-Host "[Kirakara Engine] Another process completed the verified $Mode Engine."
      return
    }
    Write-Host "[Kirakara Engine] $Mode cache is not reusable: $($ready.reason)"
    $preflight = Assert-KirakaraBootstrapPreflight `
      -Layout $Layout `
      -Lock $Lock `
      -WindowsSdkPath $WindowsSdkPath
    Assert-KirakaraEngineSourceReady `
      -Layout $Layout `
      -Lock $Lock `
      -VisualStudioPath $preflight.visualStudioPath `
      -WindowsSdkPath $preflight.windowsSdkPath `
      -ProxyUrl $ProxyUrl
    Repair-KirakaraVpythonVirtualenv -Layout $Layout -Lock $Lock

    Write-Host "[Kirakara Engine] Building only the requested $Mode Engine mode..."
    & (Join-Path $PSScriptRoot 'build_windows_engine.ps1') `
      -WorkspaceRoot $Layout.Root `
      -Mode $Mode `
      -Variant patched `
      -Jobs $Jobs `
      -ProxyUrl $ProxyUrl `
      -VisualStudioPath $preflight.visualStudioPath `
      -WindowsSdkPath $preflight.windowsSdkPath | Out-Host

    New-Item -ItemType Directory -Path $Layout.Logs -Force | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $nonce = [Guid]::NewGuid().ToString('N').Substring(0, 8)
    $verificationReport = Join-Path $Layout.Logs `
      "verify-$Mode-$stamp-$nonce.json"
    $abiReport = Join-Path $Layout.Logs "abi-$Mode-$stamp-$nonce.json"
    Write-Host '[Kirakara Engine] Verifying source, GN, toolchain, exports and artifacts...'
    & (Join-Path $PSScriptRoot 'verify_engine_bundle.ps1') `
      -WorkspaceRoot $Layout.Root `
      -FlutterSdkRoot $FlutterSdkRoot `
      -Mode $Mode `
      -Variant patched `
      -ReportPath $verificationReport `
      -CaptureArtifactHashes | Out-Host
    Write-Host '[Kirakara Engine] Exercising the versioned compositor ABI gate...'
    & (Join-Path $PSScriptRoot 'test_engine_abi_gate.ps1') `
      -FlutterSdkRoot $FlutterSdkRoot `
      -WorkspaceRoot $Layout.Root `
      -Mode $Mode `
      -ReportPath $abiReport `
      -AllowUnlockedArtifacts | Out-Host
    Write-KirakaraReadyStamp `
      -Layout $Layout `
      -Lock $Lock `
      -Mode $Mode `
      -Fingerprint $fingerprint `
      -VerificationReport $verificationReport `
      -AbiReport $abiReport

    $ready = Test-KirakaraReadyStamp `
      -Layout $Layout `
      -Lock $Lock `
      -Mode $Mode `
      -Fingerprint $fingerprint.value
    if (-not $ready.ready) {
      throw "New $Mode ready stamp failed its own reuse gate: $($ready.reason)"
    }
    Remove-KirakaraExpiredLogs -Layout $Layout -Lock $Lock
    Write-Host "[Kirakara Engine] $Mode Engine is verified and ready."
  } finally {
    Exit-KirakaraBootstrapLock -Handle $handle
  }
}

function Get-KirakaraEngineStatus {
  $layout = Get-KirakaraProjectLayout
  $lock = Get-EngineLock
  $modes = foreach ($mode in 'debug', 'profile', 'release') {
    $fingerprint = Get-KirakaraBootstrapFingerprint -Lock $lock -Mode $mode
    $state = Test-KirakaraReadyStamp `
      -Layout $layout `
      -Lock $lock `
      -Mode $mode `
      -Fingerprint $fingerprint.value
    [ordered]@{
      mode = $mode
      ready = [bool]$state.ready
      reason = [string]$state.reason
      fingerprint = $fingerprint.value
    }
  }
  return [ordered]@{
    schemaVersion = 1
    workspace = $layout.Root
    workspaceExists = Test-Path -LiteralPath $layout.Root -PathType Container
    modes = @($modes)
  }
}

function Assert-KirakaraProjectEngineReady {
  param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('debug', 'profile', 'release')]
    [string]$Mode
  )

  $layout = Get-KirakaraProjectLayout
  $lock = Get-EngineLock
  $fingerprint = Get-KirakaraBootstrapFingerprint -Lock $lock -Mode $Mode
  $state = Test-KirakaraReadyStamp `
    -Layout $layout `
    -Lock $lock `
    -Mode $Mode `
    -Fingerprint $fingerprint.value
  if (-not $state.ready) {
    throw (
      "Repository-local $Mode Engine is not ready: $($state.reason). " +
      "Run '.\flutterw engine prepare $Mode' first."
    )
  }
  $build = Get-BuildLock -Lock $lock -Mode $Mode -Variant patched
  return [pscustomobject]@{
    mode = $Mode
    fingerprint = $fingerprint.value
    output = Get-EngineOutputDirectory `
      -Layout $layout `
      -LocalEngine $build.localEngine
  }
}

function Remove-KirakaraEngineMode {
  param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('debug', 'profile', 'release')]
    [string]$Mode
  )

  $layout = Get-KirakaraProjectLayout
  $lock = Get-EngineLock
  $build = Get-BuildLock -Lock $lock -Mode $Mode -Variant patched
  $output = Get-EngineOutputDirectory `
    -Layout $layout `
    -LocalEngine $build.localEngine
  $outRoot = Join-Path $layout.Root 'out'
  if (-not (Test-PathWithin $output $outRoot)) {
    throw "Refusing to remove an Engine output outside .kfe/out: $output"
  }
  if (Test-Path -LiteralPath $output) {
    Remove-Item -LiteralPath $output -Recurse -Force
  }
  $stamp = Get-KirakaraReadyStampPath -Layout $layout -Mode $Mode
  if (Test-Path -LiteralPath $stamp -PathType Leaf) {
    Remove-Item -LiteralPath $stamp -Force
  }
  Write-Host "Removed repository-local $Mode Engine output and ready stamp."
}

function Remove-KirakaraProjectWorkspace {
  $layout = Get-KirakaraProjectLayout
  $expected = [IO.Path]::GetFullPath((Join-Path $script:RepositoryRoot '.kfe'))
  $actual = [IO.Path]::GetFullPath($layout.Root)
  if (-not $actual.TrimEnd('\').Equals(
      $expected.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to purge unexpected path: $actual"
  }
  if (Test-Path -LiteralPath $actual) {
    Remove-Item -LiteralPath $actual -Recurse -Force
  }
  Write-Host "Removed the repository-local Kirakara Engine workspace: $actual"
}

function Invoke-KirakaraEngineCommand {
  param([Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Arguments)

  $command = if ($Arguments.Count -eq 0) { 'status' } else { $Arguments[0] }
  switch ($command) {
    'status' {
      Get-KirakaraEngineStatus | ConvertTo-Json -Depth 8 | Write-Host
      return 0
    }
    'doctor' {
      $layout = Get-KirakaraProjectLayout
      $lock = Get-EngineLock
      $proxyUrl = [Environment]::GetEnvironmentVariable(
        'KIRAKARA_ENGINE_PROXY', 'Process')
      Set-KirakaraGitProcessConfiguration
      Set-EngineProcessEnvironment -Layout $layout -ProxyUrl $proxyUrl
      $sdk = Resolve-KirakaraFlutterSdk `
        -Layout $layout -Lock $lock -RequiredMode debug -NoInstall
      $preflight = Assert-KirakaraBootstrapPreflight -Layout $layout -Lock $lock
      [ordered]@{
        schemaVersion = 1
        flutterSdk = $sdk
        visualStudioPath = $preflight.visualStudioPath
        windowsSdkPath = $preflight.windowsSdkPath
        availableFreeBytes = $preflight.availableFreeBytes
        minimumFreeBytes = $preflight.minimumFreeBytes
        passed = $true
      } | ConvertTo-Json -Depth 6 | Write-Host
      return 0
    }
    'prepare' {
      $mode = if ($Arguments.Count -ge 2) { $Arguments[1] } else { 'debug' }
      if ($mode -notin @('debug', 'profile', 'release')) {
        throw "Unknown Engine mode '$mode'. Expected debug, profile, or release."
      }
      $layout = Get-KirakaraProjectLayout
      $lock = Get-EngineLock
      $proxyUrl = [Environment]::GetEnvironmentVariable(
        'KIRAKARA_ENGINE_PROXY', 'Process')
      Set-KirakaraGitProcessConfiguration
      Set-EngineProcessEnvironment -Layout $layout -ProxyUrl $proxyUrl
      $sdk = Resolve-KirakaraFlutterSdk `
        -Layout $layout -Lock $lock -RequiredMode $mode
      $jobs = 0
      $jobsText = [Environment]::GetEnvironmentVariable(
        'KIRAKARA_ENGINE_JOBS', 'Process')
      if (-not [string]::IsNullOrWhiteSpace($jobsText) -and
          -not [int]::TryParse($jobsText, [ref]$jobs)) {
        throw "Invalid KIRAKARA_ENGINE_JOBS: $jobsText"
      }
      Ensure-KirakaraProjectEngine `
        -Layout $layout `
        -Lock $lock `
        -FlutterSdkRoot $sdk.root `
        -Mode $mode `
        -Jobs $jobs `
        -ProxyUrl $proxyUrl
      return 0
    }
    'clean' {
      $mode = if ($Arguments.Count -ge 2) { $Arguments[1] } else { 'debug' }
      if ($mode -notin @('debug', 'profile', 'release')) {
        throw "Unknown Engine mode '$mode'. Expected debug, profile, or release."
      }
      $layout = Get-KirakaraProjectLayout
      $handle = Enter-KirakaraBootstrapLock -Layout $layout
      try {
        Remove-KirakaraEngineMode -Mode $mode
      } finally {
        Exit-KirakaraBootstrapLock -Handle $handle
      }
      return 0
    }
    'purge' {
      $layout = Get-KirakaraProjectLayout
      $handle = Enter-KirakaraBootstrapLock -Layout $layout
      try {
        Remove-KirakaraProjectWorkspace
      } finally {
        Exit-KirakaraBootstrapLock -Handle $handle
      }
      return 0
    }
    default {
      throw "Unknown flutterw engine command '$command'. Use status, doctor, prepare, clean, or purge."
    }
  }
}

function Invoke-KirakaraFlutter {
  param([Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Arguments)

  $layout = Get-KirakaraProjectLayout
  $lock = Get-EngineLock
  $plan = Get-KirakaraFlutterInvocationPlan -Arguments $Arguments
  $requiredMode = if ($plan.needsEngine) { $plan.mode } else { 'debug' }
  $proxyUrl = [Environment]::GetEnvironmentVariable(
    'KIRAKARA_ENGINE_PROXY', 'Process')
  Set-KirakaraGitProcessConfiguration
  Set-EngineProcessEnvironment -Layout $layout -ProxyUrl $proxyUrl
  $sdk = Resolve-KirakaraFlutterSdk `
    -Layout $layout `
    -Lock $lock `
    -RequiredMode $requiredMode
  Write-Host "[Kirakara Engine] Flutter SDK: $($sdk.root) ($($sdk.source))"
  if ($plan.needsEngine) {
    $jobs = 0
    $jobsText = [Environment]::GetEnvironmentVariable(
      'KIRAKARA_ENGINE_JOBS', 'Process')
    if (-not [string]::IsNullOrWhiteSpace($jobsText) -and
        -not [int]::TryParse($jobsText, [ref]$jobs)) {
      throw "Invalid KIRAKARA_ENGINE_JOBS: $jobsText"
    }
    Ensure-KirakaraProjectEngine `
      -Layout $layout `
      -Lock $lock `
      -FlutterSdkRoot $sdk.root `
      -Mode $plan.mode `
      -Jobs $jobs `
      -ProxyUrl $proxyUrl
  }

  $invokeArguments = [System.Collections.Generic.List[string]]::new()
  foreach ($argument in $Arguments) {
    $invokeArguments.Add($argument)
  }
  if ($plan.injectEngine) {
    $build = Get-BuildLock -Lock $lock -Mode $plan.mode -Variant patched
    $engineOutput = Get-EngineOutputDirectory `
      -Layout $layout `
      -LocalEngine $build.localEngine
    Invalidate-StaleFlutterEphemeralEngine `
      -EngineOutputDirectory $engineOutput `
      -AppRoot $script:RepositoryRoot
    $invokeArguments.Add("--local-engine=$($build.localEngine)")
    $invokeArguments.Add("--local-engine-host=$($build.localEngineHost)")
    $invokeArguments.Add("--local-engine-src-path=$($layout.OutputRoot)")
  }
  $flutter = Join-Path $sdk.root 'bin\flutter.bat'
  Write-Host "[Kirakara Engine] Executing Flutter: $($invokeArguments -join ' ')"
  Push-Location $script:RepositoryRoot
  try {
    & $flutter @invokeArguments | Out-Host
    return $LASTEXITCODE
  } finally {
    Pop-Location
  }
}

Export-ModuleMember -Function @(
  'Get-KirakaraProjectLayout',
  'Get-KirakaraFlutterInvocationPlan',
  'Get-KirakaraBootstrapFingerprint',
  'Get-KirakaraEngineStatus',
  'Assert-KirakaraProjectEngineReady',
  'Invoke-KirakaraEngineCommand',
  'Invoke-KirakaraFlutter'
)
