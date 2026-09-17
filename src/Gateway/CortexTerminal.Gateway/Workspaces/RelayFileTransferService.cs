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

        return new UploadInitResult(transferId, EndpointsFor(transferId, token));
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

        return new DownloadInitResult(transferId, ack.SizeBytes, ack.Filename, EndpointsFor(transferId, token));
    }

    private List<TransferEndpoint> EndpointsFor(string transferId, string token)
    {
        // 端点协商（P2P 优先）：LAN/公网直连端点在 Worker 上报后加入列表头部，
        // Relay 端点始终兜底。当前阶段仅 Relay。
        var endpoints = new List<TransferEndpoint>
        {
            new($"{_options.PublicUrl.TrimEnd('/')}/transfer/{transferId}?token={Uri.EscapeDataString(token)}", TransferEndpoint.KindRelay),
        };
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
