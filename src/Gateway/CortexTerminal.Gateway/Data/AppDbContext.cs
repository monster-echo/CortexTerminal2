using Microsoft.EntityFrameworkCore;

namespace CortexTerminal.Gateway.Data;

public class AppDbContext : DbContext
{
    public DbSet<User> Users => Set<User>();
    public DbSet<AuditLog> AuditLogs => Set<AuditLog>();
    public DbSet<WorkerRecord> Workers => Set<WorkerRecord>();
    public DbSet<SessionRecordEntity> Sessions => Set<SessionRecordEntity>();

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

        modelBuilder.Entity<SessionRecordEntity>(entity =>
        {
            entity.HasIndex(e => e.UserId);
            entity.HasIndex(e => e.WorkerId);
            entity.HasIndex(e => e.AttachmentState);
            entity.HasIndex(e => e.CreatedAtUtc);
        });
    }
}
