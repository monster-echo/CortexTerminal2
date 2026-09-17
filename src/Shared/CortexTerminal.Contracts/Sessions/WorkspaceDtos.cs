using MessagePack;

namespace CortexTerminal.Contracts.Sessions;

/// <summary>A workspace: a named root directory on a Worker that sessions run in and the file manager browses.</summary>
[MessagePackObject]
public sealed record WorkspaceInfo(
    [property: Key(0)] string Id,
    [property: Key(1)] string WorkerId,
    [property: Key(2)] string Name,
    [property: Key(3)] string RootPath,
    [property: Key(4)] DateTimeOffset CreatedAtUtc);

/// <summary>REST body for creating a workspace on a Worker. RootPath may be absolute or relative to the Worker home.</summary>
[MessagePackObject]
public sealed record CreateWorkspaceRequest(
    [property: Key(0)] string WorkerId,
    [property: Key(1)] string Name,
    [property: Key(2)] string RootPath);

/// <summary>
/// Gateway→Worker RPC: create the workspace directory (mkdir -p) and return the resolved
/// absolute path. The Worker enforces that the path is inside the user home unless absolute,
/// and never resolves above the home root via "..".
/// </summary>
[MessagePackObject]
public sealed record CreateWorkspaceDirectoryCommand(
    [property: Key(0)] string WorkspaceId,
    [property: Key(1)] string RootPath);

/// <summary>
/// Gateway→Worker RPC: prepare to receive a phone upload. The Worker connects to the Relay
/// transfer WebSocket for <see cref="TransferId"/>, waits for the start frame, streams the
/// body into a temp file, verifies the sha256, and atomically moves it to RootDir/DirPath/Filename.
/// </summary>
[MessagePackObject]
public sealed record PrepareFileReceiveCommand(
    [property: Key(0)] string TransferId,
    [property: Key(1)] string RootDir,
    [property: Key(2)] string DirPath,
    [property: Key(3)] string Filename,
    [property: Key(4)] long SizeBytes,
    [property: Key(5)] string Sha256,
    [property: Key(6)] string RelayUrl,
    [property: Key(7)] string Token);

/// <summary>
/// Gateway→Worker RPC: prepare to stream a workspace file to the phone. The Worker validates
/// the file synchronously, then connects to the Relay transfer WebSocket for
/// <see cref="TransferId"/> and streams the file once the start frame arrives.
/// </summary>
[MessagePackObject]
public sealed record PrepareFileSendCommand(
    [property: Key(0)] string TransferId,
    [property: Key(1)] string RootDir,
    [property: Key(2)] string RelativePath,
    [property: Key(3)] string RelayUrl,
    [property: Key(4)] string Token);

/// <summary>Worker 对 CreateWorkspaceDirectory 的应答：mkdir -p 后回传解析出的绝对路径。</summary>
[MessagePackObject]
public sealed record WorkspaceDirectoryAck(
    [property: Key(0)] bool Success,
    [property: Key(1)] FileOperationError? Error,
    [property: Key(2)] string ResolvedPath);

/// <summary>Worker 对 PrepareFileSend 的应答：同步校验结果 + 文件元信息（供 Relay 设定 Content-Length）。</summary>
[MessagePackObject]
public sealed record PrepareFileSendAck(
    [property: Key(0)] bool Success,
    [property: Key(1)] FileOperationError? Error,
    [property: Key(2)] long SizeBytes,
    [property: Key(3)] string Filename);

/// <summary>One candidate endpoint a client can transfer bytes against, in preference order.</summary>
public sealed record TransferEndpoint(string Url, string Kind)
{
    public const string KindLan = "lan";
    public const string KindPublic = "public";
    public const string KindRelay = "relay";
}

/// <summary>REST response: upload init — the client PUTs file bytes to the first reachable endpoint.</summary>
public sealed record UploadInitResult(string TransferId, IReadOnlyList<TransferEndpoint> Endpoints);

/// <summary>REST response: download init — the client GETs file bytes from the first reachable endpoint.</summary>
public sealed record DownloadInitResult(
    string TransferId,
    long SizeBytes,
    string Filename,
    IReadOnlyList<TransferEndpoint> Endpoints);
