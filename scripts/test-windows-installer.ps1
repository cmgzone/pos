# Install and uninstall a packaged Piki POS release in an isolated build folder.
#
# Usage:
#   .\scripts\test-windows-installer.ps1 -Version 1.0.5

param(
  [Parameter(Mandatory = $true)]
  [string]$Version
)

$ErrorActionPreference = "Stop"

$projectRoot = [System.IO.Path]::GetFullPath(
  (Split-Path -Parent $PSScriptRoot)
)
$buildRoot = [System.IO.Path]::GetFullPath(
  (Join-Path $projectRoot "build")
)
$smokeTarget = [System.IO.Path]::GetFullPath(
  (Join-Path $buildRoot "installer-smoke-$Version")
)
$expectedPrefix = $buildRoot + [System.IO.Path]::DirectorySeparatorChar
if (-not $smokeTarget.StartsWith(
  $expectedPrefix,
  [System.StringComparison]::OrdinalIgnoreCase
)) {
  throw "Unsafe installer smoke-test target: $smokeTarget"
}

$installer = Join-Path(
  $buildRoot
) "windows-packages\piki-pos-windows-$Version-setup.exe"
if (-not (Test-Path -LiteralPath $installer)) {
  throw "Installer not found: $installer"
}

if (Test-Path -LiteralPath $smokeTarget) {
  Remove-Item -LiteralPath $smokeTarget -Recurse -Force
}
New-Item -ItemType Directory -Path $smokeTarget | Out-Null

$installExitCode = $null
$uninstallExitCode = $null
$installedProductVersion = $null
$requiredFiles = @(
  "pos_app.exe",
  "flutter_windows.dll",
  "connectivity_plus_plugin.dll",
  "sqlite3.dll",
  "data\app.so",
  "unins000.exe"
)

try {
  $installArguments = @(
    "/VERYSILENT",
    "/SUPPRESSMSGBOXES",
    "/NORESTART",
    "/NOICONS",
    "/DIR=`"$smokeTarget`""
  )
  $installProcess = Start-Process `
    -FilePath $installer `
    -ArgumentList $installArguments `
    -Wait `
    -PassThru `
    -WindowStyle Hidden
  $installExitCode = $installProcess.ExitCode
  if ($installExitCode -ne 0) {
    throw "Installer smoke test failed with exit code $installExitCode"
  }

  $missingFiles = $requiredFiles | Where-Object {
    -not (Test-Path -LiteralPath (Join-Path $smokeTarget $_))
  }
  if ($missingFiles) {
    throw "Installed package is missing: $($missingFiles -join ', ')"
  }

  $installedProductVersion = (
    Get-Item -LiteralPath (Join-Path $smokeTarget "pos_app.exe")
  ).VersionInfo.ProductVersion
} finally {
  $uninstaller = Join-Path $smokeTarget "unins000.exe"
  if (Test-Path -LiteralPath $uninstaller) {
    $uninstallProcess = Start-Process `
      -FilePath $uninstaller `
      -ArgumentList @("/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART") `
      -Wait `
      -PassThru `
      -WindowStyle Hidden
    $uninstallExitCode = $uninstallProcess.ExitCode
  }
  if (Test-Path -LiteralPath $smokeTarget) {
    Remove-Item -LiteralPath $smokeTarget -Recurse -Force
  }
}

if ($uninstallExitCode -ne 0) {
  throw "Uninstaller smoke test failed with exit code $uninstallExitCode"
}

[pscustomobject]@{
  InstallerExitCode = $installExitCode
  InstalledProductVersion = $installedProductVersion
  RequiredFilesVerified = $requiredFiles.Count
  UninstallerExitCode = $uninstallExitCode
  CleanupComplete = -not (Test-Path -LiteralPath $smokeTarget)
}
