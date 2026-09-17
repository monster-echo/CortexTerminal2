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
}
