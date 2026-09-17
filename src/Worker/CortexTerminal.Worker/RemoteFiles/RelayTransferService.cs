using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Worker.Registration;
using Microsoft.Extensions.Logging;

namespace CortexTerminal.Worker.RemoteFiles;

/// <summary>
/// 工作区文件服务的 Worker 端执行器：
/// - <see cref="ListFiles"/>: 列出任意工作区根下的一个目录（根目录按调用传入）。
/// - <see cref="CreateWorkspaceDirectory"/>: mkdir -p 并回传解析后的绝对路径（拒绝逃逸出用户 home）。
/// 文件字节流转由 <see cref="RelayTransferService"/> 完成。
/// </summary>
public sealed class WorkspaceFileService(int maxListEntries, ILogger<WorkspaceFileService> logger)
{
    public FileListingResult ListFiles(string rootDir, string? relativePath)
        => new RemoteDirectoryLister(rootDir, maxListEntries).List(relativePath);

    public WorkspaceDirectoryAck CreateWorkspaceDirectory(CreateWorkspaceDirectoryCommand command)
    {
        if (!TryResolveWorkspaceDir(command.RootPath, out var dirPath, out var error))
        {
            return new WorkspaceDirectoryAck(false, error, ResolvedPath: "");
        }

        try
        {
            Directory.CreateDirectory(dirPath);
            var resolved = Path.GetFullPath(dirPath);
            logger.LogInformation("Workspace {WorkspaceId} directory ready at {Path}.", command.WorkspaceId, resolved);
            return new WorkspaceDirectoryAck(true, null, resolved);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to create workspace directory {Path}.", dirPath);
            return new WorkspaceDirectoryAck(false,
                new FileOperationError(FileTransferErrorCode.TransferFailed, ex.Message), ResolvedPath: "");
        }
    }

    /// <summary>
    /// 工作区根的解析规则：绝对路径原样使用（仍不得逃逸出用户 home）；相对路径基于 home 展开。
    /// 词法 ".." 逃逸一律拒绝。
    /// </summary>
    internal static bool TryResolveWorkspaceDir(string rootPath, out string fullPath, out FileOperationError? error)
    {
        fullPath = "";
        error = null;
        if (string.IsNullOrWhiteSpace(rootPath))
        {
            error = new FileOperationError(FileTransferErrorCode.PathInvalid, "rootPath is required");
            return false;
        }

        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var candidate = Path.IsPathRooted(rootPath)
            ? rootPath
            : Path.GetFullPath(Path.Combine(home, rootPath));

        var fullHome = Path.GetFullPath(home);
        if (!candidate.StartsWith(fullHome, StringComparison.Ordinal))
        {
            error = new FileOperationError(FileTransferErrorCode.AccessDenied,
                "workspace root must stay inside the user home");
            return false;
        }

        fullPath = candidate;
        return true;
    }
}

/// <summary>
/// Relay 传输执行器：Gateway RPC 先同步校验并立即应答，随后后台连入 Relay transfer WS，
/// 等待 start 帧后与客户端 HTTP 流做端到端对拷（上传落临时文件 + sha 校验 + 原子替换）。
/// 传输终态经 done 帧由 Relay 回传给客户端，Worker 不经由 Gateway 回报传输结果。
/// </summary>
public sealed class RelayTransferService(long maxTransferBytes, ILogger<RelayTransferService> logger)
{
    private readonly SemaphoreSlim _slots = new(4, 4);

    public Task<FileOperationAck> PrepareFileReceiveAsync(PrepareFileReceiveCommand command, CancellationToken ct)
    {
        if (!RemoteFileNameValidator.TryValidateSegment(command.Filename, out var reason))
        {
            return Task.FromResult(Fail(FileTransferErrorCode.PathInvalid, reason));
        }
        if (!RemotePathValidator.TryResolve(command.RootDir, command.DirPath, out var dirPath, out var pathError))
        {
            return Task.FromResult(Fail(pathError.Code, pathError.Message));
        }
        if (!Directory.Exists(dirPath))
        {
            return Task.FromResult(Fail(FileTransferErrorCode.PathNotFound, $"no such directory: {command.DirPath}"));
        }
        if (command.SizeBytes <= 0 || command.SizeBytes > maxTransferBytes)
        {
            return Task.FromResult(Fail(FileTransferErrorCode.FileTooLarge,
                $"transfer must be between 1 byte and {maxTransferBytes / (1024 * 1024)} MB"));
        }

        _ = Task.Run(() => ReceivePipelineAsync(command, Path.Combine(dirPath, command.Filename)), CancellationToken.None);
        return Task.FromResult(new FileOperationAck(true, null));
    }

    public Task<PrepareFileSendAck> PrepareFileSendAsync(PrepareFileSendCommand command, CancellationToken ct)
    {
        if (!RemotePathValidator.TryResolve(command.RootDir, command.RelativePath, out var filePath, out var pathError))
        {
            return Task.FromResult(new PrepareFileSendAck(false, pathError, 0, ""));
        }
        if (Directory.Exists(filePath))
        {
            return Task.FromResult(new PrepareFileSendAck(false,
                new FileOperationError(FileTransferErrorCode.NotADirectory, $"path is a directory: {command.RelativePath}"), 0, ""));
        }
        if (!File.Exists(filePath))
        {
            return Task.FromResult(new PrepareFileSendAck(false,
                new FileOperationError(FileTransferErrorCode.FileNotFound, $"no such file: {command.RelativePath}"), 0, ""));
        }

        var size = new FileInfo(filePath).Length;
        if (size > maxTransferBytes)
        {
            return Task.FromResult(new PrepareFileSendAck(false,
                new FileOperationError(FileTransferErrorCode.FileTooLarge,
                    $"file exceeds the {maxTransferBytes / (1024 * 1024)} MB transfer limit"), 0, ""));
        }

        var filename = Path.GetFileName(filePath);
        _ = Task.Run(() => SendPipelineAsync(command, filePath, size), CancellationToken.None);
        return Task.FromResult(new PrepareFileSendAck(true, null, size, filename));
    }

    /// <summary>上传：连 Relay → 等 start → 收文件 → sha 校验 → 原子落盘 → done。</summary>
    private async Task ReceivePipelineAsync(PrepareFileReceiveCommand command, string targetPath)
    {
        await _slots.WaitAsync();
        var tmpPath = targetPath + ".downloading";
        try
        {
            using var socket = new System.Net.WebSockets.ClientWebSocket();
            var uri = new Uri($"{command.RelayUrl.TrimEnd('/')}/transfer/{command.TransferId}/worker?token={Uri.EscapeDataString(command.Token)}");
            using var connectCts = new CancellationTokenSource(TimeSpan.FromSeconds(30));
            await socket.ConnectAsync(uri, connectCts.Token);

            await RelayProtocolIo.WaitStartAsync(socket, CancellationToken.None);

            byte[] sha;
            using (var shaInstance = SHA256.Create())
            await using (var file = File.Create(tmpPath))
            {
                long total = 0;
                await foreach (var chunk in RelayProtocolIo.ReadBinaryFramesAsync(socket, CancellationToken.None))
                {
                    total += chunk.Length;
                    if (total > command.SizeBytes)
                    {
                        throw new InvalidOperationException("received more bytes than declared sizeBytes");
                    }
                    await file.WriteAsync(chunk, CancellationToken.None);
                    shaInstance.TransformBlock(chunk, 0, chunk.Length, null, 0);
                }
                shaInstance.TransformFinalBlock(Array.Empty<byte>(), 0, 0);
                sha = shaInstance.Hash!;
                if (total != command.SizeBytes)
                {
                    throw new InvalidOperationException($"received {total} bytes, expected {command.SizeBytes}");
                }
            }

            var actual = Convert.ToHexString(sha).ToLowerInvariant();
            if (!string.Equals(actual, command.Sha256, StringComparison.OrdinalIgnoreCase))
            {
                File.Delete(tmpPath);
                logger.LogError("Transfer {TransferId} sha256 mismatch: expected {Expected}, got {Actual}.",
                    command.TransferId, command.Sha256, actual);
                await RelayProtocolIo.SendDoneAsync(socket, success: false,
                    FileTransferErrorCode.ShaMismatch, "uploaded content does not match its sha256", CancellationToken.None);
                return;
            }

            File.Move(tmpPath, targetPath, overwrite: true);
            logger.LogInformation("Transfer {TransferId} wrote {Path} ({Size} bytes).", command.TransferId, targetPath, command.SizeBytes);
            await RelayProtocolIo.SendDoneAsync(socket, success: true, null, null, CancellationToken.None);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Transfer {TransferId} receive failed.", command.TransferId);
            try { if (File.Exists(tmpPath)) File.Delete(tmpPath); } catch (IOException) { }
        }
        finally
        {
            _slots.Release();
        }
    }

    /// <summary>下载：连 Relay → 等 start → filehead → 流式发文件 → done。</summary>
    private async Task SendPipelineAsync(PrepareFileSendCommand command, string filePath, long size)
    {
        await _slots.WaitAsync();
        try
        {
            using var socket = new System.Net.WebSockets.ClientWebSocket();
            var uri = new Uri($"{command.RelayUrl.TrimEnd('/')}/transfer/{command.TransferId}/worker?token={Uri.EscapeDataString(command.Token)}");
            using var connectCts = new CancellationTokenSource(TimeSpan.FromSeconds(30));
            await socket.ConnectAsync(uri, connectCts.Token);

            await RelayProtocolIo.WaitStartAsync(socket, CancellationToken.None);
            await RelayProtocolIo.SendControlAsync(socket,
                new FileHeadFrame { Size = size, Filename = Path.GetFileName(filePath) }, CancellationToken.None);

            await using var file = File.OpenRead(filePath);
            var buffer = new byte[64 * 1024];
            int read;
            while ((read = await file.ReadAsync(buffer, CancellationToken.None)) > 0)
            {
                await socket.SendAsync(buffer.AsMemory(0, read),
                    System.Net.WebSockets.WebSocketMessageType.Binary, endOfMessage: true, CancellationToken.None);
            }

            logger.LogInformation("Transfer {TransferId} streamed {Path} ({Size} bytes).", command.TransferId, filePath, size);
            await RelayProtocolIo.SendDoneAsync(socket, success: true, null, null, CancellationToken.None);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Transfer {TransferId} send failed.", command.TransferId);
        }
        finally
        {
            _slots.Release();
        }
    }

    private static FileOperationAck Fail(string code, string message)
        => new(false, new FileOperationError(code, message));
}

/// <summary>Worker ↔ Relay transfer WS 的帧收发小件（控制 JSON 文本帧 + 64KB 二进制帧）。</summary>
public static class RelayProtocolIo
{
    public static async Task WaitStartAsync(System.Net.WebSockets.WebSocket socket, CancellationToken ct)
    {
        while (true)
        {
            var frame = await ReadFrameAsync(socket, ct);
            if (frame is null)
            {
                throw new InvalidOperationException("relay closed the transfer socket before start");
            }
            if (frame.Value.MessageType == System.Net.WebSockets.WebSocketMessageType.Binary)
            {
                continue;
            }
            var text = System.Text.Encoding.UTF8.GetString(frame.Value.Data);
            if (text.Contains(RelayProtocol.TransferStartType, StringComparison.Ordinal))
            {
                return;
            }
        }
    }

    public static async Task SendDoneAsync(System.Net.WebSockets.WebSocket socket, bool success, string? code, string? message, CancellationToken ct)
        => await SendControlAsync(socket, new TransferDoneFrame { Success = success, Code = code, Message = message }, ct);

    public static async Task SendControlAsync<T>(System.Net.WebSockets.WebSocket socket, T frame, CancellationToken ct)
        where T : class
    {
        var bytes = JsonSerializer.SerializeToUtf8Bytes(frame, RelayJson.Default);
        await socket.SendAsync(bytes, System.Net.WebSockets.WebSocketMessageType.Text, endOfMessage: true, ct);
    }

    public static async IAsyncEnumerable<byte[]> ReadBinaryFramesAsync(
        System.Net.WebSockets.WebSocket socket, [System.Runtime.CompilerServices.EnumeratorCancellation] CancellationToken ct)
    {
        var buffer = new byte[RelayProtocol.DataChunkSize];
        while (true)
        {
            var frame = await ReadFrameAsync(socket, buffer, ct);
            if (frame is null)
            {
                yield break;
            }
            if (frame.Value.MessageType == System.Net.WebSockets.WebSocketMessageType.Binary)
            {
                yield return frame.Value.Data;
            }
        }
    }

    private static async Task<RelayFrame?> ReadFrameAsync(System.Net.WebSockets.WebSocket socket, CancellationToken ct)
        => await ReadFrameAsync(socket, new byte[RelayProtocol.DataChunkSize], ct);

    private static async Task<RelayFrame?> ReadFrameAsync(System.Net.WebSockets.WebSocket socket, byte[] buffer, CancellationToken ct)
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
            if (result.MessageType == System.Net.WebSockets.WebSocketMessageType.Close)
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
}
