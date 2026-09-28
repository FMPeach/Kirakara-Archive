[CmdletBinding()]
param(
  [string]$ReportPath
)

$ErrorActionPreference = 'Stop'

if (-not ('Kirakara.Compatibility.NativeMethods' -as [type])) {
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace Kirakara.Compatibility {
  public static class NativeMethods {
    [DllImport("user32.dll")]
    public static extern int GetSystemMetrics(int index);

    [DllImport("user32.dll")]
    public static extern uint GetDpiForSystem();

    [DllImport("dwmapi.dll")]
    public static extern int DwmIsCompositionEnabled(
        [MarshalAs(UnmanagedType.Bool)] out bool enabled);
  }
}
'@
}

$repository = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if ([string]::IsNullOrWhiteSpace($ReportPath)) {
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $ReportPath = Join-Path $repository `
    "build\diagnostics\compatibility\windows-inventory-$stamp.json"
}
if ([IO.Path]::IsPathRooted($ReportPath)) {
  $absoluteReport = [IO.Path]::GetFullPath($ReportPath)
} else {
  $absoluteReport = [IO.Path]::GetFullPath((Join-Path (Get-Location).Path $ReportPath))
}
if (Test-Path -LiteralPath $absoluteReport) {
  throw "ReportPath already exists; preserve it or choose another path: $absoluteReport"
}

$os = Get-CimInstance Win32_OperatingSystem
$computer = Get-CimInstance Win32_ComputerSystem
$processors = @(Get-CimInstance Win32_Processor)
$controllers = @(Get-CimInstance Win32_VideoController)
$monitors = @(Get-CimInstance Win32_DesktopMonitor)
$dwmEnabled = $false
$dwmResult = [Kirakara.Compatibility.NativeMethods]::DwmIsCompositionEnabled(
  [ref]$dwmEnabled)

$report = [ordered]@{
  schemaVersion = 1
  generatedAt = (Get-Date).ToUniversalTime().ToString('o')
  purpose = 'diagnostic-only; never used as a persisted runtime capability decision'
  process = [ordered]@{
    architecture = [Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()
    is64Bit = [Environment]::Is64BitProcess
    remoteSession = (
      [Kirakara.Compatibility.NativeMethods]::GetSystemMetrics(0x1000) -ne 0)
    systemDpi = [Kirakara.Compatibility.NativeMethods]::GetDpiForSystem()
    dwmCompositionEnabled = $dwmEnabled
    dwmQueryHresult = $dwmResult
  }
  os = [ordered]@{
    caption = $os.Caption
    version = $os.Version
    buildNumber = $os.BuildNumber
    architecture = $os.OSArchitecture
  }
  computer = [ordered]@{
    manufacturer = $computer.Manufacturer
    model = $computer.Model
    totalPhysicalMemory = [uint64]$computer.TotalPhysicalMemory
  }
  processors = @($processors | ForEach-Object {
    [ordered]@{
      name = $_.Name.Trim()
      cores = $_.NumberOfCores
      logicalProcessors = $_.NumberOfLogicalProcessors
    }
  })
  videoControllers = @($controllers | ForEach-Object {
    [ordered]@{
      name = $_.Name
      status = $_.Status
      availability = $_.Availability
      driverVersion = $_.DriverVersion
      driverDate = if ($_.DriverDate) { $_.DriverDate.ToString('o') } else { $null }
      adapterRam = if ($_.AdapterRAM) { [uint64]$_.AdapterRAM } else { $null }
      currentMode = if ($_.CurrentHorizontalResolution -and $_.CurrentVerticalResolution) {
        [ordered]@{
          width = $_.CurrentHorizontalResolution
          height = $_.CurrentVerticalResolution
          refreshRate = $_.CurrentRefreshRate
          bitsPerPixel = $_.CurrentBitsPerPixel
        }
      } else {
        $null
      }
    }
  })
  monitors = @($monitors | ForEach-Object {
    [ordered]@{
      name = $_.Name
      type = $_.MonitorType
      status = $_.Status
      width = $_.ScreenWidth
      height = $_.ScreenHeight
    }
  })
}

New-Item -ItemType Directory -Path (Split-Path -Parent $absoluteReport) `
  -Force | Out-Null
$report | ConvertTo-Json -Depth 8 | Set-Content `
  -LiteralPath $absoluteReport -Encoding utf8
Write-Host "Windows compatibility inventory saved to $absoluteReport"
