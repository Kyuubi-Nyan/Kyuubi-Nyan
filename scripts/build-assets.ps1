param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Drawing.Common -ErrorAction SilentlyContinue

$sourceDir = Join-Path $Root 'assets\source'
$assetDir = Join-Path $Root 'assets'
$catgirlSource = Join-Path $sourceDir 'catgirl-source.jpg'
$starfieldSource = Join-Path $sourceDir 'starfield-source.jpg'
$catgirlOutput = Join-Path $assetDir 'catgirl-blue.png'
$bannerOutput = Join-Path $assetDir 'banner.png'

$drawingAssembly = [System.Drawing.Bitmap].Assembly.Location
$drawingDirectory = Split-Path -Parent $drawingAssembly
$gdiPlusAssembly = Join-Path $drawingDirectory 'System.Private.Windows.GdiPlus.dll'
$windowsCoreAssembly = Join-Path $drawingDirectory 'System.Private.Windows.Core.dll'
$drawingPrimitivesAssembly = Join-Path $drawingDirectory 'System.Drawing.Primitives.dll'
Add-Type -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public static class IcyArt
{
    public static void Recolor(string inputPath, string outputPath)
    {
        using (var source = new Bitmap(inputPath))
        using (var output = new Bitmap(source.Width, source.Height, PixelFormat.Format32bppArgb))
        {
            using (var graphics = Graphics.FromImage(output))
            {
                graphics.CompositingMode = System.Drawing.Drawing2D.CompositingMode.SourceCopy;
                graphics.DrawImage(source, 0, 0, source.Width, source.Height);
            }

            var rect = new Rectangle(0, 0, output.Width, output.Height);
            var data = output.LockBits(rect, ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
            try
            {
                int count = data.Stride * data.Height;
                var bytes = new byte[count];
                Marshal.Copy(data.Scan0, bytes, 0, count);

                for (int y = 0; y < data.Height; y++)
                {
                    int row = y * data.Stride;
                    for (int x = 0; x < data.Width; x++)
                    {
                        int i = row + x * 4;
                        double b = bytes[i] / 255.0;
                        double g = bytes[i + 1] / 255.0;
                        double r = bytes[i + 2] / 255.0;

                        double h, s, l;
                        RgbToHsl(r, g, b, out h, out s, out l);

                        // Recolor only the pink/magenta family. Skin tones remain warm.
                        bool pinkFamily = (h >= 290.0 && s >= 0.025 && l >= 0.10);
                        if (pinkFamily)
                        {
                            double newHue = 202.0 + ((h - 290.0) / 70.0) * 16.0;
                            double newSat = Math.Min(0.40, Math.Max(0.015, s * 0.58));
                            double liftedLight = Math.Min(0.96, l + (1.0 - l) * 0.10);
                            HslToRgb(newHue, newSat, liftedLight, out r, out g, out b);
                        }

                        // A restrained ice-blue grade keeps the whole composition cohesive.
                        r = Clamp01(r * 0.985 + 0.006);
                        g = Clamp01(g * 0.995 + 0.008);
                        b = Clamp01(b * 1.015 + 0.010);

                        bytes[i] = ToByte(b);
                        bytes[i + 1] = ToByte(g);
                        bytes[i + 2] = ToByte(r);
                        bytes[i + 3] = 255;
                    }
                }

                Marshal.Copy(bytes, 0, data.Scan0, count);
            }
            finally
            {
                output.UnlockBits(data);
            }

            output.Save(outputPath, ImageFormat.Png);
        }
    }

    public static void MakeFeatheredPortrait(string inputPath, string outputPath, int featherWidth)
    {
        using (var source = new Bitmap(inputPath))
        using (var output = new Bitmap(source.Width, source.Height, PixelFormat.Format32bppArgb))
        {
            using (var graphics = Graphics.FromImage(output))
            {
                graphics.CompositingMode = System.Drawing.Drawing2D.CompositingMode.SourceCopy;
                graphics.DrawImage(source, 0, 0, source.Width, source.Height);
            }

            var rect = new Rectangle(0, 0, output.Width, output.Height);
            var data = output.LockBits(rect, ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
            try
            {
                int count = data.Stride * data.Height;
                var bytes = new byte[count];
                Marshal.Copy(data.Scan0, bytes, 0, count);
                for (int y = 0; y < data.Height; y++)
                {
                    int row = y * data.Stride;
                    for (int x = 0; x < featherWidth; x++)
                    {
                        double alpha = featherWidth <= 1 ? 1.0 : (double)x / (featherWidth - 1);
                        int i = row + x * 4;
                        bytes[i + 3] = (byte)(bytes[i + 3] * alpha);
                    }
                }
                Marshal.Copy(bytes, 0, data.Scan0, count);
            }
            finally
            {
                output.UnlockBits(data);
            }

            output.Save(outputPath, ImageFormat.Png);
        }
    }

    private static void RgbToHsl(double r, double g, double b, out double h, out double s, out double l)
    {
        double max = Math.Max(r, Math.Max(g, b));
        double min = Math.Min(r, Math.Min(g, b));
        l = (max + min) / 2.0;
        double d = max - min;
        if (d < 1e-8) { h = 0; s = 0; return; }
        s = l > 0.5 ? d / (2.0 - max - min) : d / (max + min);
        if (max == r) h = (g - b) / d + (g < b ? 6.0 : 0.0);
        else if (max == g) h = (b - r) / d + 2.0;
        else h = (r - g) / d + 4.0;
        h *= 60.0;
    }

    private static void HslToRgb(double h, double s, double l, out double r, out double g, out double b)
    {
        if (s <= 0) { r = g = b = l; return; }
        double q = l < 0.5 ? l * (1.0 + s) : l + s - l * s;
        double p = 2.0 * l - q;
        h = ((h % 360.0) + 360.0) % 360.0 / 360.0;
        r = HueToRgb(p, q, h + 1.0 / 3.0);
        g = HueToRgb(p, q, h);
        b = HueToRgb(p, q, h - 1.0 / 3.0);
    }

    private static double HueToRgb(double p, double q, double t)
    {
        if (t < 0) t += 1;
        if (t > 1) t -= 1;
        if (t < 1.0 / 6.0) return p + (q - p) * 6.0 * t;
        if (t < 1.0 / 2.0) return q;
        if (t < 2.0 / 3.0) return p + (q - p) * (2.0 / 3.0 - t) * 6.0;
        return p;
    }

    private static double Clamp01(double value)
    {
        return Math.Max(0.0, Math.Min(1.0, value));
    }

    private static byte ToByte(double value)
    {
        return (byte)Math.Round(Clamp01(value) * 255.0);
    }
}
"@ -ReferencedAssemblies @($drawingAssembly, $gdiPlusAssembly, $windowsCoreAssembly, $drawingPrimitivesAssembly)

[IcyArt]::Recolor($catgirlSource, $catgirlOutput)
$featheredPortrait = Join-Path $env:TEMP 'kyuubi-catgirl-feathered.png'
[IcyArt]::MakeFeatheredPortrait($catgirlOutput, $featheredPortrait, 140)

$width = 1600
$height = 560
$canvas = New-Object System.Drawing.Bitmap($width, $height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$graphics = [System.Drawing.Graphics]::FromImage($canvas)
$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

try {
    $background = [System.Drawing.Image]::FromFile($starfieldSource)
    try {
        $scale = [Math]::Max($width / $background.Width, $height / $background.Height)
        $drawWidth = [int][Math]::Ceiling($background.Width * $scale)
        $drawHeight = [int][Math]::Ceiling($background.Height * $scale)
        $drawX = [int](($width - $drawWidth) / 2)
        $drawY = [int](($height - $drawHeight) / 2)
        $graphics.DrawImage($background, $drawX, $drawY, $drawWidth, $drawHeight)
    }
    finally {
        $background.Dispose()
    }

    $overlay = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.Rectangle(0, 0, $width, $height)),
        [System.Drawing.Color]::FromArgb(238, 3, 12, 29),
        [System.Drawing.Color]::FromArgb(0, 4, 16, 36),
        [System.Drawing.Drawing2D.LinearGradientMode]::Horizontal
    )
    try {
        $blend = New-Object System.Drawing.Drawing2D.ColorBlend(3)
        $blend.Colors = @(
            [System.Drawing.Color]::FromArgb(242, 3, 12, 29),
            [System.Drawing.Color]::FromArgb(132, 4, 21, 43),
            [System.Drawing.Color]::FromArgb(5, 4, 16, 36)
        )
        $blend.Positions = @(0.0, 0.54, 1.0)
        $overlay.InterpolationColors = $blend
        $graphics.FillRectangle($overlay, 0, 0, $width, $height)
    }
    finally {
        $overlay.Dispose()
    }

    $portrait = [System.Drawing.Image]::FromFile($featheredPortrait)
    try {
        $targetWidth = 458
        $targetHeight = 687
        $targetX = 1138
        $targetY = -56
        $graphics.DrawImage($portrait, $targetX, $targetY, $targetWidth, $targetHeight)
    }
    finally {
        $portrait.Dispose()
    }

    $linePen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(155, 132, 220, 247), 2)
    try {
        $graphics.DrawLine($linePen, 92, 450, 1010, 450)
    }
    finally {
        $linePen.Dispose()
    }

    $cyan = [System.Drawing.Color]::FromArgb(238, 162, 230, 255)
    $white = [System.Drawing.Color]::FromArgb(247, 249, 255)
    $soft = [System.Drawing.Color]::FromArgb(205, 221, 241, 255)
    $pink = [System.Drawing.Color]::FromArgb(235, 255, 143, 199)

    $fontLabel = New-Object System.Drawing.Font('Segoe UI', 13, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    $fontTitle = New-Object System.Drawing.Font('Segoe UI', 55, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $fontChinese = New-Object System.Drawing.Font('Microsoft YaHei UI', 27, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $fontBody = New-Object System.Drawing.Font('Segoe UI', 18, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    $fontFooter = New-Object System.Drawing.Font('Segoe UI', 13, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    $brushLabel = New-Object System.Drawing.SolidBrush($cyan)
    $brushTitle = New-Object System.Drawing.SolidBrush($white)
    $brushSoft = New-Object System.Drawing.SolidBrush($soft)
    $brushPink = New-Object System.Drawing.SolidBrush($pink)
    try {
        $graphics.DrawString('GITHUB PROFILE / 01', $fontLabel, $brushLabel, 94, 78)
        $graphics.DrawString('Kyuubi-Nyan', $fontTitle, $brushTitle, 88, 108)
        $graphics.DrawString('路虽远，行则必至。', $fontChinese, $brushSoft, 94, 208)
        $graphics.DrawString('Rust  ·  Automation  ·  Anime', $fontBody, $brushLabel, 96, 259)
        $graphics.DrawString('SYSTEM ONLINE   /   NYAN MODE', $fontFooter, $brushPink, 94, 478)
    }
    finally {
        $fontLabel.Dispose(); $fontTitle.Dispose(); $fontChinese.Dispose(); $fontBody.Dispose(); $fontFooter.Dispose()
        $brushLabel.Dispose(); $brushTitle.Dispose(); $brushSoft.Dispose(); $brushPink.Dispose()
    }

    $graphics.Flush()
    $canvas.Save($bannerOutput, [System.Drawing.Imaging.ImageFormat]::Png)
}
finally {
    $graphics.Dispose()
    $canvas.Dispose()
    if (Test-Path -LiteralPath $featheredPortrait) { Remove-Item -LiteralPath $featheredPortrait -Force }
}

Write-Output "Built $catgirlOutput"
Write-Output "Built $bannerOutput"







