using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace CortexTerminal.AgentRunner.Mcp;

/// <summary>
/// Local HTTP MCP server running on 127.0.0.1 inside the cortap wrapper. Registers a single
/// <c>change_title</c> tool that Claude Code calls to report the chat session title. When
/// invoked, fires <see cref="OnTitleChanged"/> so the wrapper can POST a synthetic
/// <c>AiTitleGenerated</c> event to the Worker, which fans out to the Console via the existing
/// agent activity pipeline.
///
/// <para>
/// Mirrors happy-cli's <c>startHappyServer.ts</c>: Streamable HTTP transport, <b>no session id</b>
/// (returning one makes Claude Code spawn fail with "Invalid Request: Server already initialized"),
/// single tool registered with the same name + description + input schema. Built on raw
/// <see cref="TcpListener"/> with hand-rolled HTTP/1.1 parsing because cortap is AOT-published
/// and we deliberately keep the wrapper free of ASP.NET Core.
/// </para>
/// </summary>
public sealed class CortermMcpServer : IAsyncDisposable, IDisposable
{
    private const string ProtocolVersion = "2025-06-18";
    private const string ServerName = "corterm";
    private const string ServerVersion = "1.0.0";
    private const string ChangeTitleToolName = "change_title";
    private const string ChangeTitleToolDescription = "Change the title of the current chat session";
    private const string TitleArgDescription = "The new title for the chat session";

    private TcpListener? _listener;
    private CancellationTokenSource? _cts;
    private Task? _acceptLoop;

    public string Url { get; private set; } = string.Empty;

    /// <summary>
    /// Fired when Claude Code calls <c>change_title</c>. The handler is awaited synchronously
    /// before the JSON-RPC success response is returned to Claude so a persisted title shows up
    /// on the Console by the time the next user turn starts.
    /// </summary>
    public event Func<string, CancellationToken, Task>? OnTitleChanged;

    public Task StartAsync(CancellationToken cancellationToken)
    {
        if (_listener is not null) throw new InvalidOperationException("MCP server already started.");

        _cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        _listener = new TcpListener(IPAddress.Loopback, port: 0);
        _listener.Start();
        var port = ((IPEndPoint)_listener.LocalEndpoint).Port;
        Url = $"http://127.0.0.1:{port}/mcp";

        _acceptLoop = AcceptLoopAsync(_cts.Token);
        return Task.CompletedTask;
    }

    public async Task StopAsync()
    {
        var cts = _cts;
        if (cts is null) return;
        _cts = null;

        cts.Cancel();
        if (_listener is not null)
        {
            _listener.Stop();
            _listener = null;
        }
        if (_acceptLoop is not null)
        {
            try { await _acceptLoop.ConfigureAwait(false); }
            catch { }
            _acceptLoop = null;
        }
        cts.Dispose();
    }

    public void Dispose()
    {
        _ = StopAsync();
        GC.SuppressFinalize(this);
    }

    public async ValueTask DisposeAsync()
    {
        await StopAsync().ConfigureAwait(false);
        GC.SuppressFinalize(this);
    }

    private async Task AcceptLoopAsync(CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            TcpClient client;
            try
            {
                client = await _listener!.AcceptTcpClientAsync(cancellationToken).ConfigureAwait(false);
            }
            catch (OperationCanceledException) { break; }
            catch (SocketException) { break; }
            catch (ObjectDisposedException) { break; }

            _ = HandleClientAsync(client, cancellationToken);
        }
    }

    private async Task HandleClientAsync(TcpClient client, CancellationToken cancellationToken)
    {
        using var _d = client;
        try
        {
            client.NoDelay = true;
            using var stream = client.GetStream();

            string? requestBody;
            try
            {
                requestBody = await ReadRequestBodyAsync(stream, cancellationToken).ConfigureAwait(false);
            }
            catch (OperationCanceledException) { return; }
            if (requestBody is null)
            {
                await WriteResponseAsync(stream, HttpStatusCode.BadRequest, body: string.Empty, cancellationToken).ConfigureAwait(false);
                return;
            }

            var (status, body) = await ProcessJsonRpcAsync(requestBody, cancellationToken).ConfigureAwait(false);
            await WriteResponseAsync(stream, status, body, cancellationToken).ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            // Per-client failure: log so the operator sees it, but don't crash the accept loop
            // — killing the MCP server would silently break title updates for the whole session.
            Console.Error.WriteLine($"cortap mcp: request failed: {ex.Message}");
        }
    }

    /// <summary>
    /// Minimal HTTP/1.1 reader: scan for the first <c>\r\n\r\n</c> separator, parse headers for
    /// Content-Length, then read that many body bytes. Supports POST only — MCP Streamable HTTP
    /// never uses other methods on this endpoint.
    /// </summary>
    private static async Task<string?> ReadRequestBodyAsync(NetworkStream stream, CancellationToken cancellationToken)
    {
        var buffer = new byte[8192];
        var totalRead = 0;
        var headerEndIndex = -1;

        while (headerEndIndex < 0)
        {
            if (totalRead >= buffer.Length)
            {
                // Headers too large for our buffer — bail.
                return null;
            }
            var n = await stream.ReadAsync(buffer.AsMemory(totalRead), cancellationToken).ConfigureAwait(false);
            if (n == 0) return totalRead == 0 ? null : string.Empty;
            totalRead += n;

            for (var i = 3; i < totalRead; i++)
            {
                if (buffer[i - 3] == '\r' && buffer[i - 2] == '\n' &&
                    buffer[i - 1] == '\r' && buffer[i] == '\n')
                {
                    headerEndIndex = i;
                    break;
                }
            }
        }

        var headerText = Encoding.ASCII.GetString(buffer, 0, headerEndIndex - 3);
        var lines = headerText.Split("\r\n", StringSplitOptions.RemoveEmptyEntries);
        if (lines.Length == 0) return null;

        var requestLine = lines[0];
        var requestParts = requestLine.Split(' ');
        if (requestParts.Length < 3 || !string.Equals(requestParts[0], "POST", StringComparison.Ordinal))
        {
            return null;
        }

        var contentLength = 0;
        foreach (var line in lines.AsSpan(1))
        {
            var colonIdx = line.IndexOf(':');
            if (colonIdx < 0) continue;
            var name = line[..colonIdx].Trim();
            var value = line[(colonIdx + 1)..].Trim();
            if (string.Equals(name, "Content-Length", StringComparison.OrdinalIgnoreCase))
            {
                int.TryParse(value, out contentLength);
            }
        }

        if (contentLength <= 0) return string.Empty;
        if (contentLength > 1_000_000)
        {
            // Unreasonably large — refuse to allocate.
            return null;
        }

        var bodyBytes = new byte[contentLength];
        var bodyStart = headerEndIndex + 1;
        var alreadyRead = totalRead - bodyStart;
        if (alreadyRead > 0)
        {
            Array.Copy(buffer, bodyStart, bodyBytes, 0, Math.Min(alreadyRead, contentLength));
        }

        var remaining = contentLength - alreadyRead;
        var offset = alreadyRead;
        while (remaining > 0)
        {
            var n = await stream.ReadAsync(bodyBytes.AsMemory(offset, remaining), cancellationToken).ConfigureAwait(false);
            if (n == 0) return null;
            offset += n;
            remaining -= n;
        }

        return Encoding.UTF8.GetString(bodyBytes);
    }

    private async Task<(HttpStatusCode status, string body)> ProcessJsonRpcAsync(string body, CancellationToken cancellationToken)
    {
        JsonDocument doc;
        try
        {
            doc = JsonDocument.Parse(body);
        }
        catch (JsonException)
        {
            return (HttpStatusCode.OK, JsonRpcError(null, -32700, "Parse error"));
        }

        using (doc)
        {
            var root = doc.RootElement;
            if (root.ValueKind != JsonValueKind.Object)
            {
                return (HttpStatusCode.OK, JsonRpcError(null, -32600, "Invalid Request: not an object"));
            }

            var hasId = root.TryGetProperty("id", out var idEl);
            var idJson = hasId ? idEl.GetRawText() : "null";

            if (!root.TryGetProperty("method", out var methodEl) ||
                methodEl.ValueKind != JsonValueKind.String)
            {
                return (HttpStatusCode.OK, JsonRpcError(idJson, -32600, "Invalid Request: missing method"));
            }
            var method = methodEl.GetString() ?? string.Empty;

            if (!hasId)
            {
                // Notification — no response body per JSON-RPC spec. MCP uses 202 Accepted.
                return (HttpStatusCode.Accepted, string.Empty);
            }

            switch (method)
            {
                case "initialize":
                    return (HttpStatusCode.OK, JsonRpcResult(idJson, BuildInitializeResult()));
                case "notifications/initialized":
                    // Treated as a request when id is present (non-standard) — return empty result.
                    return (HttpStatusCode.OK, JsonRpcResult(idJson, "{}"));
                case "tools/list":
                    return (HttpStatusCode.OK, JsonRpcResult(idJson, BuildToolsListResult()));
                case "ping":
                    return (HttpStatusCode.OK, JsonRpcResult(idJson, "{}"));
                case "tools/call":
                    return await HandleToolsCallAsync(idJson, root, cancellationToken).ConfigureAwait(false);
                default:
                    return (HttpStatusCode.OK, JsonRpcError(idJson, -32601, $"Method not found: {method}"));
            }
        }
    }

    private async Task<(HttpStatusCode status, string body)> HandleToolsCallAsync(string idJson, JsonElement root, CancellationToken cancellationToken)
    {
        if (!root.TryGetProperty("params", out var paramsEl) || paramsEl.ValueKind != JsonValueKind.Object)
        {
            return (HttpStatusCode.OK, JsonRpcResult(idJson, BuildToolCallText("Missing params object.", isError: true)));
        }

        if (!paramsEl.TryGetProperty("name", out var nameEl) ||
            nameEl.ValueKind != JsonValueKind.String)
        {
            return (HttpStatusCode.OK, JsonRpcResult(idJson, BuildToolCallText("Missing tool name.", isError: true)));
        }

        var toolName = nameEl.GetString();
        if (toolName != ChangeTitleToolName)
        {
            return (HttpStatusCode.OK, JsonRpcResult(idJson, BuildToolCallText($"Unknown tool: {toolName}", isError: true)));
        }

        string? title = null;
        if (paramsEl.TryGetProperty("arguments", out var argsEl))
        {
            if (argsEl.ValueKind != JsonValueKind.Object)
            {
                return (HttpStatusCode.OK, JsonRpcResult(idJson, BuildToolCallText("arguments must be an object.", isError: true)));
            }
            if (argsEl.TryGetProperty("title", out var titleEl))
            {
                if (titleEl.ValueKind != JsonValueKind.String)
                {
                    return (HttpStatusCode.OK, JsonRpcResult(idJson, BuildToolCallText("title must be a string.", isError: true)));
                }
                title = titleEl.GetString();
            }
        }

        if (string.IsNullOrWhiteSpace(title))
        {
            return (HttpStatusCode.OK, JsonRpcResult(idJson, BuildToolCallText("title is required and must not be empty.", isError: true)));
        }

        var trimmed = title!.Trim();
        var handler = OnTitleChanged;
        if (handler is null)
        {
            // Wrapper bug: MCP server started but no handler wired. Surface as JSON-RPC error
            // so Claude sees the failure rather than getting a silent no-op.
            return (HttpStatusCode.OK, JsonRpcError(idJson, -32603, "No OnTitleChanged handler registered."));
        }

        try
        {
            await handler(trimmed, cancellationToken).ConfigureAwait(false);
        }
        catch (OperationCanceledException) { throw; }
        catch (Exception ex)
        {
            return (HttpStatusCode.OK, JsonRpcResult(idJson, BuildToolCallText($"Failed to update title: {ex.Message}", isError: true)));
        }

        return (HttpStatusCode.OK, JsonRpcResult(idJson, BuildToolCallText($"Title updated to: \"{trimmed}\"", isError: false)));
    }

    private static string BuildInitializeResult()
    {
        var result = new JsonObject
        {
            ["protocolVersion"] = ProtocolVersion,
            ["capabilities"] = new JsonObject
            {
                ["tools"] = new JsonObject { ["listChanged"] = false },
            },
            ["serverInfo"] = new JsonObject
            {
                ["name"] = ServerName,
                ["version"] = ServerVersion,
            },
        };
        return result.ToJsonString();
    }

    private static string BuildToolsListResult()
    {
        var required = new JsonArray { (JsonNode)"title" };
        var properties = new JsonObject
        {
            ["title"] = new JsonObject
            {
                ["type"] = "string",
                ["description"] = TitleArgDescription,
            },
        };
        var inputSchema = new JsonObject
        {
            ["type"] = "object",
            ["properties"] = properties,
            ["required"] = required,
        };
        var tool = new JsonObject
        {
            ["name"] = ChangeTitleToolName,
            ["description"] = ChangeTitleToolDescription,
            ["inputSchema"] = inputSchema,
        };
        var result = new JsonObject { ["tools"] = new JsonArray { (JsonNode)tool } };
        return result.ToJsonString();
    }

    private static string BuildToolCallText(string text, bool isError)
    {
        var content = new JsonArray
        {
            (JsonNode)new JsonObject
            {
                ["type"] = "text",
                ["text"] = text,
            },
        };
        var result = new JsonObject
        {
            ["content"] = content,
            ["isError"] = isError,
        };
        return result.ToJsonString();
    }

    private static string JsonRpcResult(string idJson, string resultJson)
    {
        var resp = new JsonObject
        {
            ["jsonrpc"] = "2.0",
            ["id"] = JsonNode.Parse(idJson),
            ["result"] = JsonNode.Parse(resultJson),
        };
        return resp.ToJsonString();
    }

    private static string JsonRpcError(string? idJson, int code, string message)
    {
        var resp = new JsonObject
        {
            ["jsonrpc"] = "2.0",
            ["id"] = JsonNode.Parse(idJson ?? "null"),
            ["error"] = new JsonObject
            {
                ["code"] = code,
                ["message"] = message,
            },
        };
        return resp.ToJsonString();
    }

    private static async Task WriteResponseAsync(NetworkStream stream, HttpStatusCode status, string body, CancellationToken cancellationToken)
    {
        var statusLine = status switch
        {
            HttpStatusCode.OK => "HTTP/1.1 200 OK",
            HttpStatusCode.Accepted => "HTTP/1.1 202 Accepted",
            HttpStatusCode.BadRequest => "HTTP/1.1 400 Bad Request",
            _ => "HTTP/1.1 500 Internal Server Error",
        };

        var bodyBytes = body.Length == 0 ? Array.Empty<byte>() : Encoding.UTF8.GetBytes(body);

        var header = new StringBuilder();
        header.Append(statusLine).Append("\r\n");
        if (bodyBytes.Length > 0)
        {
            header.Append("Content-Type: application/json\r\n");
            header.Append("Content-Length: ").Append(bodyBytes.Length).Append("\r\n");
        }
        else
        {
            header.Append("Content-Length: 0\r\n");
        }
        header.Append("\r\n");

        var headerBytes = Encoding.ASCII.GetBytes(header.ToString());
        await stream.WriteAsync(headerBytes, cancellationToken).ConfigureAwait(false);
        if (bodyBytes.Length > 0)
        {
            await stream.WriteAsync(bodyBytes, cancellationToken).ConfigureAwait(false);
        }
    }
}
