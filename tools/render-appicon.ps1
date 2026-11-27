# Renders the PassCard app icon at 1024x1024 with GDI+, plus a multi-size preview
# so the mark can be judged at home-screen scale before it ships.
#
#   powershell -ExecutionPolicy Bypass -File tools\render-appicon.ps1
#
# The icon is a geometric mark, so it is drawn rather than generated: exact
# colours, no raster artefacts, and every proportion below is a number that can
# be tweaked and re-rendered. iOS masks the artwork to a squircle, so the
# background must bleed to all four edges and the card must stay inside the
# central ~824px safe area (the rotated card spans ~770px here).
#
# The card is composited on an offscreen bitmap and the tear notches are erased
# with CompositingMode SourceCopy. Doing the notches as part of one GraphicsPath
# with FillMode Alternate looks tempting and is wrong: the half of each circle
# that lies outside the card counts as odd and gets FILLED, producing a bump
# where a bite belongs.
#
# ASCII-only output on purpose: a GBK console mangles CJK, so a Chinese print
# would make this script's own progress unreadable.

param(
    [string]$Repo = (Split-Path -Parent $PSScriptRoot),
    [string]$Out = $null,
    [string]$Preview = $null
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

if (-not $Out) {
    # Never default to the shipped catalog asset: the illustrated icon lives
    # there now, and re-running this geometric renderer must not clobber it.
    $Out = Join-Path $PSScriptRoot 'icon-geometric-1024.png'
}
if (-not $Preview) {
    $Preview = Join-Path $PSScriptRoot 'icon-preview.png'
}

$S = 1024

# --- palette ---------------------------------------------------------------
$bgTop     = [System.Drawing.Color]::FromArgb(255,  9,  49,  55)   # deep ink teal
$bgBottom  = [System.Drawing.Color]::FromArgb(255,  3,  23,  27)
$cardLight = [System.Drawing.Color]::FromArgb(255,255,196,104)   # warm amber
$cardDark  = [System.Drawing.Color]::FromArgb(255,224,122, 31)
$ink       = [System.Drawing.Color]::FromArgb(255,  7,  50,  58)   # bars, ties to bg
$perf      = [System.Drawing.Color]::FromArgb(160,120, 62,  10)

# --- card geometry, in card-local coordinates ------------------------------
$CW = 720.0; $CH = 450.0        # card size
$CR = 60.0                      # corner radius
$PX = 185.0                     # perforation x; the stub is this wide
$NR = 40.0                      # tear-notch radius
$TILT = -7.0                    # degrees
$M  = 64.0                      # offscreen margin so the tilt has room

function New-RoundedPath([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $r * 2
    $p.AddArc($x, $y, $d, $d, 180, 90)
    $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

function New-QGraphics([System.Drawing.Bitmap]$b) {
    $q = [System.Drawing.Graphics]::FromImage($b)
    $q.SmoothingMode        = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $q.InterpolationMode    = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $q.PixelOffsetMode      = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $q.CompositingQuality   = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    return $q
}

# --- the card, offscreen ----------------------------------------------------
$ow = [int]($CW + 2 * $M); $oh = [int]($CH + 2 * $M)
$cardBmp = New-Object System.Drawing.Bitmap($ow, $oh)
$cg = New-QGraphics $cardBmp

$cardRect = New-Object System.Drawing.RectangleF($M, $M, $CW, $CH)
$cardBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    $cardRect, $cardLight, $cardDark, 55.0)
$cardPath = New-RoundedPath $M $M $CW $CH $CR
$cg.FillPath($cardBrush, $cardPath)

# Printed-detail bars on the main half. Nothing thinner than 52px survives the
# drop to 60pt, and the stub half stays empty on purpose - negative space is
# what keeps the mark readable once iOS shrinks it.
$barX = $M + $PX + 68.0
$barH = 52.0
$barR = 26.0
$inkBrush = New-Object System.Drawing.SolidBrush($ink)
foreach ($bar in @(@(100.0, 399.0), @(192.0, 300.0), @(284.0, 355.0))) {
    $bp = New-RoundedPath ([float]$barX) ([float]($M + $bar[0])) ([float]$bar[1]) ([float]$barH) ([float]$barR)
    $cg.FillPath($inkBrush, $bp)
    $bp.Dispose()
}

# Dashed perforation between the notches, stopping short of both.
$perfPen = New-Object System.Drawing.Pen($perf, 7.0)
$perfPen.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash
$cg.DrawLine($perfPen, [float]($M + $PX), [float]($M + $NR + 12),
                        [float]($M + $PX), [float]($M + $CH - $NR - 12))
$perfPen.Dispose()

# Erase the tear notches: SourceCopy REPLACES the pixels with transparent,
# which is the bite. Doing this before the bars would be equally safe - the
# notches and the bars never overlap.
$cg.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
$erase = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::Transparent)
$cg.FillEllipse($erase, [float]($M + $PX - $NR), [float]($M - $NR), [float]($NR * 2), [float]($NR * 2))
$cg.FillEllipse($erase, [float]($M + $PX - $NR), [float]($M + $CH - $NR), [float]($NR * 2), [float]($NR * 2))
$cg.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
$erase.Dispose(); $inkBrush.Dispose(); $cardBrush.Dispose(); $cardPath.Dispose(); $cg.Dispose()

# --- the canvas -------------------------------------------------------------
$bmp = New-Object System.Drawing.Bitmap($S, $S)
$g = New-QGraphics $bmp

# Backdrop bleeds to every edge: iOS crops it, it never letterboxes.
$full = New-Object System.Drawing.Rectangle(0, 0, $S, $S)
$bgBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($full, $bgTop, $bgBottom, 90.0)
$g.FillRectangle($bgBrush, $full)

$g.TranslateTransform([float]($S / 2), [float]($S / 2))
$g.RotateTransform($TILT)
$g.DrawImage($cardBmp, [int](-$ow / 2), [int](-$oh / 2))
$g.ResetTransform()

$bgBrush.Dispose(); $g.Dispose(); $cardBmp.Dispose()

$outDir = Split-Path -Parent $Out
if (-not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
Write-Output ("icon  -> " + $Out + "  (" + (Get-Item -LiteralPath $Out).Length + " bytes)")

# --- preview at home-screen sizes ------------------------------------------
# The whole point of the exercise is that it must still read at 60px, which
# cannot be judged from a 1024px original.
$sizes = @(512, 180, 120, 60)
$pad = 40
# [int] casts are not cosmetic: Measure-Object -Sum yields a double and
# Bitmap(double, int) matches no constructor.
$pw = [int](($sizes | Measure-Object -Sum).Sum + ($pad * ($sizes.Count + 1)))
$ph = [int](512 + ($pad * 2))
$pv = New-Object System.Drawing.Bitmap($pw, $ph)
$pg = New-QGraphics $pv
$pg.Clear([System.Drawing.Color]::FromArgb(255, 232, 232, 232))

$x = [float]$pad
foreach ($s in $sizes) {
    $pg.DrawImage($bmp, $x, [float]($ph - $pad - $s), [float]$s, [float]$s)
    $x += [float]($s + $pad)
}
$pg.Dispose()
$pv.Save($Preview, [System.Drawing.Imaging.ImageFormat]::Png)
$pv.Dispose()
$bmp.Dispose()
Write-Output ("preview -> " + $Preview + "  sizes " + ($sizes -join '/') + " px")
