using System.Net.WebSockets;
using System.Text.Json;
using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using Microsoft.Extensions.Options;
using System.Threading.Channels;

namespace CortexTerminal.Relay.Transfers;

/// <summary>
/// 文件传输的三个端点：
/// - PUT /transfer/{tid}  客户端上传：请求体流 → Worker WS（Worker 校验 sha 后落盘，done 帧回传终态）
/// - GET /transfer/{tid}  客户端下载：Worker WS 数据帧 → 响应体（Content-Length 已知，截断可检测）
/// - GET /transfer/{tid}/worker  Worker 侧 transfer WS（Gateway RPC 后由 Worker 发起）
/// Relay 只做内存流对拷，不落盘。
/// </summary>
public static class TransferEndpoints
{
    public const string TokenHeader = "X-Corterm-Transfer-Token";

    public static void Map(IEndpointRouteBuilder app)
    {
        app.MapPut("/transfer/{transferId}", HandleUploadAsync);
        app.MapGet("/transfer/{transferId}", HandleDownloadAsync);
        app.MapGet("/transfer/{transferId}/worker", HandleWorkerSocketAsync);
    }

    // ── 客户端上传 ────────────────────────────────────────────────

    private static async Task<IResult> HandleUploadAsync(
        string transferId, HttpContext context, TransferPairingRegistry registry, IOptions<RelayOptions> options)
    {
        var opts = options.Value;
        if (!TryValidateToken(context, transferId, opts.SharedSecret))
        {
            return Results.Unauthorized();
        }

        var pair = registry.GetOrCreate(transferId, DateTimeOffset.UtcNow.AddSeconds(opts.TransferTtlSeconds));
        try
        {
            using var linked = CancellationTokenSource.CreateLinkedTokenSource(pair.Lifetime.Token, context.RequestAborted);
            var worker = await pair.WorkerReady.Task
                .WaitAsync(TimeSpan.FromSeconds(opts.ClientWaitSeconds), linked.Token);

            await SendControlAsync(worker, new TransferStartFrame(), linked.Token);

            // 请求体 → Worker WS。await 链路自带背压：写不进去就不再读。
            var buffer = new byte[RelayProtocol.DataChunkSize];
            int read;
            while ((read = await context.Request.Body.ReadAsync(buffer, linked.Token)) > 0)
            {
                await worker.SendAsync(
                    buffer.AsMemory(0, read), WebSocketMessageType.Binary, endOfMessage: true, linked.Token);
            }

            var done = await ReadDoneAsync(pair, linked.Token);
            if (!done.Success)
            {
                return Results.Json(
                    new { error = done.Code ?? FileTransferErrorCode.TransferFailed, message = done.Message },
                    statusCode: StatusCodes.Status502BadGateway);
            }
            return Results.Json(new { success = true });
        }
        finally
        {
            registry.Remove(transferId);
        }
    }

    // ── 客户端下载 ────────────────────────────────────────────────

    private static async Task<IResult> HandleDownloadAsync(
        string transferId, HttpContext context, TransferPairingRegistry registry, IOptions<RelayOptions> options)
    {
        var opts = options.Value;
        if (!TryValidateToken(context, transferId, opts.SharedSecret))
        {
            return Results.Unauthorized();
        }

        var pair = registry.GetOrCreate(transferId, DateTimeOffset.UtcNow.AddSeconds(opts.TransferTtlSeconds));
        try
        {
            using var linked = CancellationTokenSource.CreateLinkedTokenSource(pair.Lifetime.Token, context.RequestAborted);
            var worker = await pair.WorkerReady.Task
                .WaitAsync(TimeSpan.FromSeconds(opts.ClientWaitSeconds), linked.Token);

            await SendControlAsync(worker, new TransferStartFrame(), linked.Token);

            // 通道消费：filehead（定响应头）→ 二进制数据帧（写响应体）→ done（终态）。
            var reader = pair.FromWorker.Reader;
            var headSeen = false;
            while (await reader.WaitToReadAsync(linked.Token))
            {
                while (reader.TryRead(out var frame))
                {
                    if (frame.MessageType == WebSocketMessageType.Text)
                    {
                        var head = TryDeserialize<FileHeadFrame>(frame.Data);
                        if (head is not null && head.Type == RelayProtocol.FileHeadType)
                        {
                            context.Response.StatusCode = StatusCodes.Status200OK;
                            context.Response.ContentLength = head.Size;
                            context.Response.Headers.Append("Content-Disposition",
                                $"attachment; filename=\"{head.Filename}\"");
                            headSeen = true;
                            continue;
                        }

                        // done 或未知控制帧
                        var done = TryDeserialize<TransferDoneFrame>(frame.Data);
                        if (done is not null && !done.Success && !headSeen)
                        {
                            // 响应未开始：Worker 侧失败以 HTTP 状态回给客户端
                            return Results.Json(
                                new { error = done.Code ?? FileTransferErrorCode.TransferFailed, message = done.Message },
                                statusCode: StatusCodes.Status502BadGateway);
                        }
                        // 响应已开始：Content-Length 无法兑现 → 截断连接，客户端按收到的字节数检测失败
                        context.Abort();
                        return Results.Empty;
                    }

                    if (!headSeen)
                    {
                        // filehead 之前出现数据帧：协议违规
                        return Results.StatusCode(StatusCodes.Status502BadGateway);
                    }
                    await context.Response.Body.WriteAsync(frame.Data, linked.Token);
                }
            }

            // Worker WS 关闭而未发 done：Content-Length 兑现不了，截断
            context.Abort();
            return Results.Empty;
        }
        finally
        {
            registry.Remove(transferId);
        }
    }

    // ── Worker transfer WS ────────────────────────────────────────

    private static async Task<IResult> HandleWorkerSocketAsync(
        string transferId, HttpContext context, TransferPairingRegistry registry, IOptions<RelayOptions> options)
    {
        var opts = options.Value;
        if (!context.WebSockets.IsWebSocketRequest)
        {
            return Results.BadRequest(new { error = "websocket_required" });
        }
        if (!TryValidateToken(context, transferId, opts.SharedSecret))
        {
            return Results.Unauthorized();
        }

        var pair = registry.GetOrCreate(transferId, DateTimeOffset.UtcNow.AddSeconds(opts.TransferTtlSeconds));
        var socket = await context.WebSockets.AcceptWebSocketAsync();
        if (!pair.WorkerReady.TrySetResult(socket))
        {
            // 已有 Worker 占用该传输（重复连接）：直接关闭
            await socket.CloseAsync(WebSocketCloseStatus.NormalClosure, "duplicate worker", CancellationToken.None);
            return Results.Empty;
        }

        try
        {
            var buffer = new byte[RelayProtocol.DataChunkSize];
            while (!pair.Lifetime.IsCancellationRequested)
            {
                var frame = await ReceiveMessageAsync(socket, buffer, pair.Lifetime.Token);
                if (frame is null)
                {
                    break; // Worker 关闭
                }
                await pair.FromWorker.Writer.WriteAsync(frame.Value, pair.Lifetime.Token);
            }
        }
        catch (OperationCanceledException)
        {
            // 配对超时/完成/客户端断开：正常清理路径
        }
        finally
        {
            pair.FromWorker.Writer.TryComplete();
            registry.Remove(transferId);
        }
        return Results.Empty;
    }

    // ── 共用小件 ─────────────────────────────────────────────────

    private static bool TryValidateToken(HttpContext context, string transferId, string sharedSecret)
    {
        var token = context.Request.Query["token"].FirstOrDefault();
        if (string.IsNullOrEmpty(token))
        {
            token = context.Request.Headers[TokenHeader].FirstOrDefault();
        }
        return !string.IsNullOrEmpty(token)
            && RelayToken.TryValidate(sharedSecret, token, RelayToken.AudienceTransfer, transferId, out _);
    }

    internal static async Task SendControlAsync<T>(WebSocket socket, T frame, CancellationToken ct)
        where T : class
    {
        var bytes = JsonSerializer.SerializeToUtf8Bytes(frame, RelayJson.Default);
        await socket.SendAsync(bytes, WebSocketMessageType.Text, endOfMessage: true, ct);
    }

    /// <summary>组装一条完整 WS 消息（跨多个 ReceiveAsync 缓冲，始终返回独立副本）。返回 null 表示对端关闭。</summary>
    internal static async Task<RelayFrame?> ReceiveMessageAsync(WebSocket socket, byte[] buffer, CancellationToken ct)
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

    /// <summary>消费 Worker 帧通道直到 done 终态帧。</summary>
    private static async Task<TransferDoneFrame> ReadDoneAsync(TransferPair pair, CancellationToken ct)
    {
        var reader = pair.FromWorker.Reader;
        while (await reader.WaitToReadAsync(ct))
        {
            while (reader.TryRead(out var frame))
            {
                if (frame.MessageType != WebSocketMessageType.Text) continue;
                var done = TryDeserialize<TransferDoneFrame>(frame.Data);
                if (done is not null) return done;
            }
        }
        // Worker WS 关闭而未发 done：传输失败
        return new TransferDoneFrame
        {
            Success = false,
            Code = FileTransferErrorCode.TransferFailed,
            Message = "worker closed the transfer without a completion frame",
        };
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
