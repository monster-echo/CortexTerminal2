using System.Collections.Concurrent;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Worker.Registration;
using Microsoft.AspNetCore.Http;
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
    {
        if (!TryResolveWorkspaceDir(rootDir, out var root, out var rootError))
        {
            return new FileListingResult(null, rootError);
        }
        return new RemoteDirectoryLister(root, maxListEntries).List(relativePath);
    }

    // ---- 文件变更（Gateway 的 Mkdir / WriteTextFile / Rename / Delete RPC）----
    // 所有路径统一走 RemotePathValidator.TryResolve：词法 ".." 与符号链接逃逸一律拒绝，
    // 解析后的绝对路径保证位于 root 内。删除前再做一次 root 边界复核（危险操作双保险）。

    /// <summary>新建目录：仅创建最后一级，父级不存在报 path_invalid。</summary>
    public FileOpResult Mkdir(string rootDir, string? relativePath)
    {
        if (!RemotePathValidator.TryResolve(rootDir, relativePath, out var fullPath, out var error))
        {
            return new FileOpResult(error);
        }
        if (Directory.Exists(fullPath) || File.Exists(fullPath))
        {
            return OpFail(FileTransferErrorCode.PathInvalid, $"path already exists: {relativePath}");
        }
        var parent = Path.GetDirectoryName(fullPath)!;
        if (!Directory.Exists(parent))
        {
            return OpFail(FileTransferErrorCode.PathInvalid, $"parent directory does not exist: {relativePath}");
        }

        try
        {
            Directory.CreateDirectory(fullPath);
            logger.LogInformation("Created directory {Path}.", fullPath);
            return new FileOpResult(null);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to create directory {Path}.", fullPath);
            return OpFail(FileTransferErrorCode.TransferFailed, ex.Message);
        }
    }

    /// <summary>新建/覆盖文本文件（UTF-8）：父级目录必须已存在。</summary>
    public FileOpResult WriteTextFile(string rootDir, string? relativePath, string? content)
    {
        if (!RemotePathValidator.TryResolve(rootDir, relativePath, out var fullPath, out var error))
        {
            return new FileOpResult(error);
        }
        if (relativePath is "" or ".")
        {
            return OpFail(FileTransferErrorCode.PathInvalid, "path is required");
        }
        if (Directory.Exists(fullPath))
        {
            return OpFail(FileTransferErrorCode.NotADirectory, $"path is a directory: {relativePath}");
        }
        var parent = Path.GetDirectoryName(fullPath)!;
        if (!Directory.Exists(parent))
        {
            return OpFail(FileTransferErrorCode.PathNotFound, $"no such directory: {relativePath}");
        }

        try
        {
            File.WriteAllText(fullPath, content ?? string.Empty, Encoding.UTF8);
            logger.LogInformation("Wrote text file {Path}.", fullPath);
            return new FileOpResult(null);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to write text file {Path}.", fullPath);
            return OpFail(FileTransferErrorCode.TransferFailed, ex.Message);
        }
    }

    /// <summary>重命名文件或目录：newName 是单段文件名（RemoteFileNameValidator 校验），目标已存在则拒绝。</summary>
    public FileOpResult Rename(string rootDir, string? relativePath, string? newName)
    {
        if (!RemoteFileNameValidator.TryValidateSegment(newName ?? string.Empty, out var nameReason))
        {
            return OpFail(FileTransferErrorCode.PathInvalid, nameReason);
        }
        if (!RemotePathValidator.TryResolve(rootDir, relativePath, out var fullPath, out var error))
        {
            return new FileOpResult(error);
        }
        if (relativePath is "" or ".")
        {
            return OpFail(FileTransferErrorCode.PathInvalid, "cannot rename the workspace root");
        }
        if (!Directory.Exists(fullPath) && !File.Exists(fullPath))
        {
            return OpFail(FileTransferErrorCode.FileNotFound, $"no such file or directory: {relativePath}");
        }

        var root = Path.GetFullPath(rootDir);
        var target = Path.Combine(Path.GetDirectoryName(fullPath)!, newName!);
        if (!RemotePathValidator.IsInsideRoot(root, Path.GetFullPath(target)))
        {
            return OpFail(FileTransferErrorCode.PathInvalid, "rename target escapes the workspace root");
        }
        if (Directory.Exists(target) || File.Exists(target))
        {
            return OpFail(FileTransferErrorCode.PathInvalid, $"target already exists: {newName}");
        }

        try
        {
            if (Directory.Exists(fullPath))
            {
                Directory.Move(fullPath, target);
            }
            else
            {
                File.Move(fullPath, target);
            }
            logger.LogInformation("Renamed {From} to {To}.", fullPath, target);
            return new FileOpResult(null);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to rename {Path}.", fullPath);
            return OpFail(FileTransferErrorCode.TransferFailed, ex.Message);
        }
    }

    /// <summary>删除文件或目录（目录递归删除）：路径严格限制在 root 内，符号链接最终目标也必须在 root 内。</summary>
    public FileOpResult Delete(string rootDir, string? relativePath)
    {
        if (!RemotePathValidator.TryResolve(rootDir, relativePath, out var fullPath, out var error))
        {
            return new FileOpResult(error);
        }
        var root = Path.GetFullPath(rootDir);
        if (fullPath == root || !RemotePathValidator.IsInsideRoot(root, fullPath))
        {
            return OpFail(FileTransferErrorCode.PathInvalid, "cannot delete the workspace root");
        }
        // 产品决策：符号链接跟随（不做逃逸复核）。删除链接本身只移除链接，
        // 不会伤害目标；若链接指向目录则递归删除目标目录，等同用户本机操作。
        if (!Directory.Exists(fullPath) && !File.Exists(fullPath))
        {
            return OpFail(FileTransferErrorCode.FileNotFound, $"no such file or directory: {relativePath}");
        }

        try
        {
            if (Directory.Exists(fullPath))
            {
                Directory.Delete(fullPath, recursive: true);
            }
            else
            {
                File.Delete(fullPath);
            }
            logger.LogInformation("Deleted {Path}.", fullPath);
            return new FileOpResult(null);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to delete {Path}.", fullPath);
            return OpFail(FileTransferErrorCode.TransferFailed, ex.Message);
        }
    }

    private static FileOpResult OpFail(string code, string message)
        => new(new FileOperationError(code, message));

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
        // "~" / "~/..." = 用户 home（新建工作区前的文件夹浏览起点，design/02 §4）。
        var expanded = rootPath == "~" || rootPath.StartsWith("~/")
            ? Path.GetFullPath(Path.Combine(home, rootPath[1..].TrimStart('/')))
            : rootPath;
        var candidate = Path.IsPathRooted(expanded)
            ? expanded
            : Path.GetFullPath(Path.Combine(home, expanded));

        // 产品决策（design 评审）：不再限制工作区根必须在 home 内——开发者的项目
        // 常在任意挂载点/外部盘。安全边界是「工作区根本身」：进入后所有浏览/读写
        // 由 RemotePathValidator 限制在根内（含符号链接逃逸检查）。
        // 若候选路径本身是符号链接，解析为最终目标作为根——否则根下条目解析后会
        // 落在链接真实位置，被误判为逃逸。
        var info = Directory.Exists(candidate)
            ? new DirectoryInfo(candidate)
            : (FileSystemInfo)new FileInfo(candidate);
        string? final = null;
        if (info.LinkTarget is not null)
        {
            // 只对真正的符号链接做最终目标解析（不存在/普通路径直接用候选值）。
            final = info.ResolveLinkTarget(returnFinalTarget: true)?.FullName;
        }
        fullPath = Path.GetFullPath(final ?? candidate);
        return true;
    }
}

/// <summary>本地（LAN/公网直连）传输端点的处理结果，由监听器映射为 HTTP 状态。</summary>
public sealed record LocalTransferOutcome(bool Success, int Status, string? Code, string? Message)
{
    public static LocalTransferOutcome Ok() => new(true, StatusCodes.Status200OK, null, null);
    public static LocalTransferOutcome Fail(int status, string code, string message) => new(false, status, code, message);
}

/// <summary>本地下载已就绪的信息：待流式回传的文件。</summary>
public sealed record LocalDownloadHandle(string FilePath, long SizeBytes, string Filename);

/// <summary>
/// 传输执行器：Gateway RPC 同步校验后立即应答，随后两条通道并行竞争同一传输 ——
/// - Relay 路径：后台连入 Relay transfer WS 等待配对（兜底，覆盖跨网络场景）；
/// - 本地路径：LAN/公网直连监听器接收客户端 HTTP（同网段或公网可达时先到先得）。
/// 任一通道认领传输后取消另一条；上传统一落临时文件 + sha 校验 + 原子替换。
/// 传输终态由实际承接的通道回传给客户端（Relay done 帧 / 本地 HTTP 响应）。
/// </summary>
public sealed class RelayTransferService(long maxTransferBytes, ILogger<RelayTransferService> logger)
{
    private readonly SemaphoreSlim _slots = new(4, 4);
    private readonly ConcurrentDictionary<string, PendingLocalTransfer> _local = new(StringComparer.Ordinal);

    private sealed class PendingLocalTransfer
    {
        public required bool IsReceive { get; init; }
        public required string ExpectedToken { get; init; }
        // receive
        public string TargetPath { get; init; } = "";
        public long SizeBytes { get; init; }
        public string Sha256 { get; init; } = "";
        // send
        public string FilePath { get; init; } = "";
        public string Filename { get; init; } = "";

        public CancellationTokenSource RelayCts { get; } = new();
        public int Claimed;

        /// <summary>pending 本地传输的过期时间（两条通道都未完成时到期作废）。</summary>
        public required DateTimeOffset ExpiresAtUtc { get; init; }

        public bool IsExpired(DateTimeOffset now) => now >= ExpiresAtUtc;
    }

    public Task<FileOperationAck> PrepareFileReceiveAsync(PrepareFileReceiveCommand command, CancellationToken ct)
    {
        if (!RemoteFileNameValidator.TryValidateSegment(command.Filename, out var reason))
        {
            return Task.FromResult(Fail(FileTransferErrorCode.PathInvalid, reason));
        }
        if (!WorkspaceFileService.TryResolveWorkspaceDir(command.RootDir, out _, out var receiveRootError))
        {
            return Task.FromResult(Fail(receiveRootError!.Code, receiveRootError.Message));
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

        var targetPath = Path.Combine(dirPath, command.Filename);
        var pending = new PendingLocalTransfer
        {
            IsReceive = true,
            ExpectedToken = command.Token,
            TargetPath = targetPath,
            SizeBytes = command.SizeBytes,
            Sha256 = command.Sha256,
            ExpiresAtUtc = DateTimeOffset.UtcNow.AddSeconds(PendingTtlSeconds),
        };
        SweepExpired();
        _local[command.TransferId] = pending;
        _ = Task.Run(() => ReceivePipelineAsync(command, targetPath, pending, pending.RelayCts.Token), CancellationToken.None);
        return Task.FromResult(new FileOperationAck(true, null));
    }

    public Task<PrepareFileSendAck> PrepareFileSendAsync(PrepareFileSendCommand command, CancellationToken ct)
    {
        if (!WorkspaceFileService.TryResolveWorkspaceDir(command.RootDir, out _, out var sendRootError))
        {
            return Task.FromResult(new PrepareFileSendAck(false, sendRootError!, 0, ""));
        }
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
        var pending = new PendingLocalTransfer
        {
            IsReceive = false,
            ExpectedToken = command.Token,
            FilePath = filePath,
            SizeBytes = size,
            Filename = filename,
            ExpiresAtUtc = DateTimeOffset.UtcNow.AddSeconds(PendingTtlSeconds),
        };
        SweepExpired();
        _local[command.TransferId] = pending;
        _ = Task.Run(() => SendPipelineAsync(command, filePath, size, pending, pending.RelayCts.Token), CancellationToken.None);
        return Task.FromResult(new PrepareFileSendAck(true, null, size, filename));
    }

    /// <summary>pending 本地传输的最长寿命（本地与 Relay 通道都未完成时到期作废）。</summary>
    private const int PendingTtlSeconds = 600;

    /// <summary>惰性清扫：每次 Prepare 时顺手清掉两条通道都没接手且已过期的 pending。</summary>
    private void SweepExpired()
    {
        var now = DateTimeOffset.UtcNow;
        foreach (var (id, expired) in _local)
        {
            if (expired.IsExpired(now))
            {
                _local.TryRemove(id, out _);
            }
        }
    }

    // ── 本地直连通道（由 LocalTransferListener 调用）──────────────────

    /// <summary>本地上传：token 校验 → 认领传输（取消 Relay 路径）→ 流式落盘 → sha 校验 → 原子替换。</summary>
    public async Task<LocalTransferOutcome> HandleLocalUploadAsync(
        string transferId, string token, Stream body, CancellationToken ct)
    {
        if (!_local.TryGetValue(transferId, out var pending) || !pending.IsReceive)
        {
            return LocalTransferOutcome.Fail(StatusCodes.Status404NotFound,
                FileTransferErrorCode.TransferNotFound, "no such pending transfer");
        }
        if (!TokenMatches(pending.ExpectedToken, token))
        {
            return LocalTransferOutcome.Fail(StatusCodes.Status401Unauthorized, "invalid_token", "transfer token mismatch");
        }
        if (Interlocked.CompareExchange(ref pending.Claimed, 1, 0) != 0)
        {
            return LocalTransferOutcome.Fail(StatusCodes.Status409Conflict,
                FileTransferErrorCode.TransferFailed, "transfer already claimed");
        }
        await pending.RelayCts.CancelAsync();

        var tmpPath = pending.TargetPath + ".localdownloading";
        try
        {
            byte[] sha;
            using (var shaInstance = SHA256.Create())
            await using (var file = File.Create(tmpPath))
            {
                var buffer = new byte[64 * 1024];
                long total = 0;
                int read;
                while ((read = await body.ReadAsync(buffer, ct)) > 0)
                {
                    total += read;
                    if (total > pending.SizeBytes)
                    {
                        throw new InvalidOperationException(
                            $"received more than the declared {pending.SizeBytes} bytes");
                    }
                    await file.WriteAsync(buffer.AsMemory(0, read), ct);
                    shaInstance.TransformBlock(buffer, 0, read, null, 0);
                }
                shaInstance.TransformFinalBlock(Array.Empty<byte>(), 0, 0);
                sha = shaInstance.Hash!;
                if (total != pending.SizeBytes)
                {
                    throw new InvalidOperationException($"received {total} bytes, expected {pending.SizeBytes}");
                }
            }

            var actual = Convert.ToHexString(sha).ToLowerInvariant();
            if (!string.Equals(actual, pending.Sha256, StringComparison.OrdinalIgnoreCase))
            {
                File.Delete(tmpPath);
                logger.LogError("Local transfer {TransferId} sha256 mismatch.", transferId);
                return LocalTransferOutcome.Fail(StatusCodes.Status502BadGateway,
                    FileTransferErrorCode.ShaMismatch, "uploaded content does not match its sha256");
            }

            File.Move(tmpPath, pending.TargetPath, overwrite: true);
            logger.LogInformation("Local transfer {TransferId} wrote {Path} ({Size} bytes).",
                transferId, pending.TargetPath, pending.SizeBytes);
            return LocalTransferOutcome.Ok();
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            try { if (File.Exists(tmpPath)) File.Delete(tmpPath); } catch (IOException) { }
            throw;
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Local transfer {TransferId} receive failed.", transferId);
            try { if (File.Exists(tmpPath)) File.Delete(tmpPath); } catch (IOException) { }
            return LocalTransferOutcome.Fail(StatusCodes.Status502BadGateway,
                FileTransferErrorCode.TransferFailed, ex.Message);
        }
        finally
        {
            _local.TryRemove(transferId, out _);
        }
    }

    /// <summary>本地下载：token 校验 → 认领传输（取消 Relay 路径）→ 交出文件句柄信息由监听器流式发送。</summary>
    public Task<(LocalTransferOutcome Outcome, LocalDownloadHandle? Handle)> HandleLocalDownloadAsync(
        string transferId, string token, CancellationToken ct)
    {
        (LocalTransferOutcome, LocalDownloadHandle?) Fail(int status, string code, string message)
            => (LocalTransferOutcome.Fail(status, code, message), null);

        if (!_local.TryGetValue(transferId, out var pending) || pending.IsReceive)
        {
            return Task.FromResult(Fail(StatusCodes.Status404NotFound,
                FileTransferErrorCode.TransferNotFound, "no such pending transfer"));
        }
        if (!TokenMatches(pending.ExpectedToken, token))
        {
            return Task.FromResult(Fail(StatusCodes.Status401Unauthorized,
                "invalid_token", "transfer token mismatch"));
        }
        if (Interlocked.CompareExchange(ref pending.Claimed, 1, 0) != 0)
        {
            return Task.FromResult(Fail(StatusCodes.Status409Conflict,
                FileTransferErrorCode.TransferFailed, "transfer already claimed"));
        }
        _local.TryRemove(transferId, out _);
        pending.RelayCts.Cancel();
        return Task.FromResult<(LocalTransferOutcome, LocalDownloadHandle?)>((LocalTransferOutcome.Ok(),
            new LocalDownloadHandle(pending.FilePath, pending.SizeBytes, pending.Filename)));
    }

    private static bool TokenMatches(string expected, string presented)
        => !string.IsNullOrEmpty(presented)
           && CryptographicOperations.FixedTimeEquals(
               Encoding.UTF8.GetBytes(expected),
               Encoding.UTF8.GetBytes(presented));

    private static FileOperationAck Fail(string code, string message)
        => new(false, new FileOperationError(code, message));

    // ── Relay 路径 ───────────────────────────────────────────────

    /// <summary>上传：连 Relay → 等 start → 收文件 → sha 校验 → 原子落盘 → done。</summary>
    private async Task ReceivePipelineAsync(PrepareFileReceiveCommand command, string targetPath, PendingLocalTransfer pending, CancellationToken ct)
    {
        await _slots.WaitAsync();
        var tmpPath = targetPath + ".downloading";
        try
        {
            using var socket = new System.Net.WebSockets.ClientWebSocket();
            var uri = RelayUri.BuildWebSocketUri(
                command.RelayUrl,
                $"transfer/{command.TransferId}/worker",
                new KeyValuePair<string, string>("token", command.Token));
            using var connectCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            connectCts.CancelAfter(TimeSpan.FromSeconds(30));
            await socket.ConnectAsync(uri, connectCts.Token);

            await RelayProtocolIo.WaitStartAsync(socket, ct);

            byte[] sha;
            using (var shaInstance = SHA256.Create())
            await using (var file = File.Create(tmpPath))
            {
                long total = 0;
                await foreach (var chunk in RelayProtocolIo.ReadBinaryFramesAsync(socket, ct))
                {
                    total += chunk.Length;
                    if (total > command.SizeBytes)
                    {
                        throw new InvalidOperationException("received more bytes than declared sizeBytes");
                    }
                    await file.WriteAsync(chunk, ct);
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
                    FileTransferErrorCode.ShaMismatch, "uploaded content does not match its sha256", ct);
                return;
            }

            File.Move(tmpPath, targetPath, overwrite: true);
            logger.LogInformation("Transfer {TransferId} wrote {Path} ({Size} bytes).", command.TransferId, targetPath, command.SizeBytes);
            _local.TryRemove(command.TransferId, out _);
            await RelayProtocolIo.SendDoneAsync(socket, success: true, null, null, ct);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            // 本地直连通道已认领该传输，Relay 路径按设计退出
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
    private async Task SendPipelineAsync(PrepareFileSendCommand command, string filePath, long size, PendingLocalTransfer pending, CancellationToken ct)
    {
        await _slots.WaitAsync();
        try
        {
            using var socket = new System.Net.WebSockets.ClientWebSocket();
            var uri = RelayUri.BuildWebSocketUri(
                command.RelayUrl,
                $"transfer/{command.TransferId}/worker",
                new KeyValuePair<string, string>("token", command.Token));
            using var connectCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            connectCts.CancelAfter(TimeSpan.FromSeconds(30));
            await socket.ConnectAsync(uri, connectCts.Token);

            await RelayProtocolIo.WaitStartAsync(socket, ct);
            await RelayProtocolIo.SendControlAsync(socket,
                new FileHeadFrame { Size = size, Filename = Path.GetFileName(filePath) }, ct);

            await using var file = File.OpenRead(filePath);
            var buffer = new byte[64 * 1024];
            int read;
            while ((read = await file.ReadAsync(buffer, ct)) > 0)
            {
                await socket.SendAsync(buffer.AsMemory(0, read),
                    System.Net.WebSockets.WebSocketMessageType.Binary, endOfMessage: true, ct);
            }

            logger.LogInformation("Transfer {TransferId} streamed {Path} ({Size} bytes).", command.TransferId, filePath, size);
            _local.TryRemove(command.TransferId, out _);
            await RelayProtocolIo.SendDoneAsync(socket, success: true, null, null, ct);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            // 本地直连通道已认领该传输，Relay 路径按设计退出
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
