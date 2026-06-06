param(
  [Parameter(Mandatory=$true)]
  [string]$InputPath,

  [Parameter(Mandatory=$true)]
  [string]$OutputPath,

  [double]$HoleRatio = 0.32,

  [int]$GrayMin = 150,

  [int]$GrayTolerance = 18
)

Add-Type -AssemblyName System.Drawing

if (!(Test-Path $InputPath)) {
  throw "Input file not found: $InputPath"
}

$inputFull = Resolve-Path $InputPath
$outputDir = Split-Path $OutputPath -Parent

if ($outputDir -and !(Test-Path $outputDir)) {
  New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
}

$bmp = [System.Drawing.Bitmap]::FromFile($inputFull)
$out = New-Object System.Drawing.Bitmap $bmp.Width, $bmp.Height, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)

$cx = $bmp.Width / 2
$cy = $bmp.Height / 2
$centerRadius = [Math]::Min($bmp.Width, $bmp.Height) * $HoleRatio

for ($y = 0; $y -lt $bmp.Height; $y++) {
  for ($x = 0; $x -lt $bmp.Width; $x++) {
    $c = $bmp.GetPixel($x, $y)

    $dx = $x - $cx
    $dy = $y - $cy
    $insideCenter = (($dx * $dx + $dy * $dy) -lt ($centerRadius * $centerRadius))

    $isGrayOrWhite =
      ([Math]::Abs($c.R - $c.G) -lt $GrayTolerance) -and
      ([Math]::Abs($c.G - $c.B) -lt $GrayTolerance) -and
      ($c.R -gt $GrayMin)

    $isAlmostWhite =
      ($c.R -gt 220) -and
      ($c.G -gt 220) -and
      ($c.B -gt 220)

    if ($insideCenter -or $isGrayOrWhite -or $isAlmostWhite) {
      $out.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(0, 0, 0, 0))
    } else {
      $out.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($c.A, $c.R, $c.G, $c.B))
    }
  }
}

$bmp.Dispose()

$tempPath = "$OutputPath.tmp.png"
$out.Save($tempPath, [System.Drawing.Imaging.ImageFormat]::Png)
$out.Dispose()

Move-Item $tempPath $OutputPath -Force

$check = [System.Drawing.Bitmap]::FromFile((Resolve-Path $OutputPath))
$center = $check.GetPixel([int]($check.Width / 2), [int]($check.Height / 2))
$check.Dispose()

if ($center.A -ne 0) {
  Write-Host "Warning: center alpha is not 0. Center A=$($center.A)"
} else {
  Write-Host "Done. Real transparent PNG created:"
  Write-Host $OutputPath
}
