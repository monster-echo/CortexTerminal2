using System.Net;
using System.Net.Sockets;
using System.Text;
using CortexTerminal.AgentRunner.Sinks;
using FluentAssertions;

namespace CortexTerminal.AgentRunner.Tests.Sinks;

/// <summary>
/// HttpSink returns the upstream response body so HookForwarder can write it to stdout for
/// Claude Code's UserPromptSubmit hook. These tests boot a real loopback TCP HTTP responder —
/// the same "no mocking" style as CortermMcpServerTests — so we exercise HttpClient's full
/// request/response path rather than a stub handler. The static HttpClient is fine here: every
/// test binds a unique ephemeral port.
/// </summary>
public sealed class HttpSinkTests
{
    [Fact]
    public async Task ForwardAsync_ReturnsResponseBody()
    {
        var body = "hook-additional-context";
        using var server = await LoopbackHttp.StartAsync(HttpStatusCode.OK, body);
        var sink = new HttpSink(server.Url);

        var result = await sink.ForwardAsync("{\"event_type\":\"Stop\"}", CancellationToken.None);

        result.Should().Be(body);
    }

    [Fact]
    public async Task ForwardAsync_AcceptedStatusCode_ReturnsResponseBody()
    {
        // AgentEventEndpoint returns 202 for events the adapter did not turn into a frame; that
        // is a success on this transport and the body must still flow back to stdout.
        var body = "{\"hookSpecificOutput\":{}}";
        using var server = await LoopbackHttp.StartAsync(HttpStatusCode.Accepted, body);
        var sink = new HttpSink(server.Url);

        var result = await sink.ForwardAsync("{\"event_type\":\"PreToolUse\"}", CancellationToken.None);

        result.Should().Be(body);
    }

    [Fact]
    public async Task ForwardAsync_NonSuccessStatusCode_ThrowsHttpRequestException()
    {
        using var server = await LoopbackHttp.StartAsync(HttpStatusCode.InternalServerError, "boom");
        var sink = new HttpSink(server.Url);

        var act = async () => await sink.ForwardAsync("{\"event_type\":\"Stop\"}", CancellationToken.None);

        await act.Should().ThrowAsync<HttpRequestException>();
    }

    [Fact]
    public async Task Constructor_EmptyHookUrl_Throws()
    {
        var act = () => new HttpSink(string.Empty);
        act.Should().Throw<ArgumentException>();
    }

    /// <summary>
    /// Minimal one-request-per-connection HTTP/1.1 responder bound to an ephemeral loopback port.
    /// Reads the full request (headers + Content-Length body), then writes a fixed status + body.
    /// </summary>
    private sealed class LoopbackHttp : IDisposable
    {
        public string Url { get; }
        private readonly TcpListener _listener;
        private readonly HttpStatusCode _status;
        private readonly string _body;
        private readonly CancellationTokenSource _cts = new();

        private LoopbackHttp(string url, TcpListener listener, HttpStatusCode status, string body)
        {
            Url = url;
            _listener = listener;
            _status = status;
            _body = body;
            _ = Task.Run(AcceptLoopAsync);
        }

        public static async Task<LoopbackHttp> StartAsync(HttpStatusCode status, string body)
        {
            var listener = new TcpListener(IPAddress.Loopback, 0);
            listener.Start();
            var port = ((IPEndPoint)listener.LocalEndpoint).Port;
            return new LoopbackHttp($"http://127.0.0.1:{port}/", listener, status, body);
        }

        private async Task AcceptLoopAsync()
        {
            while (!_cts.IsCancellationRequested)
            {
                TcpClient client;
                try
                {
                    client = await _listener.AcceptTcpClientAsync(_cts.Token);
                }
                catch (OperationCanceledException) { return; }
                catch (SocketException) { return; }

                _ = HandleAsync(client, _cts.Token);
            }
        }

        private async Task HandleAsync(TcpClient client, CancellationToken ct)
        {
            try
            {
                using (client)
                {
                    var stream = client.GetStream();
                    var buf = new byte[8192];
                    using var acc = new MemoryStream();
                    var headerEnd = -1;
                    var contentLength = 0;

                    // Accumulate raw bytes until we have the full header block, then parse
                    // Content-Length and keep reading until the body is fully received.
                    while (true)
                    {
                        var read = await stream.ReadAsync(buf, ct);
                        if (read == 0) return;
                        acc.Write(buf, 0, read);

                        var data = acc.GetBuffer();
                        var len = (int)acc.Length;
                        if (headerEnd < 0)
                        {
                            for (var i = 0; i + 3 < len; i++)
                            {
                                if (data[i] == 13 && data[i + 1] == 10 && data[i + 2] == 13 && data[i + 3] == 10)
                                {
                                    headerEnd = i + 4;
                                    break;
                                }
                            }
                        }
                        if (headerEnd >= 0)
                        {
                            if (contentLength == 0)
                            {
                                var headerText = Encoding.ASCII.GetString(data, 0, headerEnd);
                                foreach (var line in headerText.Split("\r\n", StringSplitOptions.RemoveEmptyEntries))
                                {
                                    if (line.StartsWith("Content-Length:", StringComparison.OrdinalIgnoreCase))
                                    {
                                        contentLength = int.Parse(line.AsSpan(15).Trim());
                                    }
                                }
                            }
                            if (len >= headerEnd + contentLength) break;
                        }
                    }

                    var bodyBytes = Encoding.UTF8.GetBytes(_body);
                    var resp = $"HTTP/1.1 {(int)_status} {_status}\r\nContent-Length: {bodyBytes.Length}\r\n\r\n";
                    var respBytes = Encoding.ASCII.GetBytes(resp);
                    await stream.WriteAsync(respBytes, ct);
                    await stream.WriteAsync(bodyBytes, ct);
                }
            }
            catch
            {
                // Best-effort responder for a unit test; client failures surface as test assertions.
            }
        }

        public void Dispose()
        {
            _cts.Cancel();
            _listener.Stop();
            _cts.Dispose();
        }
    }
}
