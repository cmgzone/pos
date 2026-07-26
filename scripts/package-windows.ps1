# Build and package the Piki POS Windows release into a single .zip
# that contains the .exe plus all required plugin DLLs and the data folder.
#
# Usage:
#   .\scripts\package-windows.ps1                    # uses pubspec.yaml version
#   .\scripts\package-windows.ps1 -Version 1.2.0+7   # explicit version
#   .\scripts\package-windows.ps1 -OutputDir C:\releases
#
# A bare Flutter .exe will fail at runtime with errors like
# "connectivity_plus_plugin.dll not found" because the plugin DLLs and
# data folder are missing. Always ship the full Release folder as a .zip.

param(
  [string]$Version = "",
  [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

# --- Determine version -------------------------------------------------------
if (-not $Version) {
  $pubspecPath = Join-Path $ProjectRoot "pubspec.yaml"
  if (Test-Path $pubspecPath) {
    $match = Select-String -Path $pubspecPath -Pattern "^\s*version:\s*([^\s#]+)"
    if ($match) {
      $Version = $match.Matches[0].Groups[1].Value
    }
  }
}
if (-not $Version) { $Version = "1.0.0+1" }
$cleanVersion = $Version -replace "\+.*$", ""
$buildNumber = if ($Version -match "\+(\d+)$") { $Matches[1] } else { "1" }
Write-Host "Building Piki POS Windows release v$cleanVersion..." -ForegroundColor Cyan

# --- Build -------------------------------------------------------------------
Write-Host "Running flutter build windows --release --build-name $cleanVersion --build-number $buildNumber..." -ForegroundColor Yellow
flutter build windows --release `
  --build-name $cleanVersion `
  --build-number $buildNumber `
  --dart-define "APP_VERSION=$Version"
if ($LASTEXITCODE -ne 0) {
  Write-Error "flutter build windows failed with exit code $LASTEXITCODE"
  exit 1
}

$releaseDir = Join-Path $ProjectRoot "build\windows\x64\runner\Release"
if (-not (Test-Path $releaseDir)) {
  Write-Error "Release directory not found: $releaseDir"
  exit 1
}

# --- Verify required DLLs are present ---------------------------------------
$requiredDlls = @(
  "flutter_windows.dll",
  "connectivity_plus_plugin.dll",
  "isar.dll",
  "sqlite3.dll"
)
$missing = @()
foreach ($dll in $requiredDlls) {
  if (-not (Test-Path (Join-Path $releaseDir $dll))) {
    $missing += $dll
  }
}
if ($missing.Count -gt 0) {
  Write-Error "Missing required DLLs in build output: $($missing -join ', ')"
  exit 1
}

Write-Host "Build output verified - all required DLLs present." -ForegroundColor Green

# --- Package -----------------------------------------------------------------
if (-not $OutputDir) {
  $OutputDir = Join-Path $ProjectRoot "build\windows-packages"
}
if (-not (Test-Path $OutputDir)) {
  New-Item -ItemType Directory -Path $OutputDir | Out-Null
}

$zipName = "piki-pos-windows-$cleanVersion.zip"
$zipPath = Join-Path $OutputDir $zipName

# Remove old zip if it exists
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

Write-Host "Packaging Release folder into $zipName..." -ForegroundColor Yellow

# Use .NET ZipFile to create the archive (available on Windows PowerShell 5.1+)
Add-Type -AssemblyName System.IO.Compression.FileSystem

# Create a temp staging folder named piki-pos-windows so the zip extracts
# into a clean subdirectory instead of dumping files into the user's Downloads.
$stagingName = "piki-pos-windows"
$stagingDir = Join-Path $OutputDir $stagingName
if (Test-Path $stagingDir) { Remove-Item $stagingDir -Recurse -Force }
New-Item -ItemType Directory -Path $stagingDir | Out-Null

# Copy all build output into the staging folder
Copy-Item -Path (Join-Path $releaseDir "*") -Destination $stagingDir -Recurse -Force

# Create the zip from the staging folder
[System.IO.Compression.ZipFile]::CreateFromDirectory($stagingDir, $zipPath)

# Clean up staging
Remove-Item $stagingDir -Recurse -Force

# --- Build the Windows installer (setup.exe) with Inno Setup -----------------
$innoCandidates = @(
  "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
  "C:\Program Files\Inno Setup 6\ISCC.exe",
  "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
)
$innoPath = $innoCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

$installerPath = $null
if ($innoPath) {
  Write-Host "Building Windows installer with Inno Setup..." -ForegroundColor Yellow
  $issPath = Join-Path $ProjectRoot "scripts\piki-pos-windows.iss"
  if (Test-Path $issPath) {
    $installerName = "piki-pos-windows-$cleanVersion-setup.exe"
    $installerPath = Join-Path (Join-Path $ProjectRoot "build\windows-packages") $installerName
    if (Test-Path $installerPath) {
      Remove-Item $installerPath -Force
    }

    # Update the version in the .iss file so the installer matches
    $issContent = Get-Content $issPath -Raw
    $issContent = $issContent -replace '#define MyAppVersion "[^"]*"', "#define MyAppVersion `"$cleanVersion`""
    Set-Content -Path $issPath -Value $issContent -NoNewline

    & $innoPath $issPath 2>&1 | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) {
      Write-Error "Inno Setup failed with exit code $LASTEXITCODE"
      exit 1
    }
    if (Test-Path $installerPath) {
      Write-Host "Installer created successfully." -ForegroundColor Green
    } else {
      Write-Warning "Inno Setup ran but installer file was not found at expected path."
      $installerPath = $null
    }
  } else {
    Write-Warning "Inno Setup script not found: $issPath - skipping installer build."
  }
} else {
  Write-Warning "Inno Setup (ISCC.exe) not found - skipping installer build."
  Write-Host "  Install Inno Setup to also generate a setup.exe:" -ForegroundColor Yellow
  Write-Host "    winget install JRSoftware.InnoSetup" -ForegroundColor Yellow
}

# --- Report ------------------------------------------------------------------
$zipInfo = Get-Item $zipPath
$zipSizeMb = [math]::Round($zipInfo.Length / 1MB, 1)
Write-Host ""
Write-Host "Done!" -ForegroundColor Green
Write-Host "  Zip:       $zipPath ($zipSizeMb MB)" -ForegroundColor White
if ($installerPath -and (Test-Path $installerPath)) {
  $instInfo = Get-Item $installerPath
  $instSizeMb = [math]::Round($instInfo.Length / 1MB, 1)
  Write-Host "  Installer: $installerPath ($instSizeMb MB)" -ForegroundColor White
}
Write-Host ""
Write-Host "Upload the installer (.exe) or zip via the admin panel" -ForegroundColor Cyan
Write-Host "Windows release section. The installer is recommended - it gives" -ForegroundColor Cyan
Write-Host "users a setup wizard with shortcuts and an uninstaller." -ForegroundColor Cyan
