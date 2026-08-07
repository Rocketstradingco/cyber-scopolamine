param(
    [string]$OutDir = (Join-Path (Split-Path -Parent $PSScriptRoot) 'assets')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function New-BrugmansiaBitmap {
    param([int]$Size)

    $bmp = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g   = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

    $s = $Size / 256.0
    function P { param($x, $y) New-Object System.Drawing.PointF(($x * $s), ($y * $s)) }

    $bg = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 11, 7, 16))
    $rect = New-Object System.Drawing.RectangleF(0, 0, $Size, $Size)
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $r = 44 * $s
    $path.AddArc(0, 0, $r, $r, 180, 90)
    $path.AddArc($Size - $r, 0, $r, $r, 270, 90)
    $path.AddArc($Size - $r, $Size - $r, $r, $r, 0, 90)
    $path.AddArc(0, $Size - $r, $r, $r, 90, 90)
    $path.CloseFigure()
    $g.FillPath($bg, $path)
    $g.SetClip($path)

    $glowRect = New-Object System.Drawing.RectangleF((30 * $s), (20 * $s), (196 * $s), (216 * $s))
    $glowPath = New-Object System.Drawing.Drawing2D.GraphicsPath
    $glowPath.AddEllipse($glowRect)
    $glow = New-Object System.Drawing.Drawing2D.PathGradientBrush($glowPath)
    $glow.CenterColor = [System.Drawing.Color]::FromArgb(120, 168, 85, 247)
    $glow.SurroundColors = @([System.Drawing.Color]::FromArgb(0, 168, 85, 247))
    $g.FillEllipse($glow, $glowRect)

    $stemPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 92, 208, 150), (8 * $s))
    $stemPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $stemPen.EndCap   = [System.Drawing.Drawing2D.LineCap]::Round
    $g.DrawBezier($stemPen, (P 104 16), (P 122 20), (P 128 30), (P 128 44))

    $calyx = New-Object System.Drawing.Drawing2D.GraphicsPath
    $calyx.AddBezier((P 114 44), (P 112 62), (P 112 74), (P 116 86))
    $calyx.AddLine((P 116 86), (P 140 86))
    $calyx.AddBezier((P 140 86), (P 144 74), (P 144 62), (P 142 44))
    $calyx.CloseFigure()
    $calyxBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 92, 208, 150))
    $g.FillPath($calyxBrush, $calyx)

    $flower = New-Object System.Drawing.Drawing2D.GraphicsPath
    $flower.AddBezier((P 116 82), (P 110 128), (P 78 158), (P 44 198))
    $rim = @(
        (P 44 198), (P 58 214), (P 72 220), (P 86 208),
        (P 100 202), (P 114 216), (P 128 221), (P 142 216),
        (P 156 202), (P 170 208), (P 184 220), (P 198 214), (P 212 198)
    )
    $flower.AddCurve([System.Drawing.PointF[]]$rim, 0.45)
    $flower.AddBezier((P 212 198), (P 178 158), (P 146 128), (P 140 82))
    $flower.CloseFigure()

    $glowPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(90, 168, 85, 247), (14 * $s))
    $glowPen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    $g.DrawPath($glowPen, $flower)

    $grad = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.PointF(0, (70 * $s))),
        (New-Object System.Drawing.PointF(0, (226 * $s))),
        [System.Drawing.Color]::FromArgb(255, 168, 85, 247),
        [System.Drawing.Color]::FromArgb(255, 108, 243, 213))
    $blend = New-Object System.Drawing.Drawing2D.ColorBlend(4)
    $blend.Colors = @(
        [System.Drawing.Color]::FromArgb(255, 186, 92, 255),
        [System.Drawing.Color]::FromArgb(255, 140, 74, 246),
        [System.Drawing.Color]::FromArgb(255, 82, 142, 240),
        [System.Drawing.Color]::FromArgb(255, 116, 246, 214))
    $blend.Positions = @(0.0, 0.42, 0.72, 1.0)
    $grad.InterpolationColors = $blend
    $g.FillPath($grad, $flower)

    $mouth = New-Object System.Drawing.RectangleF((56 * $s), (182 * $s), (144 * $s), (40 * $s))
    $mouthPath = New-Object System.Drawing.Drawing2D.GraphicsPath
    $mouthPath.AddEllipse($mouth)
    $mouthGrad = New-Object System.Drawing.Drawing2D.PathGradientBrush($mouthPath)
    $mouthGrad.CenterColor = [System.Drawing.Color]::FromArgb(215, 14, 8, 22)
    $mouthGrad.SurroundColors = @([System.Drawing.Color]::FromArgb(30, 14, 8, 22))
    $g.FillEllipse($mouthGrad, $mouth)

    $veinPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(120, 236, 233, 225), (2.2 * $s))
    foreach ($tip in @(@(70, 214), @(112, 212), @(128, 216), @(144, 212), @(186, 214))) {
        $g.DrawBezier($veinPen, (P 128 92), (P 128 130), (P $tip[0] 168), (P $tip[0] $tip[1]))
    }

    $edge = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(240, 240, 238, 232), (4 * $s))
    $edge.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    $g.DrawPath($edge, $flower)

    $g.ResetClip()
    $g.Dispose()
    return $bmp
}

$sizes = @(256, 128, 64, 48, 32, 16)
$streams = @()
foreach ($sz in $sizes) {
    $bmp = New-BrugmansiaBitmap -Size $sz
    $ms  = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $streams += ,@($sz, $ms.ToArray())
    if ($sz -eq 256) { $bmp.Save((Join-Path $OutDir 'cyber-scopolamine-256.png'), [System.Drawing.Imaging.ImageFormat]::Png) }
    $bmp.Dispose()
    $ms.Dispose()
}

$icoPath = Join-Path $OutDir 'cyber-scopolamine.ico'
$fs = [System.IO.File]::Create($icoPath)
$bw = New-Object System.IO.BinaryWriter($fs)
$bw.Write([UInt16]0)
$bw.Write([UInt16]1)
$bw.Write([UInt16]$streams.Count)
$offset = 6 + (16 * $streams.Count)
foreach ($e in $streams) {
    $sz = $e[0]; $data = $e[1]
    $bw.Write([Byte]$(if ($sz -ge 256) { 0 } else { $sz }))
    $bw.Write([Byte]$(if ($sz -ge 256) { 0 } else { $sz }))
    $bw.Write([Byte]0)
    $bw.Write([Byte]0)
    $bw.Write([UInt16]1)
    $bw.Write([UInt16]32)
    $bw.Write([UInt32]$data.Length)
    $bw.Write([UInt32]$offset)
    $offset += $data.Length
}
foreach ($e in $streams) { $bw.Write($e[1]) }
$bw.Flush(); $bw.Close(); $fs.Close()

Write-Host "wrote $icoPath ($([math]::Round((Get-Item $icoPath).Length/1KB,1)) KB, $($streams.Count) sizes)"
Write-Host "wrote $(Join-Path $OutDir 'cyber-scopolamine-256.png')"
