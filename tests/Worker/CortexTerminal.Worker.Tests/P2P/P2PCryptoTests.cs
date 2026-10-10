using System.Security.Cryptography;
using CortexTerminal.Worker.P2P;
using FluentAssertions;
using Xunit;

namespace CortexTerminal.Worker.Tests.P2P;

public sealed class P2PCryptoTests
{
    [Fact]
    public void DeriveKey_IsDeterministicAndMatchesSpecInputs()
    {
        var a1 = P2PCrypto.DeriveKey("token-abc", "transfer-1");
        var a2 = P2PCrypto.DeriveKey("token-abc", "transfer-1");
        var b = P2PCrypto.DeriveKey("token-abc", "transfer-2");
        var c = P2PCrypto.DeriveKey("token-other", "transfer-1");

        a1.Length.Should().Be(32);
        a1.Should().Equal(a2);
        a1.Should().NotEqual(b);
        a1.Should().NotEqual(c);

        // 独立实现交叉验证：RFC 5869 Extract/Expand via HMAC
        var expected = HkdfSha256Reference(
            System.Text.Encoding.UTF8.GetBytes("token-abc"),
            System.Text.Encoding.UTF8.GetBytes("transfer-1"),
            "corterm-p2p-v1"u8.ToArray());
        a1.Should().Equal(expected);
    }

    private static byte[] HkdfSha256Reference(byte[] ikm, byte[] salt, byte[] info)
    {
        using var extract = new HMACSHA256(salt);
        var prk = extract.ComputeHash(ikm);
        using var expand = new HMACSHA256(prk);
        var t = Array.Empty<byte>();
        var okm = new List<byte>();
        var counter = 1;
        while (okm.Count < 32)
        {
            t = expand.ComputeHash([.. t, .. info, (byte)counter++]);
            okm.AddRange(t);
        }
        return [.. okm.Take(32)];
    }

    [Fact]
    public void EncryptDecrypt_RoundTrips()
    {
        var key = RandomNumberGenerator.GetBytes(32);
        var sender = new P2PCipher(key);
        var receiver = new P2PCipher(key);
        var plaintext = RandomNumberGenerator.GetBytes(1000);

        var datagram = sender.Encrypt(plaintext);

        datagram[0].Should().Be(P2PCrypto.DatagramVersion);
        var dst = new byte[plaintext.Length];
        receiver.TryDecrypt(datagram, dst, out var written).Should().BeTrue();
        written.Should().Be(plaintext.Length);
        dst.Should().Equal(plaintext);
    }

    [Fact]
    public void Datagram_HasVersionNonceAndGcmOverhead()
    {
        var key = RandomNumberGenerator.GetBytes(32);
        var cipher = new P2PCipher(key);
        var datagram = cipher.Encrypt(new byte[50]);
        datagram.Length.Should().Be(50 + P2PCrypto.DatagramOverheadBytes);
    }

    [Fact]
    public void TryDecrypt_TamperedTag_Fails()
    {
        var key = RandomNumberGenerator.GetBytes(32);
        var sender = new P2PCipher(key);
        var receiver = new P2PCipher(key);
        var datagram = sender.Encrypt(new byte[64]);
        datagram[^1] ^= 0xFF;

        receiver.TryDecrypt(datagram, new byte[64], out _).Should().BeFalse();
    }

    [Fact]
    public void TryDecrypt_WrongVersion_Fails()
    {
        var key = RandomNumberGenerator.GetBytes(32);
        var sender = new P2PCipher(key);
        var datagram = sender.Encrypt(new byte[16]);
        datagram[0] = 0x99;
        sender.Encrypt(new byte[16]); // keep sender counter moving, irrelevant
        var receiver = new P2PCipher(key);
        receiver.TryDecrypt(datagram, new byte[16], out _).Should().BeFalse();
    }

    [Fact]
    public void Nonce_IsUniquePerPacket()
    {
        var cipher = new P2PCipher(RandomNumberGenerator.GetBytes(32));
        var nonces = Enumerable.Range(0, 100)
            .Select(_ => cipher.Encrypt([1]))
            .Select(d => d[1..13].ToArray())
            .ToArray();
        nonces.Distinct().Should().HaveCount(100);
    }
}
