# publish_test_apk.ps1
# Builds a debug APK and uploads it to Supabase Storage (app_releases bucket),
# then upserts the android_latest row in public.app_versions.
#
# Usage:
#   .\scripts\publish_test_apk.ps1
#
# Requirements:
#   - Flutter SDK on PATH
#   - Supabase CLI on PATH  (npx supabase or local install)
#   - SUPABASE_URL and SUPABASE_SERVICE_KEY env vars set, OR a .env file at
#     project root with those values.
#   - pubspec.yaml at project root (script auto-reads version/build number)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Load .env if present ──────────────────────────────────────────────────────
$envFile = Join-Path $PSScriptRoot '..' '.env'
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        if ($_ -match '^\s*([^#=]+?)\s*=\s*(.+?)\s*$') {
            [System.Environment]::SetEnvironmentVariable($Matches[1], $Matches[2])
        }
    }
}

$supabaseUrl = $env:SUPABASE_URL
$serviceKey  = $env:SUPABASE_SERVICE_KEY

if (-not $supabaseUrl -or -not $serviceKey) {
    Write-Error 'SUPABASE_URL and SUPABASE_SERVICE_KEY must be set.'
    exit 1
}

# ── Read version from pubspec.yaml ────────────────────────────────────────────
$pubspec = Get-Content (Join-Path $PSScriptRoot '..' 'pubspec.yaml') -Raw
if ($pubspec -match 'version:\s+(\S+)\+(\d+)') {
    $versionName = $Matches[1]
    $versionCode = [int]$Matches[2]
} else {
    Write-Error 'Could not parse version from pubspec.yaml'
    exit 1
}
Write-Host "Version: $versionName ($versionCode)" -ForegroundColor Cyan

# ── Build debug APK ───────────────────────────────────────────────────────────
Write-Host 'Building debug APK...' -ForegroundColor Cyan
Push-Location (Join-Path $PSScriptRoot '..')
flutter build apk --debug
Pop-Location

$apkSrc = Join-Path $PSScriptRoot '..' 'build' 'app' 'outputs' 'flutter-apk' 'app-debug.apk'
if (-not (Test-Path $apkSrc)) {
    Write-Error "APK not found at $apkSrc"
    exit 1
}

# ── Upload to Supabase Storage ────────────────────────────────────────────────
$storagePath = 'srood-live-latest.apk'
$uploadUrl   = "$supabaseUrl/storage/v1/object/app_releases/$storagePath"

Write-Host "Uploading APK to $uploadUrl ..." -ForegroundColor Cyan
$headers = @{
    'Authorization' = "Bearer $serviceKey"
    'Content-Type'  = 'application/octet-stream'
    'x-upsert'      = 'true'
}
$bytes = [System.IO.File]::ReadAllBytes((Resolve-Path $apkSrc))
Invoke-RestMethod -Uri $uploadUrl -Method Post -Headers $headers -Body $bytes | Out-Null
Write-Host 'Upload complete.' -ForegroundColor Green

# ── Public URL for the APK ────────────────────────────────────────────────────
$apkPublicUrl = "$supabaseUrl/storage/v1/object/public/app_releases/$storagePath"

# ── Upsert android_latest row in app_versions ─────────────────────────────────
$dbUrl  = "$supabaseUrl/rest/v1/app_versions"
$body   = @{
    id            = 'android_latest'
    version_code  = $versionCode
    version_name  = $versionName
    apk_url       = $apkPublicUrl
    release_notes = "Debug build $versionName+$versionCode"
    is_active     = $true
    force_update  = $false
} | ConvertTo-Json

$dbHeaders = @{
    'Authorization' = "Bearer $serviceKey"
    'apikey'        = $serviceKey
    'Content-Type'  = 'application/json'
    'Prefer'        = 'resolution=merge-duplicates'
}

Write-Host "Upserting app_versions row (id=android_latest) ..." -ForegroundColor Cyan
Invoke-RestMethod -Uri $dbUrl -Method Post -Headers $dbHeaders -Body $body | Out-Null
Write-Host "Done. android_latest -> $versionName ($versionCode)" -ForegroundColor Green
Write-Host "APK URL: $apkPublicUrl" -ForegroundColor White
