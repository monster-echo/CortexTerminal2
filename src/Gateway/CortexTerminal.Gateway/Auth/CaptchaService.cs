using System.Collections.Concurrent;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using Microsoft.IdentityModel.Tokens;
using SkiaSharp;

namespace CortexTerminal.Gateway.Auth;

public sealed class CaptchaService
{
    private readonly ConcurrentDictionary<string, CaptchaEntry> _entries = new();
    private readonly int _tolerance;
    private readonly string _signingKey;

    private const int ImageWidth = 300;
    private const int ImageHeight = 180;
    private const int PieceSize = 44;
    private const int PiecePadding = 8;
    private const int InitialPieceX = PieceSize / 2 + PiecePadding;

    public CaptchaService(IConfiguration configuration)
    {
        _tolerance = configuration.GetValue("Captcha:TolerancePixels", 5);
        _signingKey = configuration["Auth:SigningKey"] ?? "gateway-auth-signing-key-minimum-32b";
    }

    public CaptchaChallenge Generate()
    {
        Cleanup();

        using var background = new SKBitmap(ImageWidth, ImageHeight);
        using var canvas = new SKCanvas(background);
        canvas.Clear(SKColors.White);

        // Draw colorful gradient background
        var rng = Random.Shared;
        var colors = new[]
        {
            SKColor.FromHsv(rng.Next(360), rng.Next(60, 90), rng.Next(60, 90)),
            SKColor.FromHsv(rng.Next(360), rng.Next(60, 90), rng.Next(60, 90)),
            SKColor.FromHsv(rng.Next(360), rng.Next(60, 90), rng.Next(60, 90)),
        };

        for (var i = 0; i < colors.Length - 1; i++)
        {
            var y0 = i * ImageHeight / (colors.Length - 1);
            var y1 = (i + 1) * ImageHeight / (colors.Length - 1);
            using var shader = SKShader.CreateLinearGradient(new SKPoint(0, y0), new SKPoint(ImageWidth, y1),
                [colors[i], colors[i + 1]], SKShaderTileMode.Clamp);
            using var paint = new SKPaint { Shader = shader };
            canvas.DrawRect(0, y0, ImageWidth, y1 - y0 + 1, paint);
        }

        // Draw random shapes for visual noise
        for (var i = 0; i < 15; i++)
        {
            using var paint = new SKPaint
            {
                Color = new SKColor((uint)rng.Next()),
                Style = SKPaintStyle.Fill,
                IsAntialias = true,
            };
            var shape = rng.Next(3);
            if (shape == 0)
            {
                canvas.DrawCircle(rng.Next(ImageWidth), rng.Next(ImageHeight), rng.Next(5, 20), paint);
            }
            else if (shape == 1)
            {
                canvas.DrawRect(rng.Next(ImageWidth), rng.Next(ImageHeight), rng.Next(10, 40), rng.Next(10, 40), paint);
            }
            else
            {
                using var path = new SKPath();
                path.MoveTo(rng.Next(ImageWidth), rng.Next(ImageHeight));
                path.LineTo(rng.Next(ImageWidth), rng.Next(ImageHeight));
                path.LineTo(rng.Next(ImageWidth), rng.Next(ImageHeight));
                path.Close();
                canvas.DrawPath(path, paint);
            }
        }

        // Calculate puzzle piece position
        var targetX = rng.Next(PiecePadding + PieceSize, ImageWidth - PiecePadding - PieceSize);
        var targetY = rng.Next(PiecePadding + PieceSize, ImageHeight - PiecePadding - PieceSize);

        // Draw puzzle hole on background (darkened area)
        var holePath = CreatePuzzlePiecePath(targetX, targetY);
        using (var holePaint = new SKPaint
        {
            Color = new SKColor(0, 0, 0, 100),
            Style = SKPaintStyle.Fill,
            IsAntialias = true,
        })
        {
            canvas.DrawPath(holePath, holePaint);
        }
        using (var holeStroke = new SKPaint
        {
            Color = SKColors.White.WithAlpha(180),
            Style = SKPaintStyle.Stroke,
            StrokeWidth = 1.5f,
            IsAntialias = true,
        })
        {
            canvas.DrawPath(holePath, holeStroke);
        }

        // Create slider piece image
        using var sliderBitmap = new SKBitmap(ImageWidth, ImageHeight);
        using var sliderCanvas = new SKCanvas(sliderBitmap);
        sliderCanvas.Clear(SKColors.Transparent);

        // Extract the original area from background (before hole was drawn)
        // Re-create background without hole for extraction
        using var bgClean = GenerateCleanBackground(rng, colors);
        using var clipPath = CreatePuzzlePiecePath(InitialPieceX, targetY);
        using (var clipPaint = new SKPaint
        {
            Style = SKPaintStyle.Fill,
            IsAntialias = true,
        })
        {
            sliderCanvas.Save();
            sliderCanvas.ClipPath(clipPath);
            sliderCanvas.DrawBitmap(bgClean, InitialPieceX - targetX, 0);
            sliderCanvas.Restore();
        }
        using (var strokePaint = new SKPaint
        {
            Color = SKColors.White,
            Style = SKPaintStyle.Stroke,
            StrokeWidth = 2,
            IsAntialias = true,
        })
        {
            sliderCanvas.DrawPath(clipPath, strokePaint);
        }

        var id = Guid.NewGuid().ToString("N");
        _entries[id] = new CaptchaEntry(targetX - InitialPieceX, DateTimeOffset.UtcNow.AddMinutes(5));

        var bgBase64 = BitmapToBase64(background);
        var sliderBase64 = BitmapToBase64(sliderBitmap);

        return new CaptchaChallenge(id, bgBase64, sliderBase64, targetY);
    }

    public string? Verify(string id, int userX)
    {
        if (!_entries.TryRemove(id, out var entry))
            return null;

        if (entry.ExpiresAtUtc < DateTimeOffset.UtcNow)
            return null;

        if (Math.Abs(userX - entry.TargetX) > _tolerance)
            return null;

        return IssueCaptchaToken();
    }

    public bool ValidateToken(string token)
    {
        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(_signingKey));
        var handler = new JwtSecurityTokenHandler();
        try
        {
            handler.ValidateToken(token, new TokenValidationParameters
            {
                ValidateIssuer = true,
                ValidIssuer = "https://gateway.local/",
                ValidateAudience = true,
                ValidAudiences = ["corterm-gateway", "cortex-terminal-gateway"],
                ValidateLifetime = true,
                ValidateIssuerSigningKey = true,
                IssuerSigningKey = key,
            }, out _);
            return true;
        }
        catch
        {
            return false;
        }
    }

    private string IssueCaptchaToken()
    {
        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(_signingKey));
        var credentials = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);
        var claims = new[]
        {
            new Claim("captcha", "verified"),
            new Claim(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString("N")),
        };
        var token = new JwtSecurityToken(
            issuer: "https://gateway.local/",
            audience: "corterm-gateway",
            claims: claims,
            expires: DateTime.UtcNow.AddMinutes(5),
            signingCredentials: credentials);
        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    private SKPath CreatePuzzlePiecePath(int cx, int cy)
    {
        var s = PieceSize / 2f;
        var tab = s * 0.3f;
        var path = new SKPath();

        // Top-left corner
        path.MoveTo(cx - s, cy - s);
        // Top edge with tab going up
        path.LineTo(cx - tab, cy - s);
        path.CubicTo(cx - tab, cy - s - tab, cx + tab, cy - s - tab, cx + tab, cy - s);
        path.LineTo(cx + s, cy - s);
        // Right edge with tab going right
        path.LineTo(cx + s, cy - tab);
        path.CubicTo(cx + s + tab, cy - tab, cx + s + tab, cy + tab, cx + s, cy + tab);
        path.LineTo(cx + s, cy + s);
        // Bottom edge
        path.LineTo(cx + tab, cy + s);
        path.CubicTo(cx + tab, cy + s + tab, cx - tab, cy + s + tab, cx - tab, cy + s);
        path.LineTo(cx - s, cy + s);
        // Left edge
        path.LineTo(cx - s, cy + tab);
        path.CubicTo(cx - s - tab, cy + tab, cx - s - tab, cy - tab, cx - s, cy - tab);
        path.Close();
        return path;
    }

    private SKBitmap GenerateCleanBackground(Random rng, SKColor[] colors)
    {
        var bitmap = new SKBitmap(ImageWidth, ImageHeight);
        using var canvas = new SKCanvas(bitmap);
        canvas.Clear(SKColors.White);

        for (var i = 0; i < colors.Length - 1; i++)
        {
            var y0 = i * ImageHeight / (colors.Length - 1);
            var y1 = (i + 1) * ImageHeight / (colors.Length - 1);
            using var shader = SKShader.CreateLinearGradient(new SKPoint(0, y0), new SKPoint(ImageWidth, y1),
                [colors[i], colors[i + 1]], SKShaderTileMode.Clamp);
            using var paint = new SKPaint { Shader = shader };
            canvas.DrawRect(0, y0, ImageWidth, y1 - y0 + 1, paint);
        }

        for (var i = 0; i < 15; i++)
        {
            using var paint = new SKPaint
            {
                Color = new SKColor((uint)rng.Next()),
                Style = SKPaintStyle.Fill,
                IsAntialias = true,
            };
            var shape = rng.Next(3);
            if (shape == 0)
            {
                canvas.DrawCircle(rng.Next(ImageWidth), rng.Next(ImageHeight), rng.Next(5, 20), paint);
            }
            else if (shape == 1)
            {
                canvas.DrawRect(rng.Next(ImageWidth), rng.Next(ImageHeight), rng.Next(10, 40), rng.Next(10, 40), paint);
            }
            else
            {
                using var path = new SKPath();
                path.MoveTo(rng.Next(ImageWidth), rng.Next(ImageHeight));
                path.LineTo(rng.Next(ImageWidth), rng.Next(ImageHeight));
                path.LineTo(rng.Next(ImageWidth), rng.Next(ImageHeight));
                path.Close();
                canvas.DrawPath(path, paint);
            }
        }

        return bitmap;
    }

    private static string BitmapToBase64(SKBitmap bitmap)
    {
        using var data = bitmap.Encode(SKEncodedImageFormat.Png, 90);
        return Convert.ToBase64String(data.ToArray());
    }

    private void Cleanup()
    {
        var now = DateTimeOffset.UtcNow;
        foreach (var kvp in _entries)
        {
            if (kvp.Value.ExpiresAtUtc < now)
                _entries.TryRemove(kvp.Key, out _);
        }
    }

    private sealed record CaptchaEntry(int TargetX, DateTimeOffset ExpiresAtUtc);
}

public sealed record CaptchaChallenge(string Id, string BackgroundImage, string SliderImage, int Y);
