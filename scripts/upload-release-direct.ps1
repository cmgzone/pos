# Upload APK or Windows installer directly to the server via SCP,
# then register it in the database via the backend API.
#
# This bypasses the Traefik -> nginx -> backend proxy chain that stalls
# on large files. Use this if the browser upload hangs or times out.
#
# Usage:
#   .\scripts\upload-release-direct.ps1 -Server user@your-server-ip `
#     -Platform android -Version 1.0.0 -FilePath build\app\outputs\flutter-apk\app-release.apk
#
#   .\scripts\upload-release-direct.ps1 -Server root@192.168.1.100 `
#     -Platform windows -Version 1.0.0 -FilePath build\windows-packages\piki-pos-windows-1.0.0-setup.exe

param(
  [Parameter(Mandatory=$true)]
  [string]$Server,

  [Parameter(Mandatory=$true)]
  [ValidateSet("android","windows")]
  [string]$Platform,

  [Parameter(Mandatory=$true)]
  [string]$Version,

  [Parameter(Mandatory=$true)]
  [string]$FilePath,

  [string]$AdminEmail = "",
  [string]$AdminPassword = "",
  [string]$ApiBaseUrl = "https://pikipos.com"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $FilePath)) {
  Write-Error "File not found: $FilePath"
  exit 1
}

$file = Get-Item $FilePath
$extension = $file.Extension.ToLower()
if ($Platform -eq "android" -and $extension -ne ".apk") {
  Write-Error "Android releases must be .apk files. Got: $extension"
  exit 1
}
if ($Platform -eq "windows" -and $extension -notin @(".exe",".msi",".zip")) {
  Write-Error "Windows releases must be .exe, .msi, or .zip files. Got: $extension"
  exit 1
}

$cleanVersion = $Version -replace "\+.*$", ""
$timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$remoteName = "piki-pos-$Platform-$cleanVersion-$timestamp$extension"
$sizeMb = [math]::Round($file.Length / 1MB, 1)

Write-Host ""
Write-Host "Direct release upload" -ForegroundColor Cyan
Write-Host "  Server:   $Server" -ForegroundColor White
Write-Host "  Platform: $Platform" -ForegroundColor White
Write-Host "  Version:  $cleanVersion" -ForegroundColor White
Write-Host "  File:     $FilePath ($sizeMb MB)" -ForegroundColor White
Write-Host "  Remote:   $remoteName" -ForegroundColor White
Write-Host ""

# --- Step 1: Copy the file directly to the server via SCP -------------------
Write-Host "[1/3] Copying file to server via SCP..." -ForegroundColor Yellow

# Upload to /tmp on the server first, then move it into the Docker volume.
$remoteTempPath = "/tmp/$remoteName"
scp -P 22 "$FilePath" "${Server}:$remoteTempPath"
if ($LASTEXITCODE -ne 0) {
  Write-Error "SCP upload failed with exit code $LASTEXITCODE"
  exit 1
}
Write-Host "  SCP complete." -ForegroundColor Green

# --- Step 2: Move the file into the Docker volume ---------------------------
Write-Host "[2/3] Moving file into the backend container..." -ForegroundColor Yellow

# Find the running backend container name and copy the file into it.
$sshCommand = @"
container=`$(docker ps --filter 'ancestor=piki-web' --format '{{.Names}}' | head -1)
if [ -z "`$container" ]; then
  container=`$(docker ps --format '{{.Names}}' | grep -i 'piki.*web\|piki.*pos\|backend' | head -1)
fi
if [ -z "`$container" ]; then
  echo 'ERROR: Could not find the backend container'
  exit 1
fi
echo "Found container: `$container"
docker exec "$container" mkdir -p /app/backend/app-releases/$Platform
docker cp "$remoteTempPath" "`$container:/app/backend/app-releases/$Platform/$remoteName"
docker exec "`$container" ls -lh "/app/backend/app-releases/$Platform/$remoteName"
rm -f "$remoteTempPath"
echo "DONE"
"@

$result = ssh "$Server" $sshCommand 2>&1
Write-Host $result

if ($LASTEXITCODE -ne 0 -or $result -notmatch "DONE") {
  Write-Error "Failed to move file into the container"
  exit 1
}
Write-Host "  File is now in the container." -ForegroundColor Green

# --- Step 3: Register the release URL in the database via API ----------------
Write-Host "[3/3] Registering release in the admin panel..." -ForegroundColor Yellow

$releaseUrl = "/downloads/app/$Platform/$remoteName"

# Prompt for admin credentials if not provided
if (-not $AdminEmail) {
  $AdminEmail = Read-Host "Enter admin email"
}
if (-not $AdminPassword) {
  $AdminPassword = Read-Host "Enter admin password" -AsSecureString | ConvertFrom-SecureString
}

# Login to get a JWT token
$loginBody = @{ email = $AdminEmail; password = $AdminPassword } | ConvertTo-Json
$loginResponse = Invoke-RestMethod -Uri "$ApiBaseUrl/api/platform/login" `
  -Method POST -Body $loginBody -ContentType "application/json" -ErrorAction Stop
$token = $loginResponse.data.accessToken
if (-not $token) {
  Write-Error "Login failed - could not get access token"
  exit 1
}
Write-Host "  Logged in as $AdminEmail" -ForegroundColor Green

# Fetch current app version config
$currentResponse = Invoke-RestMethod -Uri "$ApiBaseUrl/api/platform/app-version" `
  -Method GET -Headers @{ Authorization = "Bearer $token" } -ErrorAction Stop
$current = $currentResponse.data

# Build the updated config
$updated = $current | ConvertTo-Json -Depth 5 | ConvertFrom-Json
if ($Platform -eq "android") {
  $updated.latestVersion = $cleanVersion
  $updated.androidVersion = $cleanVersion
  $updated.apkUrl = $releaseUrl
  $updated.androidUrl = $releaseUrl
} else {
  $updated.windowsVersion = $cleanVersion
  $updated.windowsUrl = $releaseUrl
}

# Save the updated config
$updateBody = $updated | ConvertTo-Json -Depth 5
$updateResponse = Invoke-RestMethod -Uri "$ApiBaseUrl/api/platform/app-version" `
  -Method PUT -Body $updateBody -ContentType "application/json" `
  -Headers @{ Authorization = "Bearer $token" } -ErrorAction Stop

Write-Host "  Release registered: $releaseUrl" -ForegroundColor Green
Write-Host ""
Write-Host "Success!" -ForegroundColor Green
Write-Host "  The $Platform release v$cleanVersion is now live." -ForegroundColor Cyan
Write-Host "  Download URL: $ApiBaseUrl$releaseUrl" -ForegroundColor Cyan
Write-Host ""
Write-Host "Users will see the update prompt on next app launch." -ForegroundColor Cyan
