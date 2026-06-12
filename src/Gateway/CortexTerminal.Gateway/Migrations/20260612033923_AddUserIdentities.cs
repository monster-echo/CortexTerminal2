using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace CortexTerminal.Gateway.Migrations
{
    /// <inheritdoc />
    public partial class AddUserIdentities : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "UserIdentities",
                columns: table => new
                {
                    id = table.Column<string>(type: "text", nullable: false),
                    user_id = table.Column<string>(type: "text", nullable: false),
                    auth_provider = table.Column<string>(type: "text", nullable: false),
                    auth_provider_id = table.Column<string>(type: "text", nullable: false),
                    email = table.Column<string>(type: "text", nullable: true),
                    phone_normalized = table.Column<string>(type: "text", nullable: true),
                    created_at_utc = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_UserIdentities", x => x.id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_UserIdentities_auth_provider_auth_provider_id",
                table: "UserIdentities",
                columns: new[] { "auth_provider", "auth_provider_id" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_UserIdentities_email",
                table: "UserIdentities",
                column: "email");

            migrationBuilder.CreateIndex(
                name: "IX_UserIdentities_phone_normalized",
                table: "UserIdentities",
                column: "phone_normalized");

            migrationBuilder.CreateIndex(
                name: "IX_UserIdentities_user_id",
                table: "UserIdentities",
                column: "user_id");

            // Seed identities from existing Users
            migrationBuilder.Sql(@"
                INSERT INTO ""UserIdentities"" (id, user_id, auth_provider, auth_provider_id, email, phone_normalized, created_at_utc)
                SELECT
                    gen_random_uuid()::text,
                    u.id,
                    COALESCE(u.auth_provider, 'password'),
                    COALESCE(u.auth_provider_id, u.username),
                    u.email,
                    CASE
                        WHEN u.auth_provider IN ('phone', 'huawei') AND u.auth_provider_id IS NOT NULL
                        THEN REGEXP_REPLACE(u.auth_provider_id, '[^0-9]', '', 'g')
                        ELSE NULL
                    END,
                    COALESCE(u.created_at_utc, NOW())
                FROM ""Users"" u
                WHERE u.status = 'active'
            ");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "UserIdentities");
        }
    }
}
