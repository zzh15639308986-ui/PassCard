# Prepares a generated illustration for use as the PassCard app icon.
#
#   powershell -ExecutionPolicy Bypass -File tools\prepare-icon.ps1 `
#       -Src <generated.png> -Out <AppIcon-1024.png> [-Preview <preview.png>]
#
# Three jobs, in order:
#   0. Normalize to 1024x1024. The catalog slot is the iOS 17 single-size
#      icon; generators drift (1254, 2048), so resize here.
#   1. Flatten to opaque. App Store icon art must not carry an alpha channel,
#      and a stray transparent pixel would show through as a hole on the
#      home screen. Missing alpha is filled with the top-left background
#      colour, which is the backdrop everywhere the art does not cover.
#   2. Patch out the generator's corner watermark. The backdrop is graph
#      paper, so a naive horizontal copy would leave the grid lines in the
#      patched corner out of phase with the rest. Detect the vertical grid
#      line period on a clean row and snap the copy shift to whole cells;
#      same-row copying keeps the horizontal lines exact by construction.
#      Pass -SkipPatch when the art carries no watermark: copying over clean
#      art only risks transplanting whatever the source band happened to hold.
#   3. Emit a 512/180/120/60 preview, because whether a cartoon face still
#      reads at home-screen size cannot be judged from the 1024 original.
#
# ASCII-only output on purpose: a GBK console mangles CJK.

param(
    [Parameter(Mandatory = $true)][string]$SrcPath,
    [Parameter(Mandatory = $true)][string]$Out,
    [string]$Preview,
    [int]$PatchShift = 0,
    [switch]$SkipPatch
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$src = [System.Drawing.Image]::FromFile((Resolve-Path -LiteralPath $SrcPath).Path)
if ($src.Width -ne $src.Height) { throw ("icon art must be square, got " + $src.Width + "x" + $src.Height) }

$W = 1024
$H = 1024
$bmp = New-Object System.Drawing.Bitmap($W, $H)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode      = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.InterpolationMode  = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.PixelOffsetMode    = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$backdrop = $src.GetPixel(0, 0)
$g.Clear($backdrop)
$g.DrawImage($src, 0, 0, $W, $H)
$g.Dispose()
$src.Dispose()

# Watermark patch: bottom-right block, each pixel copied from the same row
# a whole number of grid cells to the left.
function Get-GridPeriod {
    param([System.Drawing.Bitmap]$b, [int]$w, [int]$h)
    foreach ($fy in @(0.05, 0.5)) {
        $y = [int]($h * $fy)
        $centers = New-Object System.Collections.Generic.List[int]
        $runStart = -1
        for ($x = 0; $x -lt $w; $x++) {
            $p = $b.GetPixel($x, $y)
            $isLine = (($p.B - $p.R) -gt 5)
            if ($isLine -and $runStart -lt 0) { $runStart = $x }
            if ((-not $isLine) -and $runStart -ge 0) {
                $centers.Add([int](($runStart + $x - 1) / 2))
                $runStart = -1
            }
        }
        if ($runStart -ge 0) { $centers.Add([int](($runStart + $w - 1) / 2)) }
        if ($centers.Count -ge 4) {
            $gaps = @()
            for ($i = 1; $i -lt $centers.Count; $i++) { $gaps += ($centers[$i] - $centers[$i - 1]) }
            $sorted = $gaps | Sort-Object
            return [int]$sorted[[int]($sorted.Count / 2)]
        }
    }
    return 0
}

if ($SkipPatch) {
    Write-Output "watermark patch skipped"
} else {
    $rx = [int]($W * 0.78)
    $ry = [int]($H * 0.90)
    $period = Get-GridPeriod -b $bmp -w $W -h $H
    $shift = [int]($W * 0.40)
    if ($period -ge 8) {
        $shift = [int]([math]::Round(($W * 0.40) / $period)) * $period
    }
    if ($PatchShift -ge 1) { $shift = $PatchShift }
    Write-Output ("grid period " + $period + " px, watermark copy shift " + $shift + " px")
    for ($y = $ry; $y -lt $H; $y++) {
        for ($x = $rx; $x -lt $W; $x++) {
            $bmp.SetPixel($x, $y, $bmp.GetPixel($x - $shift, $y))
        }
    }
}

$outDir = Split-Path -Parent $Out
if (-not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
Write-Output ("icon    -> " + $Out + "  (" + (Get-Item -LiteralPath $Out).Length + " bytes, ${W}x${H}, opaque)")

if ($Preview) {
    $sizes = @(512, 180, 120, 60)
    $pad = 40
    $pw = [int](($sizes | Measure-Object -Sum).Sum + ($pad * ($sizes.Count + 1)))
    $ph = [int](512 + ($pad * 2))
    $pv = New-Object System.Drawing.Bitmap($pw, $ph)
    $pg = [System.Drawing.Graphics]::FromImage($pv)
    $pg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $pg.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $pg.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $pg.Clear([System.Drawing.Color]::FromArgb(255, 232, 232, 232))
    $x = [float]$pad
    foreach ($s in $sizes) {
        $pg.DrawImage($bmp, $x, [float]($ph - $pad - $s), [float]$s, [float]$s)
        $x += [float]($s + $pad)
    }
    $pg.Dispose()
    $pv.Save($Preview, [System.Drawing.Imaging.ImageFormat]::Png)
    $pv.Dispose()
    Write-Output ("preview -> " + $Preview + "  sizes " + ($sizes -join '/') + " px")
}
$bmp.Dispose()
