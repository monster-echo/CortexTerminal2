using System.Net;
using System.Net.Sockets;
using CortexTerminal.Worker.P2P;
using FluentAssertions;
using Xunit;

namespace CortexTerminal.Worker.Tests.P2P;

public sealed class UdpPunchTests
{
    private static byte[] NewTxid() => System.Security.Cryptography.RandomNumberGenerator.GetBytes(12);

    private static UdpClient BindEphemeral(out int port)
    {
        var socket = new UdpClient();
        socket.Client.Bind(new IPEndPoint(IPAddress.Loopback, 0));
        port = ((IPEndPoint)socket.Client.LocalEndPoint!).Port;
        return socket;
    }

    [Fact]
    public void BuildProbe_PrefixesMarkerAndEchoesTxid()
    {
        var txid = NewTxid();
        var probe = UdpPunch.BuildProbe(txid);

        probe.Length.Should().Be(14);
        UdpPunch.IsProbe(probe, txid).Should().BeTrue();
        UdpPunch.IsProbe(probe, NewTxid()).Should().BeFalse();
        UdpPunch.IsProbe(new byte[] { 0x50, 0x54 }, txid).Should().BeFalse();
    }

    [Fact]
    public async Task PunchAsync_BothSidesOnLoopback_ConvergeOnEachOther()
    {
        var sideA = BindEphemeral(out var portA);
        var sideB = BindEphemeral(out var portB);
        var txid = NewTxid();

        var punchA = UdpPunch.PunchAsync(
            sideA, new IPEndPoint(IPAddress.Loopback, portB), txid,
            TimeSpan.FromSeconds(5), TimeSpan.FromMilliseconds(20), CancellationToken.None);
        var punchB = UdpPunch.PunchAsync(
            sideB, new IPEndPoint(IPAddress.Loopback, portA), txid,
            TimeSpan.FromSeconds(5), TimeSpan.FromMilliseconds(20), CancellationToken.None);

        var channelA = await punchA.WaitAsync(TimeSpan.FromSeconds(10));
        var channelB = await punchB.WaitAsync(TimeSpan.FromSeconds(10));

        channelA.Remote.Port.Should().Be(portB);
        channelB.Remote.Port.Should().Be(portA);
    }

    [Fact]
    public async Task PunchAsync_NoPeer_TimesOut()
    {
        var socket = BindEphemeral(out _);
        var txid = NewTxid();

        var act = async () => await UdpPunch.PunchAsync(
            socket, new IPEndPoint(IPAddress.Loopback, 1), txid,
            TimeSpan.FromMilliseconds(300), TimeSpan.FromMilliseconds(20), CancellationToken.None);

        await act.Should().ThrowAsync<TimeoutException>();
    }
}
