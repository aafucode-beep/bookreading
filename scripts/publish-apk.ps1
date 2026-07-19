param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
$mobile = Join-Path $ProjectRoot "mobile"
$keyProperties = Join-Path $mobile "android\key.properties"
if (-not (Test-Path -LiteralPath $keyProperties)) {
    throw "Refusing to publish: mobile/android/key.properties is missing. Configure the private release keystore first."
}

Push-Location $mobile
try {
    flutter test
    flutter analyze
    flutter build apk --release
} finally {
    Pop-Location
}

$source = Join-Path $mobile "build\app\outputs\flutter-apk\app-release.apk"
$downloads = Join-Path $ProjectRoot "server\downloads"
New-Item -ItemType Directory -Force -Path $downloads | Out-Null
$target = Join-Path $downloads "brave-growth.apk"
Copy-Item -LiteralPath $source -Destination $target -Force
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $target).Hash.ToLowerInvariant()
Set-Content -LiteralPath "$target.sha256" -Value "$hash  brave-growth.apk" -Encoding ascii
Write-Output "Published: $target"
Write-Output "SHA256: $hash"

