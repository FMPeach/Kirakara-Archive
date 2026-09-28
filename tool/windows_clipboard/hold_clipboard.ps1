[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$ReadyPath,

  [ValidateRange(50, 5000)]
  [int]$DurationMilliseconds = 120
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class KirakaraClipboardTestLock {
  [DllImport("user32.dll", SetLastError = true)]
  [return: MarshalAs(UnmanagedType.Bool)]
  public static extern bool OpenClipboard(IntPtr owner);

  [DllImport("user32.dll", SetLastError = true)]
  [return: MarshalAs(UnmanagedType.Bool)]
  public static extern bool CloseClipboard();
}
'@

$absoluteReadyPath = [IO.Path]::GetFullPath($ReadyPath)
$readyDirectory = Split-Path -Parent $absoluteReadyPath
if (-not (Test-Path -LiteralPath $readyDirectory -PathType Container)) {
  New-Item -ItemType Directory -Path $readyDirectory -Force | Out-Null
}

$deadline = [DateTime]::UtcNow.AddSeconds(2)
while (-not [KirakaraClipboardTestLock]::OpenClipboard([IntPtr]::Zero)) {
  if ([DateTime]::UtcNow -ge $deadline) {
    $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    throw "Test helper could not open the clipboard (error $errorCode)."
  }
  Start-Sleep -Milliseconds 5
}

try {
  [IO.File]::WriteAllText($absoluteReadyPath, 'ready')
  Start-Sleep -Milliseconds $DurationMilliseconds
} finally {
  [void][KirakaraClipboardTestLock]::CloseClipboard()
}
