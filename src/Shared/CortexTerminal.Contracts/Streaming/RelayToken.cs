using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace CortexTerminal.Contracts.Streaming;

/// <summary>
/// Gateway 与 Relay 共享的短命 HMAC 令牌：base64url(payload JSON) + "." + base64url(HMAC-SHA256)。
/// Gateway 负责签发，Relay 只做无状态校验。Worker 不持有 secret：Gateway 通过可信 SignalR 通道
/// 把令牌原文发给 Worker，Worker 做常量时间比对即可。
/// </summary>
public static class RelayToken
{
    public const string AudienceTransfer = "transfer";
    public const string AudienceWorkerRelay = "worker-relay";

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
    };

    public sealed record TokenPayload(string Sub, string Aud, long Exp);

    public static string Mint(string sharedSecret, string aud, string subject, DateTimeOffset expiresAtUtc)
    {
        var payload = new TokenPayload(subject, aud, expiresAtUtc.ToUnixTimeSeconds());
        var payloadJson = JsonSerializer.Serialize(payload, JsonOptions);
        var payloadB64 = ToUrlSafeBase64(Encoding.UTF8.GetBytes(payloadJson));
        var signature = ComputeSignature(sharedSecret, payloadB64);
        return payloadB64 + "." + signature;
    }

    public static bool TryValidate(string sharedSecret, string token, string expectedAud, string expectedSubject, out TokenPayload payload)
    {
        payload = new TokenPayload("", "", 0);
        var separator = token.IndexOf('.');
        if (separator <= 0 || separator == token.Length - 1) return false;

        var payloadB64 = token[..separator];
        var signature = token[(separator + 1)..];
        if (!ConstantTimeEquals(ComputeSignature(sharedSecret, payloadB64), signature)) return false;

        string json;
        try
        {
            json = Encoding.UTF8.GetString(FromUrlSafeBase64(payloadB64));
        }
        catch (FormatException)
        {
            return false;
        }

        TokenPayload? parsed;
        try
        {
            parsed = JsonSerializer.Deserialize<TokenPayload>(json, JsonOptions);
        }
        catch (JsonException)
        {
            return false;
        }
        if (parsed is null) return false;

        if (parsed.Aud != expectedAud) return false;
        if (parsed.Sub != expectedSubject) return false;
        if (parsed.Exp <= DateTimeOffset.UtcNow.ToUnixTimeSeconds()) return false;

        payload = parsed;
        return true;
    }

    private static string ComputeSignature(string sharedSecret, string payloadB64)
    {
        var key = Encoding.UTF8.GetBytes(sharedSecret);
        var hash = HMACSHA256.HashData(key, Encoding.UTF8.GetBytes(payloadB64));
        return ToUrlSafeBase64(hash);
    }

    private static bool ConstantTimeEquals(string left, string right)
        => CryptographicOperations.FixedTimeEquals(Encoding.UTF8.GetBytes(left), Encoding.UTF8.GetBytes(right));

    private static string ToUrlSafeBase64(byte[] bytes)
        => Convert.ToBase64String(bytes).Replace('+', '-').Replace('/', '_').TrimEnd('=');

    private static byte[] FromUrlSafeBase64(string text)
    {
        var padded = text.Replace('-', '+').Replace('_', '/');
        return Convert.FromBase64String(padded.PadRight(padded.Length + ((4 - (padded.Length % 4)) % 4), '='));
    }
}
