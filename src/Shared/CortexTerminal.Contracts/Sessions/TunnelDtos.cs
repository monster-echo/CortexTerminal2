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
    DateTimeOffset CreatedAtUtc);

public sealed record TunnelListResponse(IReadOnlyList<TunnelDto> Tunnels);
