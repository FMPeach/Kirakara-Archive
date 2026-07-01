param(
  [string]$Platforms = "windows,android"
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  Write-Host "Flutter was not found on PATH. Install Flutter or add it to PATH, then rerun this script."
  exit 1
}

flutter create --platforms=$Platforms .
flutter pub get

Write-Host "Kirakara-App Flutter project is ready."
