using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace CortexTerminal.Gateway.Migrations
{
    /// <inheritdoc />
    /// <summary>
    /// Fixes the earlier BackfillPasswordIdentities migration which was INSERT-only
    /// and therefore no-op'd for users that already had a password UserIdentity row
    /// (seeded by AddUserIdentities on 2026-06-12). Those rows kept password_hash = NULL
    /// and the Phase 1 login path failed for every legacy password user.
    ///
    /// This migration UPDATEs the existing rows from Users.password_hash. Idempotent —
    /// only touches rows whose password_hash is NULL or empty.
    /// </summary>
    public partial class BackfillExistingPasswordIdentities : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
UPDATE ""UserIdentities"" ui
SET password_hash = u.""password_hash""
FROM ""Users"" u
WHERE ui.""user_id"" = u.""id""
  AND ui.""auth_provider"" = 'password'
  AND u.""password_hash"" IS NOT NULL
  AND u.""password_hash"" <> ''
  AND (ui.""password_hash"" IS NULL OR ui.""password_hash"" = '');
");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            // Best-effort reversal: null out the password_hash values that this
            // migration could have written. The pre-Phase-1 Users.password_hash
            // column is untouched, so logins fall back to it if this is rolled back.
            migrationBuilder.Sql(@"
UPDATE ""UserIdentities"" ui
SET password_hash = NULL
FROM ""Users"" u
WHERE ui.""user_id"" = u.""id""
  AND ui.""auth_provider"" = 'password'
  AND u.""password_hash"" IS NOT NULL
  AND u.""password_hash"" <> '';
");
        }
    }
}
