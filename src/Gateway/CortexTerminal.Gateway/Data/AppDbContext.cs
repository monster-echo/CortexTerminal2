using Microsoft.EntityFrameworkCore;

namespace CortexTerminal.Gateway.Data;

public class AppDbContext : DbContext
{
    public DbSet<User> Users => Set<User>();
    public DbSet<UserIdentity> UserIdentities => Set<UserIdentity>();
    public DbSet<AuditLog> AuditLogs => Set<AuditLog>();
    public DbSet<WorkerRecord> Workers => Set<WorkerRecord>();
    public DbSet<SessionRecordEntity> Sessions => Set<SessionRecordEntity>();
    public DbSet<UserPreference> UserPreferences => Set<UserPreference>();
    public DbSet<TunnelEntity> Tunnels => Set<TunnelEntity>();
    public DbSet<SessionAgentEventEntity> SessionAgentEvents => Set<SessionAgentEventEntity>();
    public DbSet<WorkspaceEntity> Workspaces => Set<WorkspaceEntity>();
    public DbSet<Plan> Plans => Set<Plan>();
    public DbSet<Subscription> Subscriptions => Set<Subscription>();
    public DbSet<MembershipOrder> MembershipOrders => Set<MembershipOrder>();
    public DbSet<RedeemCode> RedeemCodes => Set<RedeemCode>();
    public DbSet<RedeemCodeUsage> RedeemCodeUsages => Set<RedeemCodeUsage>();
    public DbSet<IapWebhookEvent> IapWebhookEvents => Set<IapWebhookEvent>();

    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<User>(entity =>
        {
            entity.HasIndex(e => e.Username).IsUnique();
            entity.HasIndex(e => new { e.AuthProvider, e.AuthProviderId });
        });

        modelBuilder.Entity<AuditLog>(entity =>
        {
            entity.HasIndex(e => e.Timestamp);
            entity.HasIndex(e => e.UserId);
            entity.HasIndex(e => e.Action);
        });

        modelBuilder.Entity<WorkerRecord>(entity =>
        {
            entity.HasIndex(e => e.OwnerUserId);
            entity.HasIndex(e => e.IsOnline);
        });

        modelBuilder.Entity<UserIdentity>(entity =>
        {
            entity.HasIndex(e => e.UserId);
            entity.HasIndex(e => new { e.AuthProvider, e.AuthProviderId }).IsUnique();
            entity.HasIndex(e => e.PhoneNormalized);
            entity.HasIndex(e => e.Email);
        });

        modelBuilder.Entity<SessionRecordEntity>(entity =>
        {
            entity.HasIndex(e => e.UserId);
            entity.HasIndex(e => e.WorkerId);
            entity.HasIndex(e => e.AttachmentState);
            entity.HasIndex(e => e.CreatedAtUtc);
        });

        modelBuilder.Entity<UserPreference>(entity =>
        {
            entity.HasIndex(e => new { e.UserId, e.Key }).IsUnique();
            entity.HasIndex(e => e.UserId);
        });

        modelBuilder.Entity<TunnelEntity>(entity =>
        {
            entity.HasIndex(e => e.TunnelKey).IsUnique();
            entity.HasIndex(e => e.OwnerUserId);
            entity.HasIndex(e => e.SessionId);
            entity.HasIndex(e => e.ExpiresAtUtc);
        });

        modelBuilder.Entity<SessionAgentEventEntity>(entity =>
        {
            entity.HasIndex(e => new { e.SessionId, e.CreatedAtUtc });
            entity.HasIndex(e => e.SessionId);
        });

        modelBuilder.Entity<WorkspaceEntity>(entity =>
        {
            entity.HasIndex(e => e.OwnerUserId);
            entity.HasIndex(e => e.WorkerId);
            entity.HasIndex(e => new { e.WorkerId, e.Name }).IsUnique();
        });

        modelBuilder.Entity<Plan>(entity =>
        {
            entity.HasIndex(e => e.Code).IsUnique();
        });
        modelBuilder.Entity<Subscription>(entity =>
        {
            entity.HasIndex(e => new { e.UserId, e.Status });
            entity.HasIndex(e => new { e.Source, e.PlatformTransactionId });
        });
        modelBuilder.Entity<MembershipOrder>(entity =>
        {
            entity.HasIndex(e => e.UserId);
        });
        modelBuilder.Entity<RedeemCode>(entity =>
        {
            entity.HasIndex(e => e.Code).IsUnique();
            entity.HasIndex(e => e.BatchId);
        });
        modelBuilder.Entity<RedeemCodeUsage>(entity =>
        {
            entity.HasIndex(e => new { e.RedeemCodeId, e.UserId }).IsUnique();
        });
        modelBuilder.Entity<IapWebhookEvent>(entity =>
        {
            entity.HasIndex(e => new { e.Platform, e.ExternalEventId }).IsUnique();
        });
    }
}
