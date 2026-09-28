[CmdletBinding()]
param(
  [switch]$Elevated
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
$isAdministrator = $principal.IsInRole(
  [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $isAdministrator) {
  if ($Elevated) {
    throw 'The workspace shell was relaunched but is not elevated.'
  }
  $arguments = @(
    '-NoLogo',
    '-NoProfile',
    '-NoExit',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    ('"{0}"' -f $PSCommandPath),
    '-Elevated'
  )
  Start-Process `
    -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
    -ArgumentList $arguments `
    -WorkingDirectory $repositoryRoot `
    -WindowStyle Normal `
    -Verb RunAs | Out-Null
  return
}

Set-Location -LiteralPath $repositoryRoot
$Host.UI.RawUI.WindowTitle = 'Kirakara compositor · Administrator'
Write-Host 'Kirakara Windows compositor administrator workspace is ready.' `
  -ForegroundColor Green
Write-Host "Repository: $repositoryRoot"
Write-Host 'This shell intentionally runs no command until one is entered.'
