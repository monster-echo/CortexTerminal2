namespace CortexTerminal.Contracts.Sessions;

public sealed record CreateTunnelRequest(int Port);

/// <summary>Workspace 级创建转发规则。remoteAddress 缺省 127.0.0.1。</summary>
public sealed record WorkspaceCreateTunnelRequest(string? Name, int LocalPort, string? RemoteAddress, int RemotePort);

/// <summary>Workspace 级编辑转发规则。字段为 null 表示不修改；name 传空串表示清除名称。</summary>
public sealed record WorkspaceUpdateTunnelRequest(string? Name, int? LocalPort, string? RemoteAddress, int? RemotePort);

/// <summary>owner 面向 tunnel 视图。Secret 仅在创建响应里返回明文,列表查询时为 null。</summary>
public sealed record TunnelDto(
    string TunnelId,
    string TunnelKey,
    /// <summary>Worker 侧目标端口（remotePort）。旧字段，语义即转发目标端口。</summary>
    int Port,
    string SessionId,
    string WorkerId,
    string Url,
    string? Secret,
    DateTimeOffset ExpiresAtUtc,
    DateTimeOffset CreatedAtUtc,
    /// <summary>创建响应带回：端口当前是否在 worker 上监听。列表查询恒为 true。</summary>
    bool PortOpen = true,
    /// <summary>规则名称（可选）。</summary>
    string? Name = null,
    /// <summary>访问入口端口标识（展示用），创建时默认与 remotePort 相同。</summary>
    int LocalPort = 0,
    /// <summary>Worker 侧目标地址，默认 127.0.0.1。</summary>
    string RemoteAddress = "127.0.0.1",
    /// <summary>归属工作区；session 级快捷隧道为 null。</summary>
    string? WorkspaceId = null,
    /// <summary>创建即运行；workspace 级规则恒为 true，撤销即不存在。</summary>
    bool Running = true);

public sealed record TunnelListResponse(IReadOnlyList<TunnelDto> Tunnels);
