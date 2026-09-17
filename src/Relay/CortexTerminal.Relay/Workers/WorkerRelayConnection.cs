using System.Collections.Concurrent;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using System.Threading.Channels;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Relay.Transfers;

namespace CortexTerminal.Relay.Workers;

/// <summary>一次隧道调用（访客请求）在 Worker 连接上的挂起状态。</summary>
public sealed class TunnelCall
{
    public TunnelCall(string id)
    {
        Id = id;
    }

    public string Id { get; }
    public TaskCompletionSource<TunnelResponseHeadFrame> Head { get; } =
        new(TaskCreationOptions.RunContinuationsAsynchronously);
    public Channel<byte[]> ResponseBody { get; } =
        Channel.CreateBounded<byte[]>(new BoundedChannelOptions(128) { SingleReader = true, SingleWriter = true });
    public TaskCompletionSource<TunnelEndFrame> End { get; } =
        new(TaskCreationOptions.RunContinuationsAsynchronously);
}

/// <summary>
/// 一条 Worker ↔ Relay 持久 WebSocket。对外暴露 <see cref="CallAsync"/>（发 treq、回流响应），
/// 内部一个发送任务（串行化所有出站帧）+ 一个接收循环（按 requestId 分发入站帧）。
/// </summary>
public sealed class WorkerRelayConnection
{
    private readonly WebSocket _socket;
    private readonly ConcurrentDictionary<string, TunnelCall> _calls = new(StringComparer.Ordinal);
    private readonly Channel<byte[]> _outgoing =
        Channel.CreateBounded<byte[]>(new BoundedChannelOptions(1024)
        {
            SingleReader = true,
            SingleWriter = false,
        });

    public WorkerRelayConnection(string workerId, WebSocket socket)
    {
        WorkerId = workerId;
        _socket = socket;
    }

    public string WorkerId { get; }
    public bool IsOpen => _socket.State == WebSocketState.Open;

    /// <summary>
    /// 发起一次隧道转发：登记挂起调用 → 出站队列发 treq（+请求体二进制帧 + treqend）。
    /// 请求体按 <see cref="RelayProtocol.DataChunkSize"/> 分帧流式发送，读多少发多少（背压）。
    /// </summary>
    public async Task<TunnelCall> CallAsync(
        TunnelRequestFrame request, Stream? requestBody, CancellationToken ct)
    {
        var call = new TunnelCall(request.Id);
        _calls[request.Id] = call;
        _outgoing.Writer.TryWrite(JsonSerializer.SerializeToUtf8Bytes(request, RelayJson.Default));

        if (requestBody is not null && requestBody.CanRead)
        {
            var buffer = new byte[RelayProtocol.DataChunkSize];
            int read;
            while ((read = await requestBody.ReadAsync(buffer, ct)) > 0)
            {
                _outgoing.Writer.TryWrite(EncodeDataFrame(request.Id, buffer.AsSpan(0, read)));
            }
            var end = JsonSerializer.SerializeToUtf8Bytes(
                new TunnelRequestBodyEndFrame { Id = request.Id }, RelayJson.Default);
            _outgoing.Writer.TryWrite(end);
        }
        return call;
    }

    /// <summary>连接主循环：发送任务 + 接收循环并发跑，直到连接关闭。</summary>
    public async Task RunAsync(CancellationToken ct)
    {
        var sendTask = SendLoopAsync(ct);
        try
        {
            await ReceiveLoopAsync(ct);
        }
        finally
        {
            _outgoing.Writer.TryComplete();
            foreach (var call in _calls.Values)
            {
                FailCall(call, "worker connection closed");
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

    private async Task SendLoopAsync(CancellationToken ct)
    {
        var reader = _outgoing.Reader;
        while (await reader.WaitToReadAsync(ct))
        {
            while (reader.TryRead(out var bytes))
            {
                await _socket.SendAsync(bytes, WebSocketMessageType.Text, endOfMessage: true, ct);
            }
        }
    }

    private async Task ReceiveLoopAsync(CancellationToken ct)
    {
        var buffer = new byte[RelayProtocol.DataChunkSize];
        while (!ct.IsCancellationRequested && _socket.State == WebSocketState.Open)
        {
            var frame = await ReceiveMessageAsync(_socket, buffer, ct);
            if (frame is null) return;

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

    private void HandleControlFrame(byte[] utf8Json)
    {
        string? type;
        try
        {
            using var doc = JsonDocument.Parse(utf8Json);
            type = doc.RootElement.TryGetProperty("type", out var t) ? t.GetString() : null;
        }
        catch (JsonException)
        {
            return;
        }

        if (type == RelayProtocol.TunnelResponseHeadType)
        {
            var head = TryDeserialize<TunnelResponseHeadFrame>(utf8Json);
            if (head is not null && _calls.TryGetValue(head.Id, out var call))
            {
                call.Head.TrySetResult(head);
            }
        }
        else if (type == RelayProtocol.TunnelEndType)
        {
            var end = TryDeserialize<TunnelEndFrame>(utf8Json);
            if (end is not null && _calls.TryRemove(end.Id, out var call))
            {
                call.ResponseBody.Writer.TryComplete();
                call.End.TrySetResult(end);
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
        if (!_calls.TryGetValue(id, out var call)) return;

        var payload = payloadStart == data.Length
            ? Array.Empty<byte>()
            : data[payloadStart..];
        call.ResponseBody.Writer.TryWrite(payload);
    }

    private static byte[] EncodeDataFrame(string requestId, ReadOnlySpan<byte> payload)
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

    private static void FailCall(TunnelCall call, string reason)
    {
        call.ResponseBody.Writer.TryComplete();
        call.Head.TrySetException(new InvalidOperationException(reason));
        call.End.TrySetResult(new TunnelEndFrame { Id = call.Id, Error = reason });
    }

    private static async Task<RelayFrame?> ReceiveMessageAsync(WebSocket socket, byte[] buffer, CancellationToken ct)
    {
        var offset = 0;
        while (true)
        {
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
            if (offset == buffer.Length)
            {
                var grown = new byte[buffer.Length * 2];
                Array.Copy(buffer, grown, buffer.Length);
                buffer = grown;
            }
        }
    }

    private static T? TryDeserialize<T>(byte[] utf8Json) where T : class
    {
        try
        {
            return JsonSerializer.Deserialize<T>(utf8Json, RelayJson.Default);
        }
        catch (JsonException)
        {
            return null;
        }
    }
}

/// <summary>在线 Worker 连接表：workerId → 连接。</summary>
public sealed class WorkerRelayRegistry
{
    private readonly ConcurrentDictionary<string, WorkerRelayConnection> _workers = new(StringComparer.Ordinal);

    public void Register(WorkerRelayConnection connection)
        => _workers[connection.WorkerId] = connection;

    public void Unregister(string workerId, WorkerRelayConnection connection)
    {
        // 只在自己仍是注册者时移除，避免新连接被旧连接的清理误伤
        if (_workers.TryGetValue(workerId, out var current) && ReferenceEquals(current, connection))
        {
            _workers.TryRemove(workerId, out _);
        }
    }

    public WorkerRelayConnection? Find(string workerId)
        => _workers.TryGetValue(workerId, out var connection) && connection.IsOpen ? connection : null;
}
