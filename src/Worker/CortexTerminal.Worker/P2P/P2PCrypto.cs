using System.Security.Cryptography;

namespace CortexTerminal.Worker.P2P;

/// <summary>
/// P2P 传输会话密钥与 UDP 包格式（规格 §3.1 / §3.2）。
/// key = HKDF-SHA256(ikm = RelayToken 原文 UTF-8, salt = transferId UTF-8, info = "corterm-p2p-v1", 32B)。
/// 数据报 = [1B version=0x01][12B nonce][ciphertext+16B GCM tag]；AAD 空。
/// nonce = 4B 随机前缀（每方向连接生成一次）+ 8B 大端计数器（每方向独立递增）。
/// </summary>
public static class P2PCrypto
{
    public const int KeySizeBytes = 32;
    public const int NonceSizeBytes = 12;
    public const int TagSizeBytes = 16;
    public const byte DatagramVersion = 0x01;
    public const int DatagramOverheadBytes = 1 + NonceSizeBytes + TagSizeBytes;
    public const int MaxDatagramSize = 1400;

    private static readonly byte[] HkdfInfo = "corterm-p2p-v1"u8.ToArray();

    public static byte[] DeriveKey(string relayToken, string transferId)
        => HKDF.DeriveKey(
            HashAlgorithmName.SHA256,
            System.Text.Encoding.UTF8.GetBytes(relayToken),
            KeySizeBytes,
            salt: System.Text.Encoding.UTF8.GetBytes(transferId),
            info: HkdfInfo);
}

/// <summary>
/// 单个加密会话的编解码：发送方向持有随机 nonce 前缀 + 递增计数器；
/// 接收方向直接使用包内携带的 nonce，无需对端计数器状态。
/// AesGcm 实例非线程安全，而 PunchStream 的 ACK/重传路径会并发进入，
/// 因此 Encrypt/TryDecrypt 内部串行化。
/// </summary>
public sealed class P2PCipher
{
    private readonly AesGcm _aes;
    private readonly object _gate = new();
    private readonly byte[] _noncePrefix = new byte[4];
    private ulong _counter;

    public P2PCipher(byte[] key)
    {
        if (key.Length != P2PCrypto.KeySizeBytes)
        {
            throw new ArgumentException($"key must be {P2PCrypto.KeySizeBytes} bytes", nameof(key));
        }
        _aes = new AesGcm(key, P2PCrypto.TagSizeBytes);
        RandomNumberGenerator.Fill(_noncePrefix);
    }

    /// <summary>版本字节 + nonce 之后的密文起始偏移（tag 附在尾部）。</summary>
    public const int CiphertextOffsetBytes = 1 + P2PCrypto.NonceSizeBytes;

    /// <summary>加密一帧明文，产出完整数据报（含版本字节与 nonce）。</summary>
    public byte[] Encrypt(ReadOnlySpan<byte> plaintext)
    {
        var datagram = new byte[CiphertextOffsetBytes + plaintext.Length + P2PCrypto.TagSizeBytes];
        datagram[0] = P2PCrypto.DatagramVersion;
        lock (_gate)
        {
            FillNextNonce(datagram.AsSpan(1, P2PCrypto.NonceSizeBytes));
            _aes.Encrypt(
                nonce: datagram.AsSpan(1, P2PCrypto.NonceSizeBytes),
                plaintext: plaintext,
                ciphertext: datagram.AsSpan(CiphertextOffsetBytes, plaintext.Length),
                tag: datagram.AsSpan(^P2PCrypto.TagSizeBytes..),
                associatedData: ReadOnlySpan<byte>.Empty);
        }
        return datagram;
    }

    /// <summary>
    /// 解密一个数据报。tag 校验不过或版本不符返回 false（规格：静默丢弃）。
    /// </summary>
    public bool TryDecrypt(ReadOnlySpan<byte> datagram, Span<byte> plaintextDestination, out int written)
    {
        written = 0;
        if (datagram.Length < P2PCrypto.DatagramOverheadBytes || datagram[0] != P2PCrypto.DatagramVersion)
        {
            return false;
        }
        var plaintextLength = datagram.Length - P2PCrypto.DatagramOverheadBytes;
        if (plaintextDestination.Length < plaintextLength)
        {
            throw new ArgumentException("plaintext destination too small", nameof(plaintextDestination));
        }
        try
        {
            lock (_gate)
            {
                _aes.Decrypt(
                    nonce: datagram.Slice(1, P2PCrypto.NonceSizeBytes),
                    ciphertext: datagram.Slice(CiphertextOffsetBytes, plaintextLength),
                    tag: datagram[^P2PCrypto.TagSizeBytes..],
                    plaintext: plaintextDestination[..plaintextLength],
                    associatedData: ReadOnlySpan<byte>.Empty);
            }
        }
        catch (AuthenticationTagMismatchException)
        {
            return false;
        }
        written = plaintextLength;
        return true;
    }

    private void FillNextNonce(Span<byte> nonce)
    {
        _noncePrefix.CopyTo(nonce);
        var counter = _counter++;
        System.Buffers.Binary.BinaryPrimitives.WriteUInt64BigEndian(nonce[4..], counter);
    }
}
