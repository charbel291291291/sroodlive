param(
  [ValidateSet("debug", "release")]
  [string]$BuildType = "debug",

  [string]$Notes = "Test build update",

  [switch]$ForceUpdate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$PubspecPath = Join-Path $ProjectRoot "pubspec.yaml"
$EnvPath = Join-Path $ProjectRoot ".env"

if (Test-Path $EnvPath) {
  Get-Content $EnvPath | ForEach-Object {
    if ($_ -match "^\s*([^#=]+?)\s*=\s*(.+?)\s*$") {
      [Environment]::SetEnvironmentVariable($Matches[1].Trim(), $Matches[2].Trim(), "Process")
    }
  }
}

$SupabaseUrl = $env:SUPABASE_URL
$ServiceRoleKey = $env:SUPABASE_SERVICE_KEY

if ([string]::IsNullOrWhiteSpace($SupabaseUrl)) {
  throw "Missing SUPABASE_URL. Set it as an environment variable or in .env"
}

if ([string]::IsNullOrWhiteSpace($ServiceRoleKey)) {
  throw "Missing SUPABASE_SERVICE_KEY. Set it as an environment variable or in .env"
}

if (!(Test-Path $PubspecPath)) {
  throw "pubspec.yaml not found at $PubspecPath"
}

$Pubspec = Get-Content $PubspecPath -Raw

if ($Pubspec -notmatch "(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$") {
  throw "Could not find version line like version: 1.0.0+15 in pubspec.yaml"
}

$VersionName = $Matches[1]
$OldVersionCode = [int]$Matches[2]
$NewVersionCode = $OldVersionCode + 1

$NewPubspec = $Pubspec -replace "(?m)^version:\s*[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+\s*$", "version: $VersionName+$NewVersionCode"
Set-Content -Path $PubspecPath -Value $NewPubspec -Encoding UTF8

Write-Host "Version updated: $VersionName+$OldVersionCode -> $VersionName+$NewVersionCode"

Push-Location $ProjectRoot

flutter pub get

if ($BuildType -eq "release") {
  flutter build apk --release --split-per-abi
  $ApkPath = Join-Path $ProjectRoot "build\app\outputs\flutter-apk\app-arm64-v8a-release.apk"
} else {
  flutter build apk --debug
  $ApkPath = Join-Path $ProjectRoot "build\app\outputs\flutter-apk\app-debug.apk"
}

Pop-Location

if (!(Test-Path $ApkPath)) {
  throw "APK not found at $ApkPath"
}

$Bucket = "app_releases"
$ObjectPath = "srood-live-latest.apk"
$TempApk = Join-Path $env:TEMP $ObjectPath

Copy-Item $ApkPath $TempApk -Force

$UploadUrl = "$SupabaseUrl/storage/v1/object/$Bucket/$ObjectPath"

$StorageHeaders = @{
  Authorization = "Bearer $ServiceRoleKey"
  apikey = $ServiceRoleKey
  "x-upsert" = "true"
  "cache-control" = "no-cache"
}

Write-Host "Uploading APK to Supabase Storage..."

Invoke-RestMethod `
  -Method Post `
  -Uri $UploadUrl `
  -Headers $StorageHeaders `
  -ContentType "application/vnd.android.package-archive" `
  -InFile $TempApk | Out-Null

$PublicApkUrl = "$SupabaseUrl/storage/v1/object/public/$Bucket/$ObjectPath"

$UpdateBody = @{
  id = "android_latest"
  platform = "android"
  version_code = $NewVersionCode
  version_name = $VersionName
  apk_url = $PublicApkUrl
  release_notes = $Notes
  force_update = [bool]$ForceUpdate
  is_active = $true
} | ConvertTo-Json

$RestHeaders = @{
  Authorization = "Bearer $ServiceRoleKey"
  apikey = $ServiceRoleKey
  Prefer = "resolution=merge-duplicates,return=minimal"
}

Write-Host "Updating app_versions row..."

Invoke-RestMethod `
  -Method Post `
  -Uri "$SupabaseUrl/rest/v1/app_versions?on_conflict=id" `
  -Headers $RestHeaders `
  -ContentType "application/json" `
  -Body $UpdateBody | Out-Null

Write-Host ""
Write-Host "Done."
Write-Host "VersionCode: $NewVersionCode"
Write-Host "APK URL: $PublicApkUrl?v=$NewVersionCode"
Write-Host "Testers should open the app and tap Download update."

