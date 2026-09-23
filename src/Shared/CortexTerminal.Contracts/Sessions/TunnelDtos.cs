namespace CortexTerminal.Contracts.Sessions;

public sealed record CreateTunnelRequest(int Port);

/// <summary>owner 面向 tunnel 视图。Secret 仅在创建响应里返回明文,列表查询时为 null。</summary>
public sealed record TunnelDto(
    string TunnelId,
    string TunnelKey,
    int Port,
    string SessionId,
    string WorkerId,
    string Url,
    string? Secret,
    DateTimeOffset ExpiresAtUtc,
    DateTimeOffset CreatedAtUtc,
    /// <summary>创建响应带回：端口当前是否在 worker 上监听。列表查询恒为 true。</summary>
    bool PortOpen = true);

public sealed record TunnelListResponse(IReadOnlyList<TunnelDto> Tunnels);
