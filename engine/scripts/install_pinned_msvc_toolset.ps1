[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$VisualStudioPath,

  [string]$ProxyUrl,

  [switch]$Elevated
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$lock = Get-EngineLock
$componentId = @($lock.hostBaseline.msvcComponentIds)
$toolsetVersion = [string]$lock.hostBaseline.msvcToolsetVersion
if ($componentId.Count -eq 0 -or [string]::IsNullOrWhiteSpace($toolsetVersion)) {
  throw 'engine.lock.json does not define the pinned MSVC components and toolset.'
}

function Test-Administrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  return $principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
  )
}

function Quote-PowerShellLiteral {
  param([Parameter(Mandatory = $true)][string]$Value)

  return "'$($Value.Replace("'", "''"))'"
}

if (-not (Test-Administrator)) {
  if ($Elevated) {
    throw 'Elevation was requested, but the relaunched process is not an administrator.'
  }

  # Use the inbox host for elevation. The Codex-bundled pwsh executable lives
  # below the interactive user's cache and is not a stable elevated entrypoint.
  $hostExecutable = Join-Path $env:SystemRoot `
    'System32\WindowsPowerShell\v1.0\powershell.exe'
  $repositoryRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot '..\..')
  )
  $logDirectory = Join-Path $repositoryRoot 'build\diagnostics'
  [System.IO.Directory]::CreateDirectory($logDirectory) | Out-Null
  $elevatedLog = Join-Path $logDirectory `
    'install_pinned_msvc_toolset.log'
  $commandParts = @(
    '&', (Quote-PowerShellLiteral $PSCommandPath),
    '-Elevated',
    '-VisualStudioPath', (Quote-PowerShellLiteral $VisualStudioPath)
  )
  if (-not [string]::IsNullOrWhiteSpace($ProxyUrl)) {
    $commandParts += @('-ProxyUrl', (Quote-PowerShellLiteral $ProxyUrl))
  }
  $commandParts += @('*>', (Quote-PowerShellLiteral $elevatedLog))
  $command = $commandParts -join ' '
  $encodedCommand = [Convert]::ToBase64String(
    [Text.Encoding]::Unicode.GetBytes($command)
  )
  Write-Host 'Requesting administrator approval for Visual Studio Installer...'
  $elevatedProcess = Start-Process `
    -FilePath $hostExecutable `
    -ArgumentList @(
      '-NoProfile',
      '-ExecutionPolicy', 'Bypass',
      '-EncodedCommand', $encodedCommand
    ) `
    -Verb RunAs `
    -Wait `
    -PassThru
  if ($elevatedProcess.ExitCode -ne 0) {
    if (Test-Path -LiteralPath $elevatedLog -PathType Leaf) {
      Get-Content -LiteralPath $elevatedLog | Write-Host
    }
    throw "Elevated toolset installation failed with exit code $($elevatedProcess.ExitCode)."
  }
  Get-Content -LiteralPath $elevatedLog | Write-Host
  exit 0
}

$resolvedVisualStudio = [System.IO.Path]::GetFullPath($VisualStudioPath)
$setup = Join-Path ${env:ProgramFiles(x86)} `
  'Microsoft Visual Studio\Installer\setup.exe'
if (-not (Test-Path -LiteralPath $setup -PathType Leaf)) {
  throw "Visual Studio Installer is missing: $setup"
}
if (-not (Test-Path -LiteralPath $resolvedVisualStudio -PathType Container)) {
  throw "Visual Studio installation is missing: $resolvedVisualStudio"
}

$vswhere = Join-Path ${env:ProgramFiles(x86)} `
  'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path -LiteralPath $vswhere -PathType Leaf)) {
  throw "Visual Studio Installer is missing vswhere.exe: $vswhere"
}
$installationPath = (& $vswhere `
    -path $resolvedVisualStudio -property installationPath | Select-Object -First 1)
if ($LASTEXITCODE -ne 0 -or
    [string]::IsNullOrWhiteSpace($installationPath) -or
    [System.IO.Path]::GetFullPath($installationPath) -ne $resolvedVisualStudio) {
  throw "The requested path is not a registered Visual Studio installation: $resolvedVisualStudio"
}

if (-not [string]::IsNullOrWhiteSpace($ProxyUrl)) {
  $env:HTTP_PROXY = $ProxyUrl
  $env:HTTPS_PROXY = $ProxyUrl
}

$installerArgumentParts = @(
  'modify',
  '--installPath', ('"{0}"' -f $resolvedVisualStudio)
)
foreach ($component in $componentId) {
  $installerArgumentParts += @('--add', $component)
}
$installerArgumentParts += @('--passive', '--norestart')
$installerArguments = $installerArgumentParts -join ' '
Write-Host "Installing $($componentId -join ', ') into $resolvedVisualStudio"
$installer = Start-Process `
  -FilePath $setup `
  -ArgumentList $installerArguments `
  -Wait `
  -PassThru
if ($installer.ExitCode -notin @(0, 3010)) {
  throw "Visual Studio Installer failed with exit code $($installer.ExitCode)."
}

$toolsetsRoot = Join-Path $resolvedVisualStudio 'VC\Tools\MSVC'
$installed = Get-Item -LiteralPath (Join-Path $toolsetsRoot $toolsetVersion) `
  -ErrorAction SilentlyContinue
if ($null -eq $installed -or -not $installed.PSIsContainer) {
  throw "Expected installed MSVC toolset $toolsetVersion below $toolsetsRoot."
}
$required = @(
  (Join-Path $installed.FullName 'include'),
  (Join-Path $installed.FullName 'lib\x64'),
  (Join-Path $installed.FullName 'atlmfc\include\atlbase.h'),
  (Join-Path $installed.FullName 'atlmfc\lib\x64\atls.lib'),
  (Join-Path $installed.FullName 'bin\Hostx64\x64\cl.exe')
)
$missing = @($required | Where-Object { -not (Test-Path -LiteralPath $_) })
if ($missing.Count -ne 0) {
  throw "MSVC $toolsetVersion installation is incomplete:`n$($missing -join [Environment]::NewLine)"
}

Write-Host "Installed pinned MSVC toolset: $($installed.Name)"
Assert-MsvcToolsetVersion -Lock $lock -VisualStudioPath $resolvedVisualStudio
if ($installer.ExitCode -eq 3010) {
  Write-Warning 'Visual Studio Installer requested a reboot; no reboot was started.'
}
