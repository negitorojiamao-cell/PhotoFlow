$ErrorActionPreference = "Stop"

Write-Host "Checking Flutter installation..." -ForegroundColor Cyan
flutter --version
if ($LASTEXITCODE -ne 0) {
  throw "Flutter is not installed or is not available on PATH. Install Flutter first: https://docs.flutter.dev/get-started/install/windows"
}

if (-not (Test-Path ".\pubspec.yaml")) {
  throw "Run this script from the PhotoFlow repository root."
}

$platforms = @()
if (-not (Test-Path ".\android")) { $platforms += "android" }
if (-not (Test-Path ".\windows")) { $platforms += "windows" }

if ($platforms.Count -gt 0) {
  Write-Host "Generating missing platform scaffolding: $($platforms -join ', ')" -ForegroundColor Cyan
  flutter create --project-name photoflow --platforms="$($platforms -join ',')" .
  if ($LASTEXITCODE -ne 0) { throw "flutter create failed." }
}

Write-Host "Fetching packages..." -ForegroundColor Cyan
flutter pub get
if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed." }

Write-Host ""
Write-Host "Setup complete. Available devices:" -ForegroundColor Green
flutter devices
