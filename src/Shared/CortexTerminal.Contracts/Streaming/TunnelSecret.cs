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

    /// <summary>5 字节随机数编码为 10 位小写 hex(40 bit 熵),仅含 0-9a-f,满足 DNS 子域名规范。用于 &lt;key&gt;.tunnel.&lt;RootDomain&gt;/ 子域名标识。</summary>
    public static string GenerateTunnelKey()
        => Convert.ToHexString(RandomNumberGenerator.GetBytes(KeyByteLength)).ToLowerInvariant();

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
