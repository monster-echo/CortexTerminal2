using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace CortexTerminal.Gateway.Migrations
{
    /// <inheritdoc />
    public partial class InitialCreate : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "AuditLogs",
                columns: table => new
                {
                    id = table.Column<string>(type: "text", nullable: false),
                    timestamp = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    user_id = table.Column<string>(type: "text", nullable: false),
                    user_name = table.Column<string>(type: "text", nullable: false),
                    action = table.Column<string>(type: "text", nullable: false),
                    target_entity = table.Column<string>(type: "text", nullable: false),
                    target_id = table.Column<string>(type: "text", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_AuditLogs", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "Sessions",
                columns: table => new
                {
                    session_id = table.Column<string>(type: "text", nullable: false),
                    user_id = table.Column<string>(type: "text", nullable: false),
                    worker_id = table.Column<string>(type: "text", nullable: false),
                    columns = table.Column<int>(type: "integer", nullable: false),
                    rows = table.Column<int>(type: "integer", nullable: false),
                    created_at_utc = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    last_activity_at_utc = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    attachment_state = table.Column<string>(type: "text", nullable: false),
                    attached_client_connection_id = table.Column<string>(type: "text", nullable: true),
                    lease_expires_at_utc = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    exit_code = table.Column<int>(type: "integer", nullable: true),
                    exit_reason = table.Column<string>(type: "text", nullable: true),
                    replay_pending = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Sessions", x => x.session_id);
                });

            migrationBuilder.CreateTable(
                name: "Users",
                columns: table => new
                {
                    id = table.Column<string>(type: "text", nullable: false),
                    username = table.Column<string>(type: "text", nullable: false),
                    email = table.Column<string>(type: "text", nullable: true),
                    display_name = table.Column<string>(type: "text", nullable: true),
                    avatar_url = table.Column<string>(type: "text", nullable: true),
                    role = table.Column<string>(type: "text", nullable: false),
                    status = table.Column<string>(type: "text", nullable: false),
                    auth_provider = table.Column<string>(type: "text", nullable: true),
                    auth_provider_id = table.Column<string>(type: "text", nullable: true),
                    password_hash = table.Column<string>(type: "text", nullable: true),
                    apple_refresh_token = table.Column<string>(type: "text", nullable: true),
                    deleted_at_utc = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    created_at_utc = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    updated_at_utc = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Users", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "Workers",
                columns: table => new
                {
                    worker_id = table.Column<string>(type: "text", nullable: false),
                    owner_user_id = table.Column<string>(type: "text", nullable: true),
                    hostname = table.Column<string>(type: "text", nullable: true),
                    operating_system = table.Column<string>(type: "text", nullable: true),
                    architecture = table.Column<string>(type: "text", nullable: true),
                    name = table.Column<string>(type: "text", nullable: true),
                    version = table.Column<string>(type: "text", nullable: true),
                    last_seen_at_utc = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    first_connected_at_utc = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    is_online = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Workers", x => x.worker_id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_AuditLogs_action",
                table: "AuditLogs",
                column: "action");

            migrationBuilder.CreateIndex(
                name: "IX_AuditLogs_timestamp",
                table: "AuditLogs",
                column: "timestamp");

            migrationBuilder.CreateIndex(
                name: "IX_AuditLogs_user_id",
                table: "AuditLogs",
                column: "user_id");

            migrationBuilder.CreateIndex(
                name: "IX_Sessions_attachment_state",
                table: "Sessions",
                column: "attachment_state");

            migrationBuilder.CreateIndex(
                name: "IX_Sessions_created_at_utc",
                table: "Sessions",
                column: "created_at_utc");

            migrationBuilder.CreateIndex(
                name: "IX_Sessions_user_id",
                table: "Sessions",
                column: "user_id");

            migrationBuilder.CreateIndex(
                name: "IX_Sessions_worker_id",
                table: "Sessions",
                column: "worker_id");

            migrationBuilder.CreateIndex(
                name: "IX_Users_auth_provider_auth_provider_id",
                table: "Users",
                columns: new[] { "auth_provider", "auth_provider_id" });

            migrationBuilder.CreateIndex(
                name: "IX_Users_username",
                table: "Users",
                column: "username",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_Workers_is_online",
                table: "Workers",
                column: "is_online");

            migrationBuilder.CreateIndex(
                name: "IX_Workers_owner_user_id",
                table: "Workers",
                column: "owner_user_id");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "AuditLogs");

            migrationBuilder.DropTable(
                name: "Sessions");

            migrationBuilder.DropTable(
                name: "Users");

            migrationBuilder.DropTable(
                name: "Workers");
        }
    }
}
