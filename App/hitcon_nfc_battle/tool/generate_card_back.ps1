param(
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing

function New-RoundedRectanglePath {
    param(
        [System.Drawing.RectangleF]$Rectangle,
        [single]$Radius
    )

    $diameter = $Radius * 2
    $path = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $path.AddArc($Rectangle.Left, $Rectangle.Top, $diameter, $diameter, 180, 90)
    $path.AddArc($Rectangle.Right - $diameter, $Rectangle.Top, $diameter, $diameter, 270, 90)
    $path.AddArc($Rectangle.Right - $diameter, $Rectangle.Bottom - $diameter, $diameter, $diameter, 0, 90)
    $path.AddArc($Rectangle.Left, $Rectangle.Bottom - $diameter, $diameter, $diameter, 90, 90)
    $path.CloseFigure()
    return $path
}

function New-PixelBorderPoints {
    param(
        [single]$Left,
        [single]$Top,
        [single]$Right,
        [single]$Bottom,
        [single]$Cut
    )

    return [System.Drawing.PointF[]]@(
        [System.Drawing.PointF]::new($Left + $Cut, $Top),
        [System.Drawing.PointF]::new($Right - $Cut, $Top),
        [System.Drawing.PointF]::new($Right, $Top + $Cut),
        [System.Drawing.PointF]::new($Right, $Bottom - $Cut),
        [System.Drawing.PointF]::new($Right - $Cut, $Bottom),
        [System.Drawing.PointF]::new($Left + $Cut, $Bottom),
        [System.Drawing.PointF]::new($Left, $Bottom - $Cut),
        [System.Drawing.PointF]::new($Left, $Top + $Cut)
    )
}

function Draw-CircuitTrace {
    param(
        [System.Drawing.Graphics]$Graphics,
        [System.Drawing.Pen]$Pen,
        [System.Drawing.Brush]$NodeBrush,
        [System.Drawing.PointF[]]$Points
    )

    $Graphics.DrawLines($Pen, $Points)
    $last = $Points[$Points.Length - 1]
    $Graphics.FillRectangle($NodeBrush, $last.X - 10, $last.Y - 10, 20, 20)
}

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $projectRoot 'assets\images\card_back_hitcon_nfc_battle_v1.png'
}
elseif (-not [System.IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath = Join-Path $projectRoot $OutputPath
}

$outputDirectory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outputDirectory)) {
    [System.IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
}

$appIconPath = Join-Path $projectRoot 'assets\app_icon\app_icon_master.png'
$panasonicLogoPath = Join-Path $projectRoot 'assets\images\panasonic_logo_white.png'
$fontPath = Join-Path $projectRoot 'assets\fonts\unifont_t-17.0.04.otf'

$width = 1276
$height = 2022
$bitmap = [System.Drawing.Bitmap]::new(
    $width,
    $height,
    [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$appIcon = $null
$panasonicLogo = $null
$privateFonts = $null
$titleFont = $null
$subtitleFont = $null
$captionFont = $null
$backgroundBrush = $null
$cyanPen = $null
$magentaPen = $null

try {
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

    $backgroundRect = [System.Drawing.Rectangle]::new(0, 0, $width, $height)
    $backgroundBrush = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
        $backgroundRect,
        [System.Drawing.Color]::FromArgb(255, 34, 0, 47),
        [System.Drawing.Color]::FromArgb(255, 6, 0, 13),
        90
    )
    $backgroundBlend = [System.Drawing.Drawing2D.ColorBlend]::new(3)
    $backgroundBlend.Colors = [System.Drawing.Color[]]@(
        [System.Drawing.Color]::FromArgb(255, 30, 0, 42),
        [System.Drawing.Color]::FromArgb(255, 15, 0, 24),
        [System.Drawing.Color]::FromArgb(255, 7, 0, 13)
    )
    $backgroundBlend.Positions = [single[]]@(0.0, 0.58, 1.0)
    $backgroundBrush.InterpolationColors = $backgroundBlend
    $graphics.FillRectangle($backgroundBrush, $backgroundRect)

    $gridPen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(22, 0, 245, 255), 2)
    try {
        for ($x = 63; $x -lt $width; $x += 64) {
            $graphics.DrawLine($gridPen, $x, 0, $x, $height)
        }
        for ($y = 51; $y -lt $height; $y += 64) {
            $graphics.DrawLine($gridPen, 0, $y, $width, $y)
        }
    }
    finally {
        $gridPen.Dispose()
    }

    $cyanTracePen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(46, 0, 245, 255), 6)
    $magentaTracePen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(42, 255, 23, 233), 6)
    $cyanNodeBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(70, 0, 245, 255))
    $magentaNodeBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(66, 255, 23, 233))
    try {
        Draw-CircuitTrace $graphics $cyanTracePen $cyanNodeBrush ([System.Drawing.PointF[]]@(
            [System.Drawing.PointF]::new(0, 600),
            [System.Drawing.PointF]::new(136, 600),
            [System.Drawing.PointF]::new(188, 652),
            [System.Drawing.PointF]::new(260, 652)
        ))
        Draw-CircuitTrace $graphics $magentaTracePen $magentaNodeBrush ([System.Drawing.PointF[]]@(
            [System.Drawing.PointF]::new($width, 820),
            [System.Drawing.PointF]::new($width - 132, 820),
            [System.Drawing.PointF]::new($width - 184, 872),
            [System.Drawing.PointF]::new($width - 260, 872)
        ))
        Draw-CircuitTrace $graphics $cyanTracePen $cyanNodeBrush ([System.Drawing.PointF[]]@(
            [System.Drawing.PointF]::new(0, 1604),
            [System.Drawing.PointF]::new(164, 1604),
            [System.Drawing.PointF]::new(224, 1544),
            [System.Drawing.PointF]::new(312, 1544)
        ))
        Draw-CircuitTrace $graphics $magentaTracePen $magentaNodeBrush ([System.Drawing.PointF[]]@(
            [System.Drawing.PointF]::new($width, 1484),
            [System.Drawing.PointF]::new($width - 156, 1484),
            [System.Drawing.PointF]::new($width - 220, 1420),
            [System.Drawing.PointF]::new($width - 316, 1420)
        ))
    }
    finally {
        $cyanTracePen.Dispose()
        $magentaTracePen.Dispose()
        $cyanNodeBrush.Dispose()
        $magentaNodeBrush.Dispose()
    }

    $cyanPen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(255, 0, 245, 255), 10)
    $magentaPen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(255, 255, 23, 233), 6)
    $cyanPen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Miter
    $magentaPen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Miter
    $graphics.DrawPolygon($cyanPen, (New-PixelBorderPoints 48 48 1228 1974 44))
    $graphics.DrawPolygon($magentaPen, (New-PixelBorderPoints 78 78 1198 1944 34))

    $cornerMagenta = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 255, 23, 233))
    $cornerCyan = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 0, 245, 255))
    try {
        $graphics.FillRectangle($cornerMagenta, 102, 102, 76, 12)
        $graphics.FillRectangle($cornerMagenta, 102, 102, 12, 76)
        $graphics.FillRectangle($cornerCyan, 1098, 1908, 76, 12)
        $graphics.FillRectangle($cornerCyan, 1162, 1844, 12, 76)
    }
    finally {
        $cornerMagenta.Dispose()
        $cornerCyan.Dispose()
    }

    $appIcon = [System.Drawing.Image]::FromFile($appIconPath)
    $iconRect = [System.Drawing.RectangleF]::new(278, 236, 720, 720)
    $iconPath = New-RoundedRectanglePath $iconRect 84
    $cyanGlowPen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(88, 0, 245, 255), 32)
    $magentaGlowPen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(88, 255, 23, 233), 32)
    try {
        $graphics.DrawPath($cyanGlowPen, $iconPath)
        $graphics.TranslateTransform(-10, -10)
        $graphics.DrawPath($magentaGlowPen, $iconPath)
        $graphics.ResetTransform()

        $savedState = $graphics.Save()
        $graphics.SetClip($iconPath)
        $graphics.DrawImage($appIcon, $iconRect)
        $graphics.Restore($savedState)
    }
    finally {
        $iconPath.Dispose()
        $cyanGlowPen.Dispose()
        $magentaGlowPen.Dispose()
    }

    $privateFonts = [System.Drawing.Text.PrivateFontCollection]::new()
    $privateFonts.AddFontFile($fontPath)
    $fontFamily = $privateFonts.Families[0]
    $titleFont = [System.Drawing.Font]::new($fontFamily, 152, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    $subtitleFont = [System.Drawing.Font]::new($fontFamily, 94, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    $captionFont = [System.Drawing.Font]::new($fontFamily, 44, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    $centerFormat = [System.Drawing.StringFormat]::new()
    $centerFormat.Alignment = [System.Drawing.StringAlignment]::Center
    $centerFormat.LineAlignment = [System.Drawing.StringAlignment]::Center
    $centerFormat.FormatFlags = [System.Drawing.StringFormatFlags]::NoWrap

    $titleRect = [System.Drawing.RectangleF]::new(80, 1010, 1116, 170)
    $whiteBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::White)
    $cyanBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 0, 245, 255))
    $magentaBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 255, 23, 233))
    try {
        $cyanTitleRect = [System.Drawing.RectangleF]::new($titleRect.X + 8, $titleRect.Y + 6, $titleRect.Width, $titleRect.Height)
        $magentaTitleRect = [System.Drawing.RectangleF]::new($titleRect.X - 8, $titleRect.Y - 6, $titleRect.Width, $titleRect.Height)
        $graphics.DrawString('HITCON', $titleFont, $cyanBrush, $cyanTitleRect, $centerFormat)
        $graphics.DrawString('HITCON', $titleFont, $magentaBrush, $magentaTitleRect, $centerFormat)
        $graphics.DrawString('HITCON', $titleFont, $whiteBrush, $titleRect, $centerFormat)

        $subtitleShadowRect = [System.Drawing.RectangleF]::new(80 + 6, 1195 + 6, 1116, 116)
        $subtitleRect = [System.Drawing.RectangleF]::new(80, 1195, 1116, 116)
        $graphics.DrawString('NFC BATTLE', $subtitleFont, $cyanBrush, $subtitleShadowRect, $centerFormat)
        $graphics.DrawString('NFC BATTLE', $subtitleFont, $magentaBrush, $subtitleRect, $centerFormat)

        $graphics.FillRectangle($magentaBrush, 236, 1390, 28, 28)
        $dividerBrush = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
            [System.Drawing.Rectangle]::new(284, 1400, 708, 8),
            [System.Drawing.Color]::FromArgb(255, 255, 23, 233),
            [System.Drawing.Color]::FromArgb(255, 0, 245, 255),
            0
        )
        try {
            $graphics.FillRectangle($dividerBrush, 284, 1400, 708, 8)
        }
        finally {
            $dividerBrush.Dispose()
        }
        $graphics.FillRectangle($cyanBrush, 1012, 1390, 28, 28)

        $captionRect = [System.Drawing.RectangleF]::new(386, 1682, 504, 62)
        $leftFormat = [System.Drawing.StringFormat]::new()
        try {
            $leftFormat.Alignment = [System.Drawing.StringAlignment]::Near
            $leftFormat.LineAlignment = [System.Drawing.StringAlignment]::Center
            $graphics.DrawString('Supported by', $captionFont, $whiteBrush, $captionRect, $leftFormat)
        }
        finally {
            $leftFormat.Dispose()
        }
    }
    finally {
        $whiteBrush.Dispose()
        $cyanBrush.Dispose()
        $magentaBrush.Dispose()
        $centerFormat.Dispose()
    }

    $panasonicLogo = [System.Drawing.Image]::FromFile($panasonicLogoPath)
    $logoWidth = 504
    $logoHeight = [int][Math]::Round($logoWidth * $panasonicLogo.Height / $panasonicLogo.Width)
    $graphics.DrawImage($panasonicLogo, 386, 1750, $logoWidth, $logoHeight)

    $bitmap.SetResolution(600, 600)
    $bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Output $OutputPath
}
finally {
    if ($cyanPen) { $cyanPen.Dispose() }
    if ($magentaPen) { $magentaPen.Dispose() }
    if ($backgroundBrush) { $backgroundBrush.Dispose() }
    if ($titleFont) { $titleFont.Dispose() }
    if ($subtitleFont) { $subtitleFont.Dispose() }
    if ($captionFont) { $captionFont.Dispose() }
    if ($privateFonts) { $privateFonts.Dispose() }
    if ($appIcon) { $appIcon.Dispose() }
    if ($panasonicLogo) { $panasonicLogo.Dispose() }
    $graphics.Dispose()
    $bitmap.Dispose()
}
