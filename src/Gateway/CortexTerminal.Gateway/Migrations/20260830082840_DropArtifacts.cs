using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace CortexTerminal.Gateway.Migrations
{
    /// <inheritdoc />
    public partial class DropArtifacts : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "Artifacts");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "Artifacts",
                columns: table => new
                {
                    id = table.Column<string>(type: "text", nullable: false),
                    completed_at_utc = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    content_sha256 = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: true),
                    created_at_utc = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    expires_at_utc = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    file_category = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    filename = table.Column<string>(type: "character varying(255)", maxLength: 255, nullable: false),
                    origin = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    owner_user_id = table.Column<string>(type: "text", nullable: false),
                    session_id = table.Column<string>(type: "text", nullable: false),
                    size_bytes = table.Column<long>(type: "bigint", nullable: false),
                    status = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Artifacts", x => x.id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_Artifacts_expires_at_utc",
                table: "Artifacts",
                column: "expires_at_utc");

            migrationBuilder.CreateIndex(
                name: "IX_Artifacts_owner_user_id",
                table: "Artifacts",
                column: "owner_user_id");

            migrationBuilder.CreateIndex(
                name: "IX_Artifacts_session_id",
                table: "Artifacts",
                column: "session_id");

            migrationBuilder.CreateIndex(
                name: "IX_Artifacts_session_id_filename",
                table: "Artifacts",
                columns: new[] { "session_id", "filename" },
                unique: true);
        }
    }
}
