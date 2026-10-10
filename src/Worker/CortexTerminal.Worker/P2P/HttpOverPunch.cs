using System.Text;
using CortexTerminal.Worker.RemoteFiles;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging;

namespace CortexTerminal.Worker.P2P;

/// <summary>
/// 精简 HTTP/1.1 over 可靠流（规格 §4）：Worker 端服务 + 测试/客户端小助手。
/// 语义与 LocalTransferListener 完全一致 —— PUT/GET /transfer/{id}?token= 映射到
/// RelayTransferService 的 pending-transfer 认领逻辑（上传落盘 + sha 校验 + 原子替换、
/// 下载流式回传；401/404/409/502 状态码相同）。
/// </summary>
public static class PunchHttp
{
    private const int MaxHeaderBytes = 16 * 1024;

    /// <summary>服务一条已打通的可靠流：解析一个请求、应答、写完 FIN。</summary>
    public static async Task ServeAsync(PunchStream stream, RelayTransferService transfers, ILogger logger, CancellationToken ct)
    {
        try
        {
            await ServeCoreAsync(stream, transfers, ct);
            // 规格 §4：响应写完即 FIN。
            stream.CompleteWriting();
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception ex)
        {
            // 内部错误：不能静默假成功 —— 记日志并向对端 RST。
            logger.LogError(ex, "P2P transfer HTTP serving failed.");
            stream.Abort(new IOException("p2p transfer serving failed", ex));
            throw;
        }
    }

    private static async Task ServeCoreAsync(PunchStream stream, RelayTransferService transfers, CancellationToken ct)
    {
            var headerText = await ReadHeaderAsync(stream, ct);
            var request = ParseRequest(headerText);

            if (!request.Path.StartsWith("/transfer/", StringComparison.Ordinal))
            {
                await WriteJsonResponseAsync(stream, StatusCodes.Status404NotFound, "not_found", "no such route", ct);
                return;
            }
            var transferId = Uri.UnescapeDataString(request.Path["/transfer/".Length..]);

            switch (request.Method)
            {
                case "PUT":
                {
                    var body = new LimitedStream(stream, request.ContentLength);
                    var outcome = await transfers.HandleLocalUploadAsync(
                        transferId, request.Token, body, ct);
                    await WriteOutcomeAsync(stream, outcome, ct);
                    return;
                }
                case "GET":
                {
                    var (outcome, handle) = await transfers.HandleLocalDownloadAsync(transferId, request.Token, ct);
                    if (!outcome.Success || handle is null)
                    {
                        await WriteOutcomeAsync(stream, outcome, ct);
                        return;
                    }
                    await WriteResponseHeadAsync(stream, StatusCodes.Status200OK, "OK",
                        contentType: "application/octet-stream",
                        contentLength: handle.SizeBytes,
                        extraHeaders: $"Content-Disposition: attachment; filename=\"{EscapeHeader(handle.Filename)}\"\r\n",
                        ct);
                    await using var file = File.OpenRead(handle.FilePath);
                    await file.CopyToAsync(stream, ct);
                    await stream.FlushAsync(ct);
                    return;
                }
                default:
                    await WriteJsonResponseAsync(stream, StatusCodes.Status405MethodNotAllowed,
                        "method_not_allowed", $"method {request.Method} is not supported", ct);
                    return;
            }
    }

    private static async Task WriteOutcomeAsync(Stream stream, LocalTransferOutcome outcome, CancellationToken ct)
    {
        if (outcome.Success)
        {
            await WriteJsonResponseAsync(stream, StatusCodes.Status200OK, null, null, ct, body: """{"success":true}""");
            return;
        }
        await WriteJsonResponseAsync(stream, outcome.Status, outcome.Code ?? "transfer_failed", outcome.Message, ct);
    }

    private static async Task WriteJsonResponseAsync(
        Stream stream, int status, string? code, string? message, CancellationToken ct, string? body = null)
    {
        body ??= System.Text.Json.JsonSerializer.Serialize(new { error = code, message });
        await WriteResponseHeadAsync(stream, status, Reason(status), "application/json", body.Length, extraHeaders: null, ct);
        var bytes = Encoding.UTF8.GetBytes(body);
        await stream.WriteAsync(bytes, ct);
        await stream.FlushAsync(ct);
    }

    private static async Task WriteResponseHeadAsync(
        Stream stream, int status, string reason, string? contentType, long contentLength, string? extraHeaders, CancellationToken ct)
    {
        var head = new StringBuilder();
        head.Append("HTTP/1.1 ").Append(status).Append(' ').Append(reason).Append("\r\n");
        if (contentType is not null)
        {
            head.Append("Content-Type: ").Append(contentType).Append("\r\n");
        }
        head.Append("Content-Length: ").Append(contentLength).Append("\r\n");
        if (extraHeaders is not null)
        {
            head.Append(extraHeaders);
        }
        head.Append("\r\n");
        var bytes = Encoding.ASCII.GetBytes(head.ToString());
        await stream.WriteAsync(bytes, ct);
    }

    private static async Task<string> ReadHeaderAsync(Stream stream, CancellationToken ct)
    {
        var buffer = new MemoryStream();
        var one = new byte[1];
        while (true)
        {
            if (buffer.Length > MaxHeaderBytes)
            {
                throw new InvalidDataException("HTTP request head exceeds the 16 KB limit");
            }
            var read = await stream.ReadAsync(one, ct);
            if (read == 0)
            {
                throw new InvalidDataException("stream closed before HTTP request head completed");
            }
            buffer.WriteByte(one[0]);
            // 以 "\r\n\r\n" 结束
            var bytes = buffer.GetBuffer().AsSpan(0, (int)buffer.Length);
            if (bytes.Length >= 4 && bytes[^4..].SequenceEqual("\r\n\r\n"u8))
            {
                break;
            }
        }
        return Encoding.ASCII.GetString(buffer.GetBuffer(), 0, (int)buffer.Length);
    }

    internal static PunchedHttpRequest ParseRequest(string headerText)
    {
        var end = headerText.IndexOf("\r\n\r\n", StringComparison.Ordinal);
        var head = end >= 0 ? headerText[..end] : headerText;
        var lines = head.Split("\r\n");
        var requestLine = lines[0].Split(' ');
        if (requestLine.Length < 3 || !requestLine[2].StartsWith("HTTP/1.", StringComparison.Ordinal))
        {
            throw new InvalidDataException($"malformed request line: {lines[0]}");
        }
        long contentLength = 0;
        foreach (var line in lines.Skip(1))
        {
            var sep = line.IndexOf(':');
            if (sep <= 0)
            {
                continue;
            }
            if (line[..sep].Trim().Equals("Content-Length", StringComparison.OrdinalIgnoreCase)
                && !long.TryParse(line[(sep + 1)..].Trim(), out contentLength))
            {
                throw new InvalidDataException("malformed Content-Length header");
            }
        }

        var target = requestLine[1];
        var queryIndex = target.IndexOf('?');
        var path = queryIndex >= 0 ? target[..queryIndex] : target;
        var query = queryIndex >= 0 ? target[(queryIndex + 1)..] : "";
        string token = "";
        foreach (var pair in query.Split('&', StringSplitOptions.RemoveEmptyEntries))
        {
            var eq = pair.IndexOf('=');
            if (eq > 0 && pair[..eq] == "token")
            {
                token = Uri.UnescapeDataString(pair[(eq + 1)..]);
            }
        }
        return new PunchedHttpRequest(requestLine[0], path, token, contentLength);
    }

    private static string Reason(int status) => status switch
    {
        200 => "OK",
        401 => "Unauthorized",
        404 => "Not Found",
        405 => "Method Not Allowed",
        409 => "Conflict",
        502 => "Bad Gateway",
        _ => "Error",
    };

    private static string EscapeHeader(string value)
        => value.Replace("\\", "\\\\").Replace("\"", "\\\"");

    public sealed record PunchedHttpRequest(string Method, string Path, string Token, long ContentLength);
}

/// <summary>把可靠流限制为请求体字节流：最多读 Content-Length 字节即 EOF。</summary>
internal sealed class LimitedStream : Stream
{
    private readonly Stream _inner;
    private readonly long _limit;
    private long _remaining;

    public LimitedStream(Stream inner, long limit)
    {
        _inner = inner;
        _limit = limit;
        _remaining = limit;
    }

    public override bool CanRead => true;
    public override bool CanSeek => false;
    public override bool CanWrite => false;
    public override long Length => _limit;
    public override long Position { get => _limit - _remaining; set => throw new NotSupportedException(); }
    public override void Flush() { }
    public override int Read(byte[] buffer, int offset, int count)
        => ReadAsync(buffer.AsMemory(offset, count)).AsTask().GetAwaiter().GetResult();

    public override async ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken cancellationToken = default)
    {
        if (_remaining <= 0)
        {
            return 0;
        }
        if (buffer.Length > _remaining)
        {
            buffer = buffer[..(int)_remaining];
        }
        var read = await _inner.ReadAsync(buffer, cancellationToken);
        _remaining -= read;
        return read;
    }

    public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
    public override void SetLength(long value) => throw new NotSupportedException();
    public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();
}

/// <summary>测试/客户端侧最小 HTTP 助手：在打通的可靠流上执行 PUT/GET 并读回响应。</summary>
public static class PunchHttpClient
{
    public static async Task<PunchHttpResponse> PutAsync(
        PunchStream stream, string transferId, string token, ReadOnlyMemory<byte> body, CancellationToken ct)
    {
        var head =
            $"PUT /transfer/{Uri.EscapeDataString(transferId)}?token={Uri.EscapeDataString(token)} HTTP/1.1\r\n" +
            "Host: p2p\r\nContent-Type: application/octet-stream\r\n" +
            $"Content-Length: {body.Length}\r\n\r\n";
        await stream.WriteAsync(Encoding.ASCII.GetBytes(head), ct);
        await stream.WriteAsync(body, ct);
        await stream.FlushAsync(ct);
        stream.CompleteWriting(); // 半关闭：服务端读体到 EOF
        return await ReadResponseAsync(stream, readBody: true, ct);
    }

    public static async Task<PunchHttpResponse> GetAsync(PunchStream stream, string transferId, string token, CancellationToken ct)
    {
        var head =
            $"GET /transfer/{Uri.EscapeDataString(transferId)}?token={Uri.EscapeDataString(token)} HTTP/1.1\r\n" +
            "Host: p2p\r\n\r\n";
        await stream.WriteAsync(Encoding.ASCII.GetBytes(head), ct);
        await stream.FlushAsync(ct);
        return await ReadResponseAsync(stream, readBody: true, ct);
    }

    public static async Task<PunchHttpResponse> ReadResponseAsync(Stream stream, bool readBody, CancellationToken ct)
    {
        var head = new MemoryStream();
        var one = new byte[1];
        while (true)
        {
            var read = await stream.ReadAsync(one, ct);
            if (read == 0)
            {
                throw new InvalidDataException("stream closed before HTTP response head completed");
            }
            head.WriteByte(one[0]);
            var span = head.GetBuffer().AsSpan(0, (int)head.Length);
            if (span.Length >= 4 && span[^4..].SequenceEqual("\r\n\r\n"u8))
            {
                break;
            }
        }
        var text = Encoding.ASCII.GetString(head.GetBuffer(), 0, (int)head.Length);
        var lines = text.Split("\r\n");
        var statusLine = lines[0].Split(' ');
        if (statusLine.Length < 2 || !statusLine[0].StartsWith("HTTP/1.", StringComparison.Ordinal))
        {
            throw new InvalidDataException($"malformed status line: {lines[0]}");
        }
        var status = int.Parse(statusLine[1]);
        long contentLength = 0;
        foreach (var line in lines.Skip(1))
        {
            var sep = line.IndexOf(':');
            if (sep > 0 && line[..sep].Trim().Equals("Content-Length", StringComparison.OrdinalIgnoreCase))
            {
                contentLength = long.Parse(line[(sep + 1)..].Trim());
            }
        }

        var body = new byte[contentLength];
        var offset = 0;
        while (offset < body.Length)
        {
            var read = await stream.ReadAsync(body.AsMemory(offset), ct);
            if (read == 0)
            {
                throw new InvalidDataException("stream closed before response body completed");
            }
            offset += read;
        }
        return new PunchHttpResponse(status, body);
    }

    public sealed record PunchHttpResponse(int Status, byte[] Body);
}
