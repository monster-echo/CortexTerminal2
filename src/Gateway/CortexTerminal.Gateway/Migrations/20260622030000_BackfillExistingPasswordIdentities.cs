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
UPDATE ""UserIdentities""
SET password_hash = (
    SELECT u.""password_hash""
    FROM ""Users"" u
    WHERE u.""id"" = ""UserIdentities"".""user_id""
      AND u.""password_hash"" IS NOT NULL
      AND u.""password_hash"" <> ''
)
WHERE ""auth_provider"" = 'password'
  AND (""password_hash"" IS NULL OR ""password_hash"" = '')
  AND EXISTS (
    SELECT 1 FROM ""Users"" u
    WHERE u.""id"" = ""UserIdentities"".""user_id""
      AND u.""password_hash"" IS NOT NULL
      AND u.""password_hash"" <> ''
  );
");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
UPDATE ""UserIdentities""
SET password_hash = NULL
WHERE ""auth_provider"" = 'password'
  AND EXISTS (
    SELECT 1 FROM ""Users"" u
    WHERE u.""id"" = ""UserIdentities"".""user_id""
      AND u.""password_hash"" IS NOT NULL
      AND u.""password_hash"" <> ''
  );
");
        }
    }
}
