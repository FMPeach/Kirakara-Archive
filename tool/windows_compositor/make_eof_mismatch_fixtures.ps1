[CmdletBinding()]
param(
  [string]$OutputDirectory = (Join-Path $env:TEMP `
    'kirakara_eof_mismatch_fixtures'),

  [string]$Ffmpeg = 'ffmpeg',

  [string]$Ffprobe = 'ffprobe',

  [ValidateRange(3, 15)]
  [int]$LongSeconds = 6,

  [ValidateRange(1, 10)]
  [int]$ShortSeconds = 2,

  [switch]$Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($ShortSeconds -ge $LongSeconds) {
  throw 'ShortSeconds must be less than LongSeconds.'
}
foreach ($tool in @($Ffmpeg, $Ffprobe)) {
  if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
    throw "Required media tool was not found: $tool"
  }
}

$output = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath(
  $OutputDirectory)
$files = [ordered]@{
  audioShortVideo = 'audio-short-video.mp4'
  audioShortVocal = 'audio-short-vocal.wav'
  audioShortAccompaniment = 'audio-short-inst.wav'
  videoShortVideo = 'video-short-video.mp4'
  videoShortVocal = 'video-short-vocal.wav'
  videoShortAccompaniment = 'video-short-inst.wav'
}
$targets = @($files.Values | ForEach-Object { Join-Path $output $_ })
$targets += Join-Path $output 'manifest.json'
$existing = @($targets | Where-Object { Test-Path -LiteralPath $_ })
if ($existing.Count -gt 0 -and -not $Force) {
  throw (
    'EOF mismatch fixtures already exist; preserve them or pass -Force: ' +
    ($existing -join ', '))
}
New-Item -ItemType Directory -Path $output -Force | Out-Null

function Invoke-CheckedFfmpeg {
  param(
    [Parameter(Mandatory = $true)][string]$Label,
    [Parameter(Mandatory = $true)][string[]]$Arguments
  )

  Write-Host "Generating $Label..."
  & $Ffmpeg @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "ffmpeg failed while generating $Label (exit $LASTEXITCODE)."
  }
}

function Get-MediaDurationSeconds {
  param([Parameter(Mandatory = $true)][string]$Path)

  $raw = & $Ffprobe -v error -show_entries format=duration `
    -of default=noprint_wrappers=1:nokey=1 $Path
  if ($LASTEXITCODE -ne 0) {
    throw "ffprobe failed for $Path (exit $LASTEXITCODE)."
  }
  $duration = 0.0
  if (-not [double]::TryParse(
      ([string]$raw).Trim(),
      [Globalization.NumberStyles]::Float,
      [Globalization.CultureInfo]::InvariantCulture,
      [ref]$duration) -or $duration -le 0) {
    throw "ffprobe returned an invalid duration for ${Path}: $raw"
  }
  return $duration
}

$audioShortVideo = Join-Path $output $files.audioShortVideo
$videoShortVideo = Join-Path $output $files.videoShortVideo
Invoke-CheckedFfmpeg -Label $files.audioShortVideo -Arguments @(
  '-y', '-v', 'error', '-f', 'lavfi',
  '-i', "testsrc2=size=1280x720:rate=60:duration=$LongSeconds",
  '-c:v', 'libx264', '-preset', 'veryfast', '-pix_fmt', 'yuv420p',
  $audioShortVideo
)
Invoke-CheckedFfmpeg -Label $files.videoShortVideo -Arguments @(
  '-y', '-v', 'error', '-f', 'lavfi',
  '-i', "testsrc=size=1280x720:rate=60:duration=$ShortSeconds",
  '-c:v', 'libx264', '-preset', 'veryfast', '-pix_fmt', 'yuv420p',
  $videoShortVideo
)

$audioDefinitions = @(
  @{ Name = $files.audioShortVocal; Seconds = $ShortSeconds; Frequency = 440 },
  @{ Name = $files.audioShortAccompaniment; Seconds = $ShortSeconds; Frequency = 220 },
  @{ Name = $files.videoShortVocal; Seconds = $LongSeconds; Frequency = 330 },
  @{ Name = $files.videoShortAccompaniment; Seconds = $LongSeconds; Frequency = 165 }
)
foreach ($definition in $audioDefinitions) {
  $path = Join-Path $output $definition.Name
  Invoke-CheckedFfmpeg -Label $definition.Name -Arguments @(
    '-y', '-v', 'error', '-f', 'lavfi',
    '-i', "sine=frequency=$($definition.Frequency):sample_rate=44100:duration=$($definition.Seconds)",
    '-ac', '2', '-c:a', 'pcm_s16le', $path
  )
}

$audioShortVideoDuration = Get-MediaDurationSeconds $audioShortVideo
$audioShortVocalDuration = Get-MediaDurationSeconds `
  (Join-Path $output $files.audioShortVocal)
$audioShortAccompanimentDuration = Get-MediaDurationSeconds `
  (Join-Path $output $files.audioShortAccompaniment)
$videoShortVideoDuration = Get-MediaDurationSeconds $videoShortVideo
$videoShortVocalDuration = Get-MediaDurationSeconds `
  (Join-Path $output $files.videoShortVocal)
$videoShortAccompanimentDuration = Get-MediaDurationSeconds `
  (Join-Path $output $files.videoShortAccompaniment)
$audioShortLatestEof = [Math]::Max(
  $audioShortVocalDuration,
  $audioShortAccompanimentDuration)
$videoShortEarliestAudioEof = [Math]::Min(
  $videoShortVocalDuration,
  $videoShortAccompanimentDuration)
if (
  $audioShortVideoDuration - $audioShortLatestEof -lt 0.75 -or
  $videoShortEarliestAudioEof - $videoShortVideoDuration -lt 0.75
) {
  throw 'Generated fixtures do not have a meaningful EOF duration mismatch.'
}

$manifest = [ordered]@{
  schemaVersion = 1
  generatedAt = (Get-Date).ToUniversalTime().ToString('o')
  videoMasterClock = $true
  cases = @(
    [ordered]@{
      name = 'audio-shorter-than-video'
      video = $files.audioShortVideo
      vocal = $files.audioShortVocal
      accompaniment = $files.audioShortAccompaniment
      videoDurationSeconds = $audioShortVideoDuration
      vocalDurationSeconds = $audioShortVocalDuration
      accompanimentDurationSeconds = $audioShortAccompanimentDuration
    },
    [ordered]@{
      name = 'video-shorter-than-audio'
      video = $files.videoShortVideo
      vocal = $files.videoShortVocal
      accompaniment = $files.videoShortAccompaniment
      videoDurationSeconds = $videoShortVideoDuration
      vocalDurationSeconds = $videoShortVocalDuration
      accompanimentDurationSeconds = $videoShortAccompanimentDuration
    }
  )
}
$manifestPath = Join-Path $output 'manifest.json'
$manifest | ConvertTo-Json -Depth 5 | Set-Content `
  -LiteralPath $manifestPath `
  -Encoding utf8

Write-Host "EOF mismatch fixtures saved to $output"
Write-Host "Manifest: $manifestPath"
[pscustomobject]@{
  outputDirectory = $output
  manifestPath = $manifestPath
  audioShortVideoDurationSeconds = $audioShortVideoDuration
  audioShortVocalDurationSeconds = $audioShortVocalDuration
  audioShortAccompanimentDurationSeconds = $audioShortAccompanimentDuration
  videoShortVideoDurationSeconds = $videoShortVideoDuration
  videoShortVocalDurationSeconds = $videoShortVocalDuration
  videoShortAccompanimentDurationSeconds = $videoShortAccompanimentDuration
}
