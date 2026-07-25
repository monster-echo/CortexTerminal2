namespace CortexTerminal.Gateway.Membership;

public interface IEntitlementService
{
    Task<Entitlement> GetEntitlementAsync(string userId, CancellationToken ct);
    Task EnforceWorkerQuotaAsync(string userId, CancellationToken ct);
}
