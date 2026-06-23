using CortexTerminal.Gateway.Data;
using Microsoft.EntityFrameworkCore;

namespace CortexTerminal.Gateway.Sessions;

public sealed class UserPreferenceService(IDbContextFactory<AppDbContext> factory)
{
    public const string ScrollbackMaxBytesKey = "scrollback_max_bytes";

    public async Task<int?> GetScrollbackMaxBytesAsync(string userId, CancellationToken cancellationToken)
    {
        await using var db = await factory.CreateDbContextAsync(cancellationToken);
        var pref = await db.UserPreferences
            .FirstOrDefaultAsync(p => p.UserId == userId && p.Key == ScrollbackMaxBytesKey, cancellationToken);
        if (pref is null || !int.TryParse(pref.Value, out var bytes)) return null;
        return bytes;
    }

    public async Task SetScrollbackMaxBytesAsync(string userId, int bytes, CancellationToken cancellationToken)
    {
        await using var db = await factory.CreateDbContextAsync(cancellationToken);
        var pref = await db.UserPreferences
            .FirstOrDefaultAsync(p => p.UserId == userId && p.Key == ScrollbackMaxBytesKey, cancellationToken);
        if (pref is null)
        {
            pref = new UserPreference { UserId = userId, Key = ScrollbackMaxBytesKey };
            db.UserPreferences.Add(pref);
        }
        pref.Value = bytes.ToString();
        pref.UpdatedAtUtc = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(cancellationToken);
    }
}
