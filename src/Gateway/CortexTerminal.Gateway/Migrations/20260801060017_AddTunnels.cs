using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace CortexTerminal.Gateway.Migrations
{
    /// <inheritdoc />
    public partial class AddTunnels : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "Tunnels",
                columns: table => new
                {
                    id = table.Column<string>(type: "text", nullable: false),
                    tunnel_key = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    owner_user_id = table.Column<string>(type: "text", nullable: false),
                    worker_id = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    worker_connection_id = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    session_id = table.Column<string>(type: "text", nullable: false),
                    port = table.Column<int>(type: "integer", nullable: false),
                    secret_hash = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    transport_type = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    expires_at_utc = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    created_at_utc = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    revoked_at_utc = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Tunnels", x => x.id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_Tunnels_expires_at_utc",
                table: "Tunnels",
                column: "expires_at_utc");

            migrationBuilder.CreateIndex(
                name: "IX_Tunnels_owner_user_id",
                table: "Tunnels",
                column: "owner_user_id");

            migrationBuilder.CreateIndex(
                name: "IX_Tunnels_session_id",
                table: "Tunnels",
                column: "session_id");

            migrationBuilder.CreateIndex(
                name: "IX_Tunnels_tunnel_key",
                table: "Tunnels",
                column: "tunnel_key",
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "Tunnels");
        }
    }
}
