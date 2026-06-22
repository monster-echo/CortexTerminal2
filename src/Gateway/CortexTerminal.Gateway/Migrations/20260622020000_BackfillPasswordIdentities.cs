using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace CortexTerminal.Gateway.Migrations
{
    /// <inheritdoc />
    /// <summary>
    /// Backfill UserIdentity(provider='password') rows from legacy Users.PasswordHash
    /// so that Phase 1 login path can find every existing credential without falling
    /// back to the Users column. Idempotent — skips users that already have a password
    /// identity (e.g. created after Phase 1).
    /// </summary>
    public partial class BackfillPasswordIdentities : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // PostgreSQL only. The in-memory dev provider never hits this path.
            migrationBuilder.Sql(@"
INSERT INTO ""UserIdentities"" (""id"", ""user_id"", ""auth_provider"", ""auth_provider_id"", ""password_hash"", ""created_at_utc"")
SELECT
    regexp_replace(gen_random_uuid()::text, '-', '', 'g'),
    u.""id"",
    'password',
    u.""username"",
    u.""password_hash"",
    NOW() AT TIME ZONE 'UTC'
FROM ""Users"" u
WHERE u.""password_hash"" IS NOT NULL
  AND u.""password_hash"" <> ''
  AND NOT EXISTS (
    SELECT 1 FROM ""UserIdentities"" ui
    WHERE ui.""user_id"" = u.""id""
      AND ui.""auth_provider"" = 'password'
  );
");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            // Remove only the backfilled rows: password identities whose AuthProviderId
            // collides with a Users.Username (i.e. the backfill signature). User-created
            // password identities registered through the Phase 1 register endpoint have
            // the same shape, so this Down is best-effort — the safety net is the Users
            // table, which is not touched here.
            migrationBuilder.Sql(@"
DELETE FROM ""UserIdentities"" ui
WHERE ui.""auth_provider"" = 'password'
  AND EXISTS (
    SELECT 1 FROM ""Users"" u WHERE u.""username"" = ui.""auth_provider_id""
  );
");
        }
    }
}
