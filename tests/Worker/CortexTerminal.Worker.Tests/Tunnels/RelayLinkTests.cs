using System.Net;
using System.Net.Sockets;
using CortexTerminal.Worker.Tunnels;
using FluentAssertions;
using Microsoft.Extensions.Logging.Abstractions;

namespace CortexTerminal.Worker.Tests.Tunnels;

/// <summary>RelayLink 端口探活：隧道创建前的 localhost 可达性检查。</summary>
public sealed class RelayLinkTests
{
    private static RelayLink NewLink() => new("worker-test", NullLogger<RelayLink>.Instance);

    [Fact]
    public void ProbePort_ReturnsOpenFalseForInvalidPort()
    {
        var resp = NewLink().ProbePort(0, TimeSpan.FromMilliseconds(100));
        resp.Open.Should().BeFalse();
        resp.ErrorMessage.Should().Contain("invalid port");

        var negative = NewLink().ProbePort(-1, TimeSpan.FromMilliseconds(100));
        negative.Open.Should().BeFalse();
    }

    [Fact]
    public void ProbePort_ReturnsOpenFalseWhenNothingListening()
    {
        // Grab an ephemeral port no one is listening on, then release it before probing.
        using var tcp = new System.Net.Sockets.TcpListener(IPAddress.Loopback, 0);
        tcp.Start();
        var port = ((IPEndPoint)tcp.LocalEndpoint).Port;
        tcp.Stop();

        var resp = NewLink().ProbePort(port, TimeSpan.FromMilliseconds(500));
        resp.Open.Should().BeFalse();
    }

    [Fact]
    public void ProbePort_ReturnsOpenTrueForListeningPort()
    {
        using var tcp = new System.Net.Sockets.TcpListener(IPAddress.Loopback, 0);
        tcp.Start();
        try
        {
            var port = ((IPEndPoint)tcp.LocalEndpoint).Port;
            var resp = NewLink().ProbePort(port, TimeSpan.FromSeconds(2));
            resp.Open.Should().BeTrue();
        }
        finally
        {
            tcp.Stop();
        }
    }

    // Gateway 以 http(s) 形态下发 Relay 公网地址；WebSocket 连接必须映射成 ws(s)，
    // 否则数据面永远连不上（"Only Uris starting with 'ws://' or 'wss://' are supported"）。
    [Theory]
    [InlineData("http://localhost:8090", "ws", "localhost", 8090)]
    [InlineData("https://relay.example.com", "wss", "relay.example.com", 443)]
    [InlineData("ws://localhost:8090", "ws", "localhost", 8090)]
    [InlineData("wss://relay.example.com:9443/", "wss", "relay.example.com", 9443)]
    public void BuildRelayUri_MapsHttpSchemeToWebSocket(string relayUrl, string expectedScheme, string expectedHost, int expectedPort)
    {
        var uri = RelayLink.BuildRelayUri(relayUrl, "worker-1", "tok en");
        uri.Scheme.Should().Be(expectedScheme);
        uri.Host.Should().Be(expectedHost);
        uri.Port.Should().Be(expectedPort);
        uri.AbsolutePath.Should().Be("/worker");
        uri.Query.Should().Contain("workerId=worker-1");
        uri.Query.Should().Contain("token=tok%20en");
    }
}
