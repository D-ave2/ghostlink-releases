param(
    [string]$RequestedName = "GHOSTLINK"
)

$ErrorActionPreference = "Stop"

$Repo = "D-ave2/ghostlink-releases"
$AssetName = "GHOSTLINK_WINDOWS_BOOTSTRAP.zip"
$ManifestName = "ghostlink-release.json"

function Step([string]$Text) {
    Write-Host ""
    Write-Host ">>> $Text" -ForegroundColor Cyan
}

function Ensure-BinPath {
    $bin = Join-Path $env:LOCALAPPDATA "GHOSTLINK\bin"
    New-Item -ItemType Directory -Force $bin | Out-Null

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $parts = @()
    if ($userPath) {
        $parts = @(
            $userPath -split ";" |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ }
        )
    }

    if ($parts -notcontains $bin) {
        $parts += $bin
    }

    [Environment]::SetEnvironmentVariable(
        "Path",
        (($parts | Select-Object -Unique) -join ";"),
        "User"
    )
}

function Register-DownloadCommand {
    $onlineRoot = Join-Path $env:LOCALAPPDATA "GHOSTLINK\online"
    $binRoot = Join-Path $env:LOCALAPPDATA "GHOSTLINK\bin"

    New-Item -ItemType Directory -Force $onlineRoot | Out-Null
    New-Item -ItemType Directory -Force $binRoot | Out-Null

    $selfTarget = Join-Path $onlineRoot "ghostlink-online.ps1"

    if ($PSCommandPath -and ((Resolve-Path $PSCommandPath).Path -ne $selfTarget)) {
        Copy-Item $PSCommandPath $selfTarget -Force
    }

    $cmd = @'
@echo off
setlocal
if /I not "%~1"=="GHOSTLINK" (
  echo Usage: DOWNLOAD GHOSTLINK
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%LOCALAPPDATA%\GHOSTLINK\online\ghostlink-online.ps1" -RequestedName GHOSTLINK
exit /b %ERRORLEVEL%
'@

    Set-Content (Join-Path $binRoot "DOWNLOAD.cmd") $cmd -Encoding ASCII
    Ensure-BinPath
}

if ($RequestedName.ToUpperInvariant() -ne "GHOSTLINK") {
    Write-Host "Usage: DOWNLOAD GHOSTLINK"
    exit 1
}

if (-not [Environment]::Is64BitOperatingSystem) {
    throw "GHOSTLINK Windows release currently requires 64-bit Windows."
}

if ($env:PROCESSOR_ARCHITECTURE -ne "AMD64" -and $env:PROCESSOR_ARCHITEW6432 -ne "AMD64") {
    throw "This release is the Windows x64 build. ARM64 support will be a separate release."
}

Write-Host ""
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host " GHOSTLINK // ONLINE DOWNLOAD ENGINE" -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan

$headers = @{
    "Accept" = "application/vnd.github+json"
    "User-Agent" = "GHOSTLINK-Downloader"
}

Step "Checking latest public GHOSTLINK release"

$release = Invoke-RestMethod `
    -Uri "https://api.github.com/repos/$Repo/releases/latest" `
    -Headers $headers `
    -Method Get

$manifestAsset = @($release.assets) |
    Where-Object { $_.name -eq $ManifestName } |
    Select-Object -First 1

$bootstrapAsset = @($release.assets) |
    Where-Object { $_.name -eq $AssetName } |
    Select-Object -First 1

if (-not $manifestAsset) {
    throw "Latest release is missing $ManifestName."
}
if (-not $bootstrapAsset) {
    throw "Latest release is missing $AssetName."
}

$tempRoot = Join-Path $env:TEMP ("GHOSTLINK-" + [Guid]::NewGuid().ToString("N"))
$manifestPath = Join-Path $tempRoot $ManifestName
$zipPath = Join-Path $tempRoot $AssetName
$extractRoot = Join-Path $tempRoot "package"

New-Item -ItemType Directory -Force $tempRoot | Out-Null
New-Item -ItemType Directory -Force $extractRoot | Out-Null

try {
    Step "Downloading release manifest"
    Invoke-WebRequest `
        -Uri $manifestAsset.browser_download_url `
        -OutFile $manifestPath `
        -UseBasicParsing

    $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json

    $platform = $manifest.platforms.'windows-x64'
    if (-not $platform) {
        throw "Manifest has no windows-x64 release."
    }

    if ($platform.asset -ne $AssetName) {
        throw "Manifest asset name does not match expected GHOSTLINK asset."
    }

    $expectedSha = ([string]$platform.sha256).Trim().ToLowerInvariant()
    if ($expectedSha -notmatch '^[0-9a-f]{64}$') {
        throw "Manifest SHA-256 is invalid."
    }

    Step "Downloading GHOSTLINK $($manifest.version)"
    Invoke-WebRequest `
        -Uri $bootstrapAsset.browser_download_url `
        -OutFile $zipPath `
        -UseBasicParsing

    $actualSha = (Get-FileHash $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()

    if ($actualSha -ne $expectedSha) {
        throw "GHOSTLINK checksum mismatch. Installation stopped."
    }

    Write-Host "SHA-256 => VERIFIED" -ForegroundColor Green

    Step "Expanding verified GHOSTLINK package"
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractRoot -Force

    $installer = Join-Path $extractRoot "installer\ghostlink-download.ps1"
    if (-not (Test-Path -LiteralPath $installer)) {
        throw "Verified GHOSTLINK package is missing its installer."
    }

    Step "Requesting Administrator permission for installation"
    $args = "-NoProfile -ExecutionPolicy Bypass -File `"$installer`" -RequestedName GHOSTLINK"
    $p = Start-Process powershell.exe -Verb RunAs -ArgumentList $args -PassThru -Wait

    if ($p.ExitCode -ne 0) {
        throw "GHOSTLINK installer exited with code $($p.ExitCode)."
    }

    # The packaged installer writes a local repair wrapper. Restore the
    # internet-backed command so future DOWNLOAD GHOSTLINK calls remain online.
    Register-DownloadCommand

    Write-Host ""
    Write-Host "=====================================================" -ForegroundColor Green
    Write-Host " DOWNLOAD GHOSTLINK => COMPLETE" -ForegroundColor Green
    Write-Host "=====================================================" -ForegroundColor Green
    Write-Host "Installed release: $($manifest.version)"
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
