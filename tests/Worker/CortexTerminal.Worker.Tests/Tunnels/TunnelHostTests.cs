using System.Net;
using System.Net.Sockets;
using System.Text;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Worker.Tunnels;
using FluentAssertions;
using Microsoft.Extensions.Logging.Abstractions;

namespace CortexTerminal.Worker.Tests.Tunnels;

public sealed class TunnelHostTests
{
    private static TunnelHost NewHost()
    {
        // Force IPv4 loopback regardless of how `localhost` resolves (macOS DNS prefers ::1,
        // which HttpListener bound to 127.0.0.1 doesn't answer). TunnelHost's URL is fixed to
        // "localhost", so pin the socket here instead of relying on OS resolution.
        var handler = new SocketsHttpHandler
        {
            ConnectCallback = async (ctx, ct) =>
            {
                var socket = new Socket(SocketType.Stream, ProtocolType.Tcp) { NoDelay = true };
                await socket.ConnectAsync(IPAddress.Loopback, ctx.DnsEndPoint.Port, ct);
                return new NetworkStream(socket, ownsSocket: true);
            }
        };
        return new TunnelHost(new HttpClient(handler), NullLogger<TunnelHost>.Instance);
    }

    [Fact]
    public void ProbePort_ReturnsOpenFalseForInvalidPort()
    {
        var resp = NewHost().ProbePort(0, TimeSpan.FromMilliseconds(100));
        resp.Open.Should().BeFalse();
        resp.ErrorMessage.Should().Contain("invalid port");

        var negative = NewHost().ProbePort(-1, TimeSpan.FromMilliseconds(100));
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

        var resp = NewHost().ProbePort(port, TimeSpan.FromMilliseconds(500));
        resp.Open.Should().BeFalse();
    }

    [Fact]
    public async Task HandleRequestAsync_ForwardsToLocalhostAndReturnsUpstreamBody()
    {
        using var server = new TcpListener(IPAddress.Loopback, 0);
        server.Start();
        var port = ((IPEndPoint)server.LocalEndpoint).Port;

        var serve = Task.Run(async () =>
        {
            using var client = await server.AcceptTcpClientAsync();
            using var stream = client.GetStream();
            await ReadRequestHeadAsync(stream, TimeSpan.FromSeconds(5));
            var body = Encoding.UTF8.GetBytes("HI");
            var head = Encoding.ASCII.GetBytes($"HTTP/1.1 200 OK\r\nContent-Length: {body.Length}\r\nConnection: close\r\n\r\n");
            await stream.WriteAsync(head);
            await stream.WriteAsync(body);
        });

        var host = NewHost();
        var req = new TunnelHttpRequest(
            "tunnel-1",
            port,
            "GET",
            "/",
            "",
            new Dictionary<string, string[]>(),
            Array.Empty<byte>());

        var resp = await host.HandleRequestAsync(req, TimeSpan.FromSeconds(5));

        await serve.WaitAsync(TimeSpan.FromSeconds(5));

        resp.StatusCode.Should().Be(200);
        Encoding.UTF8.GetString(resp.Body).Should().Be("HI");
        resp.ErrorMessage.Should().BeNull();
    }

    private static async Task ReadRequestHeadAsync(NetworkStream stream, TimeSpan timeout)
    {
        using var cts = new CancellationTokenSource(timeout);
        var buf = new byte[4096];
        var sb = new StringBuilder();
        while (!sb.ToString().Contains("\r\n\r\n"))
        {
            var n = await stream.ReadAsync(buf.AsMemory(), cts.Token);
            if (n == 0) break;
            sb.Append(Encoding.ASCII.GetString(buf, 0, n));
        }
    }
}
