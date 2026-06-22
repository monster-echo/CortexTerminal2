using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace CortexTerminal.Gateway.Migrations
{
    /// <inheritdoc />
    /// <summary>
    /// One-off repair: phone_5543 (created 2026-05-06 via phone SMS) and
    /// hw_17701565543 (created 2026-06-22 via Huawei quick-login) are two
    /// separate User rows that belong to the same real person — both bind
    /// phone 17701565543. They were never auto-merged because the
    /// cross-provider phone linkage in EnsureUser is a recent addition.
    ///
    /// The user is currently active on hw_17701565543 (where they reset
    /// the password to test123 today), so we merge phone_5543 → hw_17701565543.
    ///
    /// What this migration does:
    ///   1. Backfill phone_normalized on hw_17701565543's password identity
    ///      so future phone+password logins route to the right account.
    ///   2. Reassign Sessions / Workers / AuditLogs ownership from
    ///      phone_5543 to hw_17701565543 (both have zero rows in practice
    ///      at the time of writing, but the UPDATEs are kept for safety).
    ///   3. Delete phone_5543's identities, then the User row itself.
    ///
    /// Idempotent: if phone_5543 is already gone, every statement no-ops.
    /// </summary>
    public partial class MergeDuplicatePhoneAccounts : Migration
    {
        private const string FromUserId = "166d9d400007451fb5a7afc298c83f3c"; // phone_5543
        private const string ToUserId = "94ebf2c1ee80476faaa1c46d1295aa0b";   // hw_17701565543
        private const string PhoneNormalized = "17701565543";

        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // 1) Backfill phone_normalized on the surviving password identity
            //    so that phone+password login resolves to hw_17701565543.
            migrationBuilder.Sql(@"
UPDATE ""UserIdentities""
SET phone_normalized = '" + PhoneNormalized + @"'
WHERE user_id = '" + ToUserId + @"'
  AND auth_provider = 'password'
  AND (phone_normalized IS NULL OR phone_normalized = '');
");

            // 2) Reassign ownership of dependent rows. Each UPDATE is a no-op
            //    if phone_5543 has no rows in that table.
            migrationBuilder.Sql(@"
UPDATE ""Sessions"" SET user_id = '" + ToUserId + @"' WHERE user_id = '" + FromUserId + @"';
UPDATE ""Workers"" SET owner_user_id = '" + ToUserId + @"' WHERE owner_user_id = '" + FromUserId + @"';
UPDATE ""AuditLogs"" SET user_id = '" + ToUserId + @"' WHERE user_id = '" + FromUserId + @"';
");

            // 3) Drop the duplicate user's identities, then the user row.
            migrationBuilder.Sql(@"
DELETE FROM ""UserIdentities"" WHERE user_id = '" + FromUserId + @"';
DELETE FROM ""Users"" WHERE id = '" + FromUserId + @"';
");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            // Recreate phone_5543 as a bare user row without identities.
            // The original password hash is gone (we deleted it in Up),
            // so the user cannot log in to this account after rollback.
            // We accept this — the merge is the desired end state and the
            // rollback exists only to satisfy EF's migration contract.
            migrationBuilder.Sql(@"
INSERT INTO ""Users"" (id, username, auth_provider, role, status, created_at_utc, updated_at_utc)
SELECT '" + FromUserId + @"', 'phone_5543', 'phone', 'user', 'active', NOW() AT TIME ZONE 'UTC', NOW() AT TIME ZONE 'UTC'
WHERE NOT EXISTS (SELECT 1 FROM ""Users"" WHERE id = '" + FromUserId + @"');
");
        }
    }
}
