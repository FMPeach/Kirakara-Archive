[CmdletBinding()]
param(
  [string]$SourcePng
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repositoryRoot = [IO.Path]::GetFullPath(
  (Join-Path $PSScriptRoot '..\..')
)
if ([string]::IsNullOrWhiteSpace($SourcePng)) {
  $SourcePng = Join-Path $repositoryRoot 'assets\branding\app_icon.png'
}
$sourcePath = [IO.Path]::GetFullPath($SourcePng)
if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
  throw "App icon source does not exist: $sourcePath"
}

Add-Type -AssemblyName System.Drawing

function New-IconPngBytes {
  param(
    [Parameter(Mandatory = $true)]
    [System.Drawing.Image]$Source,

    [Parameter(Mandatory = $true)]
    [int]$Size
  )

  $bitmap = [Drawing.Bitmap]::new(
    $Size,
    $Size,
    [Drawing.Imaging.PixelFormat]::Format32bppArgb
  )
  $graphics = [Drawing.Graphics]::FromImage($bitmap)
  $stream = [IO.MemoryStream]::new()
  try {
    $graphics.Clear([Drawing.Color]::Transparent)
    $graphics.CompositingMode =
        [Drawing.Drawing2D.CompositingMode]::SourceCopy
    $graphics.CompositingQuality =
        [Drawing.Drawing2D.CompositingQuality]::HighQuality
    $graphics.InterpolationMode =
        [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.PixelOffsetMode =
        [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.SmoothingMode =
        [Drawing.Drawing2D.SmoothingMode]::HighQuality
    $graphics.DrawImage(
      $Source,
      [Drawing.Rectangle]::new(0, 0, $Size, $Size),
      0,
      0,
      $Source.Width,
      $Source.Height,
      [Drawing.GraphicsUnit]::Pixel
    )
    $bitmap.Save($stream, [Drawing.Imaging.ImageFormat]::Png)
    return ,$stream.ToArray()
  } finally {
    $stream.Dispose()
    $graphics.Dispose()
    $bitmap.Dispose()
  }
}

function Write-PngFile {
  param(
    [Parameter(Mandatory = $true)]
    [byte[]]$Bytes,

    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    throw "Expected icon output directory does not exist: $directory"
  }
  [IO.File]::WriteAllBytes($Path, $Bytes)
}

function Write-WindowsIcon {
  param(
    [Parameter(Mandatory = $true)]
    [System.Drawing.Image]$Source,

    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $sizes = @(16, 20, 24, 32, 40, 48, 64, 128, 256)
  $images = @(
    foreach ($size in $sizes) {
      [pscustomobject]@{
        Size = $size
        Bytes = [byte[]](New-IconPngBytes -Source $Source -Size $size)
      }
    }
  )

  $stream = [IO.MemoryStream]::new()
  $writer = [IO.BinaryWriter]::new($stream)
  try {
    $writer.Write([uint16]0)
    $writer.Write([uint16]1)
    $writer.Write([uint16]$images.Count)

    $offset = 6 + (16 * $images.Count)
    foreach ($image in $images) {
      $dimension = if ($image.Size -eq 256) { 0 } else { $image.Size }
      $writer.Write([byte]$dimension)
      $writer.Write([byte]$dimension)
      $writer.Write([byte]0)
      $writer.Write([byte]0)
      $writer.Write([uint16]1)
      $writer.Write([uint16]32)
      $writer.Write([uint32]$image.Bytes.Length)
      $writer.Write([uint32]$offset)
      $offset += $image.Bytes.Length
    }
    foreach ($image in $images) {
      $writer.Write([byte[]]$image.Bytes)
    }
    $writer.Flush()
    [IO.File]::WriteAllBytes($Path, $stream.ToArray())
  } finally {
    $writer.Dispose()
    $stream.Dispose()
  }
}

$source = [Drawing.Bitmap]::FromFile($sourcePath)
try {
  if ($source.Width -ne $source.Height) {
    throw "App icon source must be square; got $($source.Width)x$($source.Height)."
  }
  if ($source.Width -lt 128) {
    throw "App icon source must be at least 128x128; got $($source.Width)x$($source.Height)."
  }

  $androidSizes = [ordered]@{
    'mipmap-mdpi' = 48
    'mipmap-hdpi' = 72
    'mipmap-xhdpi' = 96
    'mipmap-xxhdpi' = 144
    'mipmap-xxxhdpi' = 192
  }
  foreach ($entry in $androidSizes.GetEnumerator()) {
    $bytes = New-IconPngBytes -Source $source -Size $entry.Value
    $path = Join-Path $repositoryRoot (
      "android\app\src\main\res\$($entry.Key)\ic_launcher.png"
    )
    Write-PngFile -Bytes $bytes -Path $path
  }

  $windowsPath = Join-Path $repositoryRoot (
    'windows\runner\resources\app_icon.ico'
  )
  Write-WindowsIcon -Source $source -Path $windowsPath
} finally {
  $source.Dispose()
}

Write-Host "Generated Windows and Android app icons from $sourcePath"
