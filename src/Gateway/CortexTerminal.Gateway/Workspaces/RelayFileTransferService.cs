using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Gateway.Sessions;
using CortexTerminal.Gateway.Workers;
using Microsoft.Extensions.Options;

namespace CortexTerminal.Gateway.Workspaces;

/// <summary>工作区文件操作失败，code 为 <see cref="FileTransferErrorCode"/> 之一，由 REST 端点映射 HTTP 状态。</summary>
public sealed class WorkspaceFileServiceException(string code, string message) : Exception(message)
{
    public string Code { get; } = code;
}

/// <summary>
/// 工作区文件的编排器：列目录走 Worker RPC；上传/下载由 Gateway 签发短命 Relay 令牌并通知
/// Worker 连入 Relay transfer WS，字节随后在「客户端 HTTP ⇄ Relay ⇄ Worker WS」间流式对拷，
/// Gateway 与 Relay 均不落盘。
/// </summary>
public sealed class RelayFileTransferService(
    IWorkerRegistry workers,
    IWorkerCommandDispatcher workerCommands,
    WorkspaceRegistry workspaceRegistry,
    IOptions<RelayOptions> options)
{
    private readonly RelayOptions _options = options.Value;

    /// <summary>新建目录（仅最后一级；父级缺失由 Worker 报 path_invalid）。</summary>
    public Task MkdirAsync(string userId, string workspaceId, string? path, CancellationToken ct)
        => InvokeFileOpAsync(userId, workspaceId, path,
            (worker, ws, token) => workerCommands.MkdirAsync(worker.ConnectionId, ws.RootPath, path!, token), ct);

    /// <summary>新建/覆盖文本文件（UTF-8；父级目录必须已存在）。</summary>
    public Task WriteTextAsync(string userId, string workspaceId, string? path, string? content, CancellationToken ct)
        => InvokeFileOpAsync(userId, workspaceId, path,
            (worker, ws, token) => workerCommands.WriteTextFileAsync(
                worker.ConnectionId, ws.RootPath, path!, content ?? string.Empty, token), ct);

    /// <summary>重命名文件或目录（newName 是单段文件名，Worker 端用 RemoteFileNameValidator 校验）。</summary>
    public Task RenameAsync(string userId, string workspaceId, string? path, string? newName, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(newName))
        {
            throw new WorkspaceFileServiceException(FileTransferErrorCode.PathInvalid, "newName is required");
        }
        return InvokeFileOpAsync(userId, workspaceId, path,
            (worker, ws, token) => workerCommands.RenameAsync(worker.ConnectionId, ws.RootPath, path!, newName, token), ct);
    }

    /// <summary>删除文件或目录（目录由 Worker 递归删除，路径严格限制在 root 内）。</summary>
    public Task DeleteAsync(string userId, string workspaceId, string? path, CancellationToken ct)
        => InvokeFileOpAsync(userId, workspaceId, path,
            (worker, ws, token) => workerCommands.DeleteAsync(worker.ConnectionId, ws.RootPath, path!, token), ct);

    /// <summary>
    /// 文件变更类 RPC 的共用编排：path 非空校验 → 工作区归属 + Worker 在线 → 15s 超时 →
    /// 把 FileOpResult 的结构化错误翻成 <see cref="WorkspaceFileServiceException"/>，RPC 通道异常翻成 worker_offline。
    /// </summary>
    private async Task InvokeFileOpAsync(
        string userId,
        string workspaceId,
        string? path,
        Func<RegisteredWorker, Data.WorkspaceEntity, CancellationToken, Task<FileOpResult>> invoke,
        CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            throw new WorkspaceFileServiceException(FileTransferErrorCode.PathInvalid, "path is required");
        }

        var workspace = await OwnedWorkspaceAsync(userId, workspaceId);
        var worker = OnlineWorkerOrThrow(workspace.WorkerId);

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeout.CancelAfter(TimeSpan.FromSeconds(15));
        FileOpResult result;
        try
        {
            result = await invoke(worker, workspace, timeout.Token);
        }
        catch (Exception ex)
        {
            throw new WorkspaceFileServiceException(FileTransferErrorCode.WorkerOffline,
                "worker did not complete the operation: " + ex.Message);
        }
        if (result.Error is not null)
        {
            throw new WorkspaceFileServiceException(result.Error.Code, result.Error.Message);
        }
    }

    public async Task<FileListing> ListAsync(string userId, string workspaceId, string? path, CancellationToken ct)
    {
        var workspace = await OwnedWorkspaceAsync(userId, workspaceId);
        var worker = OnlineWorkerOrThrow(workspace.WorkerId);

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeout.CancelAfter(TimeSpan.FromSeconds(15));
        var result = await workerCommands.ListFilesAsync(
            worker.ConnectionId, workspace.RootPath, path ?? string.Empty, timeout.Token);
        if (result.Error is not null)
        {
            throw new WorkspaceFileServiceException(result.Error.Code, result.Error.Message);
        }
        return result.Listing ?? throw new WorkspaceFileServiceException(
            FileTransferErrorCode.TransferFailed, "worker returned an empty listing result");
    }

    /// <summary>
    /// 上传第一步：登记传输（通知 Worker 连入 Relay 等待配对），返回客户端可用的端点列表。
    /// 客户端随后 PUT 文件字节到第一个可达端点，PUT 响应即终态，无 complete 调用。
    /// </summary>
    public async Task<UploadInitResult> CreateUploadAsync(
        string userId, string workspaceId, string dirPath, string filename, long sizeBytes, string sha256, CancellationToken ct)
    {
        if (!RemoteFileNameValidator.TryValidateSegment(filename, out var reason))
        {
            throw new WorkspaceFileServiceException(FileTransferErrorCode.PathInvalid, reason);
        }
        if (sizeBytes <= 0)
        {
            throw new WorkspaceFileServiceException(FileTransferErrorCode.PathInvalid, "sizeBytes must be positive");
        }

        var workspace = await OwnedWorkspaceAsync(userId, workspaceId);
        var worker = OnlineWorkerOrThrow(workspace.WorkerId);

        var transferId = Guid.NewGuid().ToString("N");
        var token = RelayToken.Mint(
            _options.SharedSecret, RelayToken.AudienceTransfer, transferId, DateTimeOffset.UtcNow.AddSeconds(_options.TransferTtlSeconds));
        var command = new PrepareFileReceiveCommand(
            transferId, workspace.RootPath, dirPath ?? string.Empty, filename, sizeBytes, sha256, _options.PublicUrl, token);

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeout.CancelAfter(TimeSpan.FromSeconds(20));
        FileOperationAck ack;
        try
        {
            ack = await workerCommands.PrepareFileReceiveAsync(worker.ConnectionId, command, timeout.Token);
        }
        catch (Exception ex)
        {
            throw new WorkspaceFileServiceException(FileTransferErrorCode.WorkerOffline,
                "worker did not accept the transfer: " + ex.Message);
        }
        if (!ack.Success)
        {
            var error = ack.Error ?? new FileOperationError(FileTransferErrorCode.TransferFailed, "worker rejected the upload");
            throw new WorkspaceFileServiceException(error.Code, error.Message);
        }

        return new UploadInitResult(transferId, EndpointsFor(worker, transferId, token));
    }

    /// <summary>
    /// 下载第一步：同步让 Worker 校验文件并连入 Relay 等待配对，返回端点列表。
    /// 客户端随后 GET 第一个可达端点拿文件字节。
    /// </summary>
    public async Task<DownloadInitResult> StartDownloadAsync(
        string userId, string workspaceId, string path, CancellationToken ct)
    {
        var workspace = await OwnedWorkspaceAsync(userId, workspaceId);
        var worker = OnlineWorkerOrThrow(workspace.WorkerId);

        var transferId = Guid.NewGuid().ToString("N");
        var token = RelayToken.Mint(
            _options.SharedSecret, RelayToken.AudienceTransfer, transferId, DateTimeOffset.UtcNow.AddSeconds(_options.TransferTtlSeconds));
        var command = new PrepareFileSendCommand(transferId, workspace.RootPath, path, _options.PublicUrl, token);

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeout.CancelAfter(TimeSpan.FromSeconds(20));
        PrepareFileSendAck ack;
        try
        {
            ack = await workerCommands.PrepareFileSendAsync(worker.ConnectionId, command, timeout.Token);
        }
        catch (Exception ex)
        {
            throw new WorkspaceFileServiceException(FileTransferErrorCode.WorkerOffline,
                "worker did not accept the transfer: " + ex.Message);
        }
        if (!ack.Success)
        {
            var error = ack.Error ?? new FileOperationError(FileTransferErrorCode.TransferFailed, "worker rejected the download");
            throw new WorkspaceFileServiceException(error.Code, error.Message);
        }

        return new DownloadInitResult(transferId, ack.SizeBytes, ack.Filename, EndpointsFor(worker, transferId, token));
    }

    /// <summary>
    /// 终端文件浏览：根目录由客户端给出（shell OSC 7 上报的实时 cwd，或工作区绝对路径），
    /// Worker 侧负责把根限制在用户 home 内。鉴权只看 worker 归属。
    /// </summary>
    public async Task<FileListing> ListForWorkerAsync(
        string userId, string workerId, string rootPath, string? path, CancellationToken ct)
    {
        var worker = OwnedOnlineWorkerOrThrow(userId, workerId);

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeout.CancelAfter(TimeSpan.FromSeconds(15));
        var result = await workerCommands.ListFilesAsync(
            worker.ConnectionId, rootPath, path ?? string.Empty, timeout.Token);
        if (result.Error is not null)
        {
            throw new WorkspaceFileServiceException(result.Error.Code, result.Error.Message);
        }
        return result.Listing ?? throw new WorkspaceFileServiceException(
            FileTransferErrorCode.TransferFailed, "worker returned an empty listing result");
    }

    public async Task<UploadInitResult> CreateUploadForWorkerAsync(
        string userId, string workerId, string rootPath, string dirPath, string filename, long sizeBytes, string sha256, CancellationToken ct)
    {
        if (!RemoteFileNameValidator.TryValidateSegment(filename, out var reason))
        {
            throw new WorkspaceFileServiceException(FileTransferErrorCode.PathInvalid, reason);
        }
        if (sizeBytes <= 0)
        {
            throw new WorkspaceFileServiceException(FileTransferErrorCode.PathInvalid, "sizeBytes must be positive");
        }

        var worker = OwnedOnlineWorkerOrThrow(userId, workerId);

        var transferId = Guid.NewGuid().ToString("N");
        var token = RelayToken.Mint(
            _options.SharedSecret, RelayToken.AudienceTransfer, transferId, DateTimeOffset.UtcNow.AddSeconds(_options.TransferTtlSeconds));
        var command = new PrepareFileReceiveCommand(
            transferId, rootPath, dirPath ?? string.Empty, filename, sizeBytes, sha256, _options.PublicUrl, token);

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeout.CancelAfter(TimeSpan.FromSeconds(20));
        FileOperationAck ack;
        try
        {
            ack = await workerCommands.PrepareFileReceiveAsync(worker.ConnectionId, command, timeout.Token);
        }
        catch (Exception ex)
        {
            throw new WorkspaceFileServiceException(FileTransferErrorCode.WorkerOffline,
                "worker did not accept the transfer: " + ex.Message);
        }
        if (!ack.Success)
        {
            var error = ack.Error ?? new FileOperationError(FileTransferErrorCode.TransferFailed, "worker rejected the upload");
            throw new WorkspaceFileServiceException(error.Code, error.Message);
        }

        return new UploadInitResult(transferId, EndpointsFor(worker, transferId, token));
    }

    public async Task<DownloadInitResult> StartDownloadForWorkerAsync(
        string userId, string workerId, string rootPath, string path, CancellationToken ct)
    {
        var worker = OwnedOnlineWorkerOrThrow(userId, workerId);

        var transferId = Guid.NewGuid().ToString("N");
        var token = RelayToken.Mint(
            _options.SharedSecret, RelayToken.AudienceTransfer, transferId, DateTimeOffset.UtcNow.AddSeconds(_options.TransferTtlSeconds));
        var command = new PrepareFileSendCommand(transferId, rootPath, path, _options.PublicUrl, token);

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeout.CancelAfter(TimeSpan.FromSeconds(20));
        PrepareFileSendAck ack;
        try
        {
            ack = await workerCommands.PrepareFileSendAsync(worker.ConnectionId, command, timeout.Token);
        }
        catch (Exception ex)
        {
            throw new WorkspaceFileServiceException(FileTransferErrorCode.WorkerOffline,
                "worker did not accept the transfer: " + ex.Message);
        }
        if (!ack.Success)
        {
            var error = ack.Error ?? new FileOperationError(FileTransferErrorCode.TransferFailed, "worker rejected the download");
            throw new WorkspaceFileServiceException(error.Code, error.Message);
        }

        return new DownloadInitResult(transferId, ack.SizeBytes, ack.Filename, EndpointsFor(worker, transferId, token));
    }

    /// <summary>worker 归属校验 + 在线校验（worker-scoped 文件操作共用）。</summary>
    private RegisteredWorker OwnedOnlineWorkerOrThrow(string userId, string workerId)
    {
        if (!workers.TryGetWorker(workerId, out var worker)
            || (worker.OwnerUserId is not null && worker.OwnerUserId != userId))
        {
            throw new WorkspaceFileServiceException(FileTransferErrorCode.PathNotFound, "Worker not found");
        }
        return OnlineWorkerOrThrow(workerId);
    }

    /// <summary>
    /// 端点协商（P2P 优先，按可达概率排序）：同网段 LAN 直连 → 公网直连 → Relay 兜底。
    /// 客户端按顺序尝试，全部失败视为传输失败。
    /// </summary>
    private List<TransferEndpoint> EndpointsFor(RegisteredWorker worker, string transferId, string token)
    {
        var endpoints = new List<TransferEndpoint>();
        var lan = worker.LanEndpoints ?? Array.Empty<string>();
        foreach (var baseUrl in lan)
        {
            if (string.IsNullOrWhiteSpace(baseUrl)) continue;
            endpoints.Add(new TransferEndpoint(
                $"{baseUrl.TrimEnd('/')}/transfer/{transferId}?token={Uri.EscapeDataString(token)}", TransferEndpoint.KindLan));
        }
        if (!string.IsNullOrWhiteSpace(worker.PublicTransferBaseUrl))
        {
            endpoints.Add(new TransferEndpoint(
                $"{worker.PublicTransferBaseUrl.TrimEnd('/')}/transfer/{transferId}?token={Uri.EscapeDataString(token)}", TransferEndpoint.KindPublic));
        }
        endpoints.Add(new TransferEndpoint(
            $"{_options.PublicUrl.TrimEnd('/')}/transfer/{transferId}?token={Uri.EscapeDataString(token)}", TransferEndpoint.KindRelay));
        return endpoints;
    }

    private async Task<Data.WorkspaceEntity> OwnedWorkspaceAsync(string userId, string workspaceId)
    {
        try
        {
            return await workspaceRegistry.GetOwnedAsync(userId, workspaceId);
        }
        catch (WorkspaceNotFoundException)
        {
            throw new WorkspaceFileServiceException(FileTransferErrorCode.PathNotFound, "Workspace not found");
        }
        catch (WorkspaceForbiddenException)
        {
            throw new UnauthorizedAccessException("Workspace belongs to another user");
        }
    }

    private RegisteredWorker OnlineWorkerOrThrow(string workerId)
    {
        if (!workers.TryGetWorker(workerId, out var worker) || string.IsNullOrEmpty(worker.ConnectionId))
        {
            throw new WorkspaceFileServiceException(FileTransferErrorCode.WorkerOffline, "Worker is offline");
        }
        return worker;
    }
}
