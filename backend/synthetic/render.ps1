# Renders synthetic phone screenshots from truth.json. ASCII only on purpose:
# the Chinese text lives in the JSON, which is read with an explicit UTF-8
# encoding, so this file never depends on the script file's own BOM.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root = $PSScriptRoot
$json = [System.IO.File]::ReadAllText((Join-Path $root 'truth.json'), [System.Text.Encoding]::UTF8)
$data = ConvertFrom-Json $json

$W = 1080
$H = 2340

try {
    $family = New-Object System.Drawing.FontFamily('Microsoft YaHei')
} catch {
    $family = [System.Drawing.FontFamily]::GenericSansSerif
}

$bold = [System.Drawing.FontStyle]::Bold
$regular = [System.Drawing.FontStyle]::Regular

function New-Brush([int]$r, [int]$g, [int]$b) {
    return New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, $r, $g, $b))
}

$bgBrush     = New-Brush 242 243 245
$cardBrush   = New-Brush 255 255 255
$darkBrush   = New-Brush 24 24 27
$greyBrush   = New-Brush 138 143 152
$lineBrush   = New-Brush 228 230 234
$blackBrush  = New-Brush 0 0 0

$fStatus  = New-Object System.Drawing.Font($family, 17, $bold)
$fApp     = New-Object System.Drawing.Font($family, 19, $regular)
$fTitle   = New-Object System.Drawing.Font($family, 34, $bold)
$fSub     = New-Object System.Drawing.Font($family, 20, $regular)
$fLabel   = New-Object System.Drawing.Font($family, 20, $regular)
$fValue   = New-Object System.Drawing.Font($family, 25, $bold)
$fFoot    = New-Object System.Drawing.Font($family, 16, $regular)

$pen = New-Object System.Drawing.Pen($lineBrush, 2)

$made = @()
foreach ($item in $data.items) {
    $rows = @($item.rows)
    $rowH = 104
    $cardX = 40
    $cardY = 232
    $cardW = $W - 80
    $rowsY = $cardY + 214
    $barH = 0
    if ($item.barcode) { $barH = 168 }
    $cardH = 214 + ($rows.Count * $rowH) + $barH + 56

    $bmp = New-Object System.Drawing.Bitmap($W, $H)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

    $g.FillRectangle($bgBrush, 0, 0, $W, $H)

    # status bar + app nav bar
    $g.DrawString('9:41', $fStatus, $darkBrush, 52, 46)
    $g.DrawString('5G   100%', $fStatus, $darkBrush, $W - 210, 46)
    $g.DrawString('<', $fTitle, $darkBrush, 48, 118)
    $appSize = $g.MeasureString($item.app, $fApp)
    $g.DrawString($item.app, $fApp, $darkBrush, ($W - $appSize.Width) / 2, 132)

    # card
    $g.FillRectangle($cardBrush, $cardX, $cardY, $cardW, $cardH)
    $accent = $item.accent -split ','
    $accentBrush = New-Brush ([int]$accent[0]) ([int]$accent[1]) ([int]$accent[2])
    $g.FillRectangle($accentBrush, $cardX, $cardY, $cardW, 10)

    $g.DrawString($item.title, $fTitle, $darkBrush, $cardX + 44, $cardY + 44)
    $g.DrawString($item.subtitle, $fSub, $greyBrush, $cardX + 46, $cardY + 118)
    $g.DrawLine($pen, $cardX + 44, $cardY + 178, $cardX + $cardW - 44, $cardY + 178)

    $y = $rowsY
    foreach ($row in $rows) {
        $g.DrawString($row.label, $fLabel, $greyBrush, $cardX + 46, $y)
        $g.DrawString($row.value, $fValue, $darkBrush, $cardX + 340, $y - 4)
        $g.DrawLine($pen, $cardX + 44, $y + 76, $cardX + $cardW - 44, $y + 76)
        $y = $y + $rowH
    }

    if ($item.barcode) {
        # A deterministic fake barcode. It carries no real payload, so any
        # qr_payload the model reports for it is a hallucination worth counting.
        $rnd = New-Object System.Random(11)
        $bx = $cardX + 90
        $by = $y + 30
        $bw = $cardW - 180
        $cx = $bx
        while ($cx -lt ($bx + $bw - 8)) {
            # Not $w: PowerShell variable names are case-insensitive, so $w
            # would silently overwrite the canvas width $W for every later image.
            $barW = 2 + $rnd.Next(0, 7)
            if ($rnd.Next(0, 2) -eq 0) {
                $g.FillRectangle($blackBrush, $cx, $by, $barW, 110)
            }
            $cx = $cx + $barW + 2 + $rnd.Next(0, 4)
        }
        $code = $g.MeasureString('1234 5678 9012 3456', $fFoot)
        $g.DrawString('1234 5678 9012 3456', $fFoot, $greyBrush, ($W - $code.Width) / 2, $by + 120)
    }

    $outPath = Join-Path $root $item.file
    $bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose()
    $bmp.Dispose()
    $accentBrush.Dispose()

    $made += ('{0}  {1}x{2}  rows={3}' -f $item.file, $W, $H, $rows.Count)
}

$pen.Dispose()
$fFoot.Dispose(); $fValue.Dispose(); $fLabel.Dispose(); $fSub.Dispose()
$fTitle.Dispose(); $fApp.Dispose(); $fStatus.Dispose()
$family.Dispose()

$made | ForEach-Object { Write-Output $_ }
Write-Output ('rendered {0} images into {1}' -f $made.Count, $root)
