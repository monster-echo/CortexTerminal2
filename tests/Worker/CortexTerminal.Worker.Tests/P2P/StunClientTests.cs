using System.Net;
using CortexTerminal.Worker.P2P;
using FluentAssertions;
using Xunit;

namespace CortexTerminal.Worker.Tests.P2P;

public sealed class StunClientTests
{
    private static byte[] NewTxid() => System.Security.Cryptography.RandomNumberGenerator.GetBytes(12);

    [Fact]
    public void BuildBindingRequest_ProducesWellFormed20Bytes()
    {
        var txid = NewTxid();
        var request = StunClient.BuildBindingRequest(txid);

        request.Length.Should().Be(20);
        request[0].Should().Be(0x00);
        request[1].Should().Be(0x01); // Binding Request
        request[2].Should().Be(0x00);
        request[3].Should().Be(0x00); // no attributes
        // magic cookie big-endian
        request[4..8].Should().Equal([0x21, 0x12, 0xA4, 0x42]);
        request[8..20].Should().Equal(txid);
    }

    [Fact]
    public void BuildBindingRequest_RejectsWrongTxidLength()
    {
        var act = () => StunClient.BuildBindingRequest(new byte[8]);
        act.Should().Throw<ArgumentException>();
    }

    /// <summary>按 RFC 5389 规则构造一个 XOR-MAPPED-ADDRESS 响应（IPv4）。</summary>
    private static byte[] BuildXorMappedResponse(byte[] txid, IPAddress address, ushort port)
    {
        var magic = new byte[] { 0x21, 0x12, 0xA4, 0x42 };
        var addr = address.GetAddressBytes();
        var xport = (ushort)(port ^ (StunClient.MagicCookie >> 16));
        var xaddr = new byte[4];
        for (var i = 0; i < 4; i++)
        {
            xaddr[i] = (byte)(addr[i] ^ magic[i]);
        }

        var response = new byte[20 + 12];
        response[0] = 0x01;
        response[1] = 0x01; // Binding Success
        response[2] = 0x00;
        response[3] = 0x0C; // attribute total length 12
        magic.CopyTo(response, 4);
        txid.CopyTo(response, 8);

        // attribute: type 0x0020, length 8, family 0x01, xport, xaddr
        var attrStart = 20;
        response[attrStart] = 0x00;
        response[attrStart + 1] = 0x20;
        response[attrStart + 2] = 0x00;
        response[attrStart + 3] = 0x08;
        response[attrStart + 4] = 0x00;
        response[attrStart + 5] = 0x01;
        response[attrStart + 6] = (byte)(xport >> 8);
        response[attrStart + 7] = (byte)(xport & 0xFF);
        xaddr.CopyTo(response, attrStart + 8);
        return response;
    }

    [Fact]
    public void TryParseXorMappedAddress_DecodesSyntheticResponse()
    {
        var txid = NewTxid();
        var response = BuildXorMappedResponse(txid, IPAddress.Parse("203.0.113.7"), 54321);

        var ok = StunClient.TryParseXorMappedAddress(response, txid, out var mapped);

        ok.Should().BeTrue();
        mapped.Address.Should().Be(IPAddress.Parse("203.0.113.7"));
        mapped.Port.Should().Be(54321);
    }

    [Fact]
    public void TryParseXorMappedAddress_WrongTxid_Fails()
    {
        var txid = NewTxid();
        var other = NewTxid();
        var response = BuildXorMappedResponse(txid, IPAddress.Parse("203.0.113.7"), 54321);

        StunClient.TryParseXorMappedAddress(response, other, out _).Should().BeFalse();
    }

    [Fact]
    public void TryParseXorMappedAddress_GarbageInput_Fails()
    {
        var txid = NewTxid();
        StunClient.TryParseXorMappedAddress(new byte[] { 1, 2, 3 }, txid, out _).Should().BeFalse();
        StunClient.TryParseXorMappedAddress(Array.Empty<byte>(), txid, out _).Should().BeFalse();
    }
}
