#Requires -Version 7.0

[CmdletBinding(PositionalBinding = $false)]
param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [AllowEmptyCollection()]
  [string[]]$FlutterArguments = @()
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$processEnvironment = [Collections.Generic.Dictionary[string, string]]::new(
  [StringComparer]::OrdinalIgnoreCase)
foreach ($entry in Get-ChildItem Env:) {
  $processEnvironment[$entry.Name] = $entry.Value
}

$module = Join-Path $PSScriptRoot `
  'engine\scripts\project_engine_bootstrap.psm1'
$exitCode = 1
try {
  Import-Module $module -Force -ErrorAction Stop
  if (
    $FlutterArguments.Count -gt 0 -and
    $FlutterArguments[0] -eq 'engine'
  ) {
    $exitCode = [int](Invoke-KirakaraEngineCommand `
        -Arguments @($FlutterArguments | Select-Object -Skip 1))
  } else {
    $exitCode = [int](Invoke-KirakaraFlutter -Arguments $FlutterArguments)
  }
} catch {
  Write-Error $_ -ErrorAction Continue
  $exitCode = 1
} finally {
  foreach ($name in @(Get-ChildItem Env: | ForEach-Object { $_.Name })) {
    if (-not $processEnvironment.ContainsKey($name)) {
      Remove-Item -LiteralPath "Env:\$name" -ErrorAction SilentlyContinue
    }
  }
  foreach ($entry in $processEnvironment.GetEnumerator()) {
    [Environment]::SetEnvironmentVariable(
      $entry.Key, $entry.Value, 'Process')
  }
}
exit $exitCode
