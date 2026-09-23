using System.Collections.Concurrent;
using System.Net;
using System.Net.Http.Headers;
using System.Net.WebSockets;
using System.Text;
using System.Threading.Channels;
using CortexTerminal.Contracts.Streaming;
using Microsoft.Extensions.Logging;

namespace CortexTerminal.Worker.Tunnels;

/// <summary>
/// Worker ⇄ Relay 持久数据面连接（隧道转发）。持 Gateway 签发的 worker relay 令牌连入
/// Relay 的 /worker WS；访客请求经 treq 控制帧到达，本端用共享 HttpClient 流式反代到
/// localhost:&lt;port&gt;，响应头/体/终态分别经 tres / 二进制帧 / tend 回传。无整包缓冲。
/// </summary>
public sealed class RelayLink(string workerId, ILogger<RelayLink> logger, TimeSpan? waitPortTimeout = null) : IAsyncDisposable
{
    /// <summary>访客请求到达时端口未监听的最长等待时间；超时后按 unreachable 返回。</summary>
    private readonly TimeSpan _waitPortTimeout = waitPortTimeout ?? TimeSpan.FromSeconds(15);

    private readonly SemaphoreSlim _stateLock = new(1, 1);
    private ClientWebSocket? _socket;
    private CancellationTokenSource? _lifetime;
    private string? _token;
    private string _relayUrl = string.Empty;

    private readonly ConcurrentDictionary<string, InflightTunnelRequest> _inflight = new(StringComparer.Ordinal);
    private readonly Channel<OutgoingFrame> _outgoing = Channel.CreateBounded<OutgoingFrame>(
        new BoundedChannelOptions(1024) { SingleReader = true, SingleWriter = false });

    /// <summary>是否已连入 Relay（隧道数据面可用）。</summary>
    public bool IsConnected => _socket is { State: WebSocketState.Open };

    public ValueTask DisposeAsync()
    {
        _lifetime?.Cancel();
        _lifetime?.Dispose();
        return ValueTask.CompletedTask;
    }

    private readonly record struct OutgoingFrame(byte[] Bytes, WebSocketMessageType Type);

    /// <summary>更新 Relay 地址与令牌（Gateway 注册时经 IssueRelayToken RPC 推送）。</summary>
    public void Configure(string relayUrl, string token)
    {
        _relayUrl = relayUrl;
        _token = token;
    }

    /// <summary>TCP 端口探活：建隧道前的可达性检查（localhost:&lt;port&gt;）。</summary>
    public ProbePortResponse ProbePort(int port, TimeSpan timeout)
    {
        if (port <= 0 || port > 65535)
        {
            return new ProbePortResponse(false, $"invalid port {port}");
        }
        try
        {
            using var tcp = new System.Net.Sockets.TcpClient();
            var ar = tcp.BeginConnect(IPAddress.Loopback, port, null, null);
            if (!ar.AsyncWaitHandle.WaitOne(timeout))
            {
                return new ProbePortResponse(false, $"connect to localhost:{port} timed out");
            }
            tcp.EndConnect(ar);
            return new ProbePortResponse(true, null);
        }
        catch (Exception ex)
        {
            logger.LogDebug(ex, "probe localhost:{Port} failed", port);
            return new ProbePortResponse(false, ex.Message);
        }
    }

    /// <summary>保持连入 Relay：断线重连（间隔 5s）。令牌未就绪/未配置时静默等待下一次配置。</summary>
    public Task RunAsync(CancellationToken cancellationToken) => Task.Run(() => LoopAsync(cancellationToken), cancellationToken);

    private async Task LoopAsync(CancellationToken cancellationToken)
    {
        _lifetime = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        while (!cancellationToken.IsCancellationRequested)
        {
            string? token;
            string relayUrl;
            await _stateLock.WaitAsync(cancellationToken);
            try
            {
                token = _token;
                relayUrl = _relayUrl;
            }
            finally
            {
                _stateLock.Release();
            }

            if (string.IsNullOrEmpty(token) || string.IsNullOrEmpty(relayUrl))
            {
                await Task.Delay(TimeSpan.FromSeconds(5), cancellationToken);
                continue;
            }

            try
            {
                using var socket = new ClientWebSocket();
                socket.Options.KeepAliveInterval = TimeSpan.FromSeconds(30);
                var uri = BuildRelayUri(relayUrl, workerId, token);
                await socket.ConnectAsync(uri, cancellationToken);
                _socket = socket;
                logger.LogInformation("Relay link connected for worker {WorkerId}.", workerId);
                await RunConnectionAsync(socket, cancellationToken);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                logger.LogWarning(ex, "Relay link lost for worker {WorkerId}, retrying in 5s.", workerId);
            }
            _socket = null;
            try
            {
                await Task.Delay(TimeSpan.FromSeconds(5), cancellationToken);
            }
            catch (OperationCanceledException)
            {
                return;
            }
        }
    }

    /// <summary>
    /// Relay 公网地址在 Gateway 侧以 http(s) 形态配置（同一地址也用于拼传输端点 URL），
    /// 但 WebSocket 连接只接受 ws(s)。映射收敛在 RelayUri，避免各调用点重写一遍。
    /// </summary>
    internal static Uri BuildRelayUri(string relayUrl, string workerId, string token)
        => RelayUri.BuildWebSocketUri(
            relayUrl,
            "worker",
            new KeyValuePair<string, string>("workerId", workerId),
            new KeyValuePair<string, string>("token", token));

    private async Task RunConnectionAsync(WebSocket socket, CancellationToken ct)
    {
        var sendTask = SendLoopAsync(socket, ct);
        try
        {
            var buffer = new byte[RelayProtocol.DataChunkSize];
            while (socket.State == WebSocketState.Open && !ct.IsCancellationRequested)
            {
                var frame = await ReceiveMessageAsync(socket, buffer, ct);
                if (frame is null)
                {
                    break;
                }
                if (frame.Value.MessageType == WebSocketMessageType.Text)
                {
                    HandleControlFrame(frame.Value.Data);
                }
                else
                {
                    HandleDataFrame(frame.Value.Data);
                }
            }
        }
        finally
        {
            _outgoing.Writer.TryComplete();
            foreach (var request in _inflight.Values)
            {
                request.RequestBodyWriter.TryComplete();
            }
            try
            {
                await sendTask;
            }
            catch (OperationCanceledException) { }
            catch (WebSocketException) { }
            catch (IOException) { }
        }
    }

    private async Task SendLoopAsync(WebSocket socket, CancellationToken ct)
    {
        var reader = _outgoing.Reader;
        while (await reader.WaitToReadAsync(ct))
        {
            while (reader.TryRead(out var frame))
            {
                await socket.SendAsync(frame.Bytes, frame.Type, endOfMessage: true, ct);
            }
        }
    }

    private void HandleControlFrame(byte[] utf8Json)
    {
        string? type;
        try
        {
            using var doc = System.Text.Json.JsonDocument.Parse(utf8Json);
            type = doc.RootElement.TryGetProperty("type", out var t) ? t.GetString() : null;
        }
        catch (System.Text.Json.JsonException)
        {
            return;
        }

        if (type == RelayProtocol.TunnelRequestType)
        {
            var request = TryDeserialize<TunnelRequestFrame>(utf8Json);
            if (request is not null)
            {
                _ = ExecuteTunnelRequestAsync(request);
            }
        }
        else if (type == RelayProtocol.TunnelRequestBodyEndType)
        {
            var end = TryDeserialize<TunnelRequestBodyEndFrame>(utf8Json);
            if (end is not null && _inflight.TryGetValue(end.Id, out var request))
            {
                request.RequestBodyWriter.TryComplete();
            }
        }
    }

    private void HandleDataFrame(byte[] data)
    {
        // [0x02][4B idLen 大端][id][payload]
        if (data.Length < 1 + RelayProtocol.RequestIdLengthBytes || data[0] != RelayProtocol.DataFrameMarker)
        {
            return;
        }
        var idLen = (data[1] << 24) | (data[2] << 16) | (data[3] << 8) | data[4];
        var payloadStart = 1 + RelayProtocol.RequestIdLengthBytes + idLen;
        if (payloadStart > data.Length) return;

        var id = Encoding.UTF8.GetString(data, 1 + RelayProtocol.RequestIdLengthBytes, idLen);
        if (!_inflight.TryGetValue(id, out var request)) return;

        var payload = payloadStart == data.Length ? Array.Empty<byte>() : data[payloadStart..];
        request.RequestBodyWriter.TryWrite(payload);
    }

    /// <summary>轮询等待 localhost:&lt;port&gt; 出现监听（间隔 500ms,最长 _waitPortTimeout）。</summary>
    private async Task<bool> WaitPortOpenAsync(int port, CancellationToken ct)
    {
        var deadline = DateTime.UtcNow + _waitPortTimeout;
        while (true)
        {
            try
            {
                using var tcp = new System.Net.Sockets.TcpClient();
                var ar = tcp.BeginConnect(IPAddress.Loopback, port, null, null);
                if (ar.AsyncWaitHandle.WaitOne(TimeSpan.FromMilliseconds(500)) && tcp.Connected)
                {
                    tcp.EndConnect(ar);
                    return true;
                }
            }
            catch
            {
                // 尚未监听，继续等待。
            }

            if (DateTime.UtcNow >= deadline)
            {
                return false;
            }
            try
            {
                await Task.Delay(TimeSpan.FromMilliseconds(500), ct);
            }
            catch (OperationCanceledException)
            {
                return false;
            }
        }
    }

    /// <summary>反代一次访客请求到 localhost:&lt;port&gt;：请求体经管道流式供给，响应分帧回流。</summary>
    private async Task ExecuteTunnelRequestAsync(TunnelRequestFrame request)
    {
        var inflight = new InflightTunnelRequest();
        _inflight[request.Id] = inflight;
        try
        {
            // 端口未监听时先等它就绪（服务重启/延迟启动场景），超时按 unreachable 返回。
            if (!await WaitPortOpenAsync(request.Port, inflight.Lifetime.Token))
            {
                var timeoutEnd = System.Text.Json.JsonSerializer.SerializeToUtf8Bytes(
                    new TunnelEndFrame { Id = request.Id, Error = $"localhost:{request.Port} not listening after waiting {_waitPortTimeout.TotalSeconds:0}s" },
                    RelayJson.Default);
                _outgoing.Writer.TryWrite(new OutgoingFrame(timeoutEnd, WebSocketMessageType.Text));
                return;
            }

            using var upstream = new HttpRequestMessage(new HttpMethod(request.Method), BuildUrl(request));
            foreach (var (name, values) in request.Headers)
            {
                if (name.StartsWith("Host", StringComparison.OrdinalIgnoreCase)) continue;
                if (name.StartsWith("Content-", StringComparison.OrdinalIgnoreCase)) continue;
                foreach (var value in values)
                {
                    upstream.Headers.TryAddWithoutValidation(name, value);
                }
            }

            var bodyStream = new ChannelStream(inflight.RequestBodyReader);
            if (HasBody(request.Method))
            {
                upstream.Content = new StreamContent(bodyStream);
                var contentType = GetHeader(request.Headers, "Content-Type");
                if (contentType is not null)
                {
                    upstream.Content.Headers.ContentType = new MediaTypeHeaderValue(contentType);
                }
            }

            using var response = await Forwarder.SendAsync(upstream, HttpCompletionOption.ResponseHeadersRead, inflight.Lifetime.Token);

            var head = new TunnelResponseHeadFrame
            {
                Id = request.Id,
                Status = (int)response.StatusCode,
                Headers = CollectHeaders(response),
            };
            _outgoing.Writer.TryWrite(new OutgoingFrame(
                System.Text.Json.JsonSerializer.SerializeToUtf8Bytes(head, RelayJson.Default), WebSocketMessageType.Text));

            var buffer = new byte[RelayProtocol.DataChunkSize];
            await using (var stream = await response.Content.ReadAsStreamAsync(inflight.Lifetime.Token))
            {
                int read;
                while ((read = await stream.ReadAsync(buffer, inflight.Lifetime.Token)) > 0)
                {
                    _outgoing.Writer.TryWrite(new OutgoingFrame(EncodeDataFrame(request.Id, buffer.AsSpan(0, read)), WebSocketMessageType.Binary));
                }
            }

            _outgoing.Writer.TryWrite(new OutgoingFrame(
                System.Text.Json.JsonSerializer.SerializeToUtf8Bytes(
                    new TunnelEndFrame { Id = request.Id }, RelayJson.Default), WebSocketMessageType.Text));
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Tunnel forward to localhost:{Port}{Path} failed.", request.Port, request.Path);
            var end = System.Text.Json.JsonSerializer.SerializeToUtf8Bytes(
                new TunnelEndFrame { Id = request.Id, Error = $"localhost:{request.Port} unreachable: {ex.Message}" },
                RelayJson.Default);
            _outgoing.Writer.TryWrite(new OutgoingFrame(end, WebSocketMessageType.Text));
        }
        finally
        {
            _inflight.TryRemove(request.Id, out _);
            inflight.Dispose();
        }
    }

    private static readonly HttpClient Forwarder = CreateForwarder();

    private static HttpClient CreateForwarder()
    {
        // 反代目标是 localhost:port，绝不能走系统代理（代理无法访问用户回环地址）。
        var handler = new SocketsHttpHandler { UseProxy = false, AllowAutoRedirect = false };
        return new HttpClient(handler) { Timeout = Timeout.InfiniteTimeSpan };
    }

    private static bool HasBody(string method)
        => method is not ("GET" or "HEAD" or "DELETE" or "CONNECT" or "TRACE");

    private static string? GetHeader(Dictionary<string, string[]> headers, string name)
        => headers.TryGetValue(name, out var values) && values.Length > 0 ? values[0] : null;

    private static Dictionary<string, string[]> CollectHeaders(HttpResponseMessage response)
    {
        var result = new Dictionary<string, string[]>();
        foreach (var (name, values) in response.Headers)
        {
            if (RelayLink.IsHopByHop(name)) continue;
            result[name] = values.ToArray();
        }
        foreach (var (name, values) in response.Content.Headers)
        {
            if (RelayLink.IsHopByHop(name)) continue;
            result[name] = values.ToArray();
        }
        return result;
    }

    private static bool IsHopByHop(string name)
        => name.Equals("Connection", StringComparison.OrdinalIgnoreCase)
           || name.Equals("Keep-Alive", StringComparison.OrdinalIgnoreCase)
           || name.Equals("Transfer-Encoding", StringComparison.OrdinalIgnoreCase)
           || name.Equals("Upgrade", StringComparison.OrdinalIgnoreCase)
           || name.Equals("Proxy-Authenticate", StringComparison.OrdinalIgnoreCase)
           || name.Equals("Proxy-Authorization", StringComparison.OrdinalIgnoreCase)
           || name.Equals("TE", StringComparison.OrdinalIgnoreCase)
           || name.Equals("Trailer", StringComparison.OrdinalIgnoreCase);

    internal static string BuildUrl(TunnelRequestFrame request)
    {
        var path = string.IsNullOrEmpty(request.Path) ? "/" : request.Path;
        return $"http://localhost:{request.Port}{path}{request.Query}";
    }

    internal static byte[] EncodeDataFrame(string requestId, ReadOnlySpan<byte> payload)
    {
        var idBytes = Encoding.UTF8.GetBytes(requestId);
        var frame = new byte[1 + RelayProtocol.RequestIdLengthBytes + idBytes.Length + payload.Length];
        frame[0] = RelayProtocol.DataFrameMarker;
        frame[1] = (byte)(idBytes.Length >> 24);
        frame[2] = (byte)(idBytes.Length >> 16);
        frame[3] = (byte)(idBytes.Length >> 8);
        frame[4] = (byte)idBytes.Length;
        idBytes.CopyTo(frame.AsSpan(5));
        payload.CopyTo(frame.AsSpan(5 + idBytes.Length));
        return frame;
    }

    private static async Task<RelayFrame?> ReceiveMessageAsync(WebSocket socket, byte[] buffer, CancellationToken ct)
    {
        var offset = 0;
        while (true)
        {
            if (offset == buffer.Length)
            {
                var grown = new byte[buffer.Length * 2];
                Array.Copy(buffer, grown, buffer.Length);
                buffer = grown;
            }
            var result = await socket.ReceiveAsync(buffer.AsMemory(offset), ct);
            if (result.MessageType == WebSocketMessageType.Close)
            {
                return null;
            }
            offset += result.Count;
            if (result.EndOfMessage)
            {
                var data = new byte[offset];
                Array.Copy(buffer, data, offset);
                return new RelayFrame(result.MessageType, data, EndOfMessage: true);
            }
        }
    }

    private static T? TryDeserialize<T>(byte[] utf8Json) where T : class
    {
        try
        {
            return System.Text.Json.JsonSerializer.Deserialize<T>(utf8Json, RelayJson.Default);
        }
        catch (System.Text.Json.JsonException)
        {
            return null;
        }
    }

    /// <summary>一次进行中的隧道请求：访客请求体的管道 + 独立生命周期。</summary>
    private sealed class InflightTunnelRequest : IDisposable
    {
        public System.Threading.Channels.ChannelWriter<byte[]> RequestBodyWriter { get; }
        public System.Threading.Channels.ChannelReader<byte[]> RequestBodyReader { get; }
        public CancellationTokenSource Lifetime { get; } = new(TimeSpan.FromMinutes(10));

        public InflightTunnelRequest()
        {
            var channel = System.Threading.Channels.Channel.CreateBounded<byte[]>(
                new System.Threading.Channels.BoundedChannelOptions(64) { SingleReader = true, SingleWriter = true });
            RequestBodyWriter = channel.Writer;
            RequestBodyReader = channel.Reader;
        }

        public void Dispose() => Lifetime.Dispose();
    }

    /// <summary>把 ChannelReader 包装成 Stream，供 StreamContent 流式读取请求体。</summary>
    private sealed class ChannelStream(System.Threading.Channels.ChannelReader<byte[]> reader) : Stream
    {
        private byte[]? _current;
        private int _offset;

        public override bool CanRead => true;
        public override bool CanSeek => false;
        public override bool CanWrite => false;
        public override long Length => throw new NotSupportedException();
        public override long Position { get => throw new NotSupportedException(); set => throw new NotSupportedException(); }

        public override async ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken cancellationToken)
        {
            if (_current is null || _offset >= _current.Length)
            {
                if (!await reader.WaitToReadAsync(cancellationToken))
                {
                    return 0;
                }
                if (!reader.TryRead(out _current!))
                {
                    return 0;
                }
                _offset = 0;
            }

            var count = Math.Min(buffer.Length, _current.Length - _offset);
            _current.AsMemory(_offset, count).CopyTo(buffer);
            _offset += count;
            return count;
        }

        public override void Flush() { }
        public override int Read(byte[] buffer, int offset, int count)
            => ReadAsync(buffer.AsMemory(offset, count), CancellationToken.None).AsTask().GetAwaiter().GetResult();
        public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
        public override void SetLength(long value) => throw new NotSupportedException();
        public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();
    }
}
