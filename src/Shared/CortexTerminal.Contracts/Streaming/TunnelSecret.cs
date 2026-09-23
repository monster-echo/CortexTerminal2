using System.Security.Cryptography;
using System.Text;

namespace CortexTerminal.Contracts.Streaming;

/// <summary>
/// 生成 secret(访客访问凭据)与 tunnel key(路径标识),以及对 secret 做 SHA-256 哈希存储。
/// Gateway 与 Relay 共享：Gateway 生成并存哈希，Relay 用哈希校验访客 secret。
/// </summary>
public static class TunnelSecret
{
    private const int SecretByteLength = 32;
    private const int KeyByteLength = 5;

    /// <summary>32 字节随机数,编码为 URL-safe base64(无 padding)。用于 ?k= 访问凭据。</summary>
    public static string GenerateSecret()
        => ToUrlSafeBase64(RandomNumberGenerator.GetBytes(SecretByteLength));

    private const string Base36Alphabet = "0123456789abcdefghijklmnopqrstuvwxyz";

    /// <summary>5 字节随机数(40 bit 熵)编码为 8 位 base36 小写(0-9a-z),满足 DNS 子域名规范。用于 t-&lt;key&gt;.&lt;RootDomain&gt; 子域名标识。访问凭据由 secret 承担,key 熵要求较低。</summary>
    public static string GenerateTunnelKey()
    {
        var bytes = RandomNumberGenerator.GetBytes(KeyByteLength);
        // 大端序整数 -> base36。
        var buf = new char[8];
        ulong n = 0;
        for (var i = 0; i < bytes.Length; i++)
        {
            n = (n << 8) | bytes[i];
        }
        for (var i = buf.Length - 1; i >= 0; i--)
        {
            buf[i] = Base36Alphabet[(int)(n % 36)];
            n /= 36;
        }
        return new string(buf);
    }

    /// <summary>SHA-256(secret) 的小写十六进制。明文 secret 永不入库。</summary>
    public static string Hash(string secret)
    {
        var bytes = Encoding.UTF8.GetBytes(secret);
        var hash = SHA256.HashData(bytes);
        return Convert.ToHexString(hash).ToLowerInvariant();
    }

    public static bool Verify(string secret, string hash)
        => !string.IsNullOrEmpty(secret) && Hash(secret) == hash;

    private static string ToUrlSafeBase64(byte[] bytes)
        => Convert.ToBase64String(bytes).Replace('+', '-').Replace('/', '_').TrimEnd('=');
}
