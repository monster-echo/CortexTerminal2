using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace CortexTerminal.Gateway.Migrations
{
    /// <inheritdoc />
    /// <summary>
    /// Defensive backfill: any User with a non-empty Users.password_hash but no
    /// password UserIdentity row gets one created. This handles users that were
    /// registered via phone/huawei/apple OAuth, later set a password via
    /// /api/me/password, but for some reason (legacy flows, account-restore from
    /// backup, manual DB surgery) lost their password identity row.
    ///
    /// Also normalizes phone_normalized to the 11-digit form used by NormalizePhone()
    /// in Program.cs — earlier migration seed SQL used REGEXP_REPLACE which kept
    /// the country code (13/15 digits), making Phase 1 password-by-phone login
    /// unable to match. Idempotent.
    /// </summary>
    public partial class SeedMissingPasswordIdentities : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // 1) Create a password identity for every legacy password holder that
            //    doesn't have one yet. phone_normalized is filled when the User has
            //    a phone-style auth_provider_id so that phone+password login works.
            migrationBuilder.Sql(@"
INSERT INTO ""UserIdentities"" (id, user_id, auth_provider, auth_provider_id, email, phone_normalized, password_hash, created_at_utc)
SELECT
    regexp_replace(gen_random_uuid()::text, '-', '', 'g'),
    u.""id"",
    'password',
    u.""username"",
    u.""email"",
    CASE
        WHEN u.""auth_provider"" IN ('phone', 'huawei') AND u.""auth_provider_id"" IS NOT NULL
             AND char_length(regexp_replace(u.""auth_provider_id"", '[^0-9]', '', 'g')) >= 11
        THEN substring(regexp_replace(u.""auth_provider_id"", '[^0-9]', '', 'g') from char_length(regexp_replace(u.""auth_provider_id"", '[^0-9]', '', 'g')) - 10)
        ELSE NULL
    END,
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

            // 2) Normalize phone_normalized to last-11-digits form (matches
            //    NormalizePhone() in Program.cs). Only touches values that currently
            //    have a country-code prefix (>11 digits).
            migrationBuilder.Sql(@"
UPDATE ""UserIdentities""
SET phone_normalized = substring(phone_normalized from char_length(phone_normalized) - 10)
WHERE phone_normalized IS NOT NULL
  AND char_length(phone_normalized) > 11;
");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            // Best-effort reverse: drop the password identities this migration
            // may have introduced (rows whose AuthProviderId collides with a
            // Users.Username — the seed signature). Existing password identities
            // created via /api/auth/password/register are not affected because
            // those have AuthProviderId values that don't collide with Usernames.
            migrationBuilder.Sql(@"
DELETE FROM ""UserIdentities"" ui
WHERE ui.""auth_provider"" = 'password'
  AND EXISTS (
    SELECT 1 FROM ""Users"" u WHERE u.""username"" = ui.""auth_provider_id""
  );
");
            // phone_normalized normalization is not reversed — the 13-digit form
            // was buggy and there's no reason to restore it.
        }
    }
}
