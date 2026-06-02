$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$EnvFile = Join-Path $Root ".env.local"

if (!(Test-Path $EnvFile)) {
  throw ".env.local not found. Run .\scripts\run-web.ps1 first."
}

$envMap = @{}

Get-Content $EnvFile | ForEach-Object {
  $line = $_.Trim()
  if ($line -and !$line.StartsWith("#") -and $line.Contains("=")) {
    $parts = $line.Split("=", 2)
    $envMap[$parts[0].Trim()] = $parts[1].Trim()
  }
}

flutter run -d windows `
  --dart-define=SUPABASE_URL=$($envMap["SUPABASE_URL"]) `
  --dart-define=SUPABASE_ANON_KEY=$($envMap["SUPABASE_ANON_KEY"])
