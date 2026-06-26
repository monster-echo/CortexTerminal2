using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace CortexTerminal.Gateway.Migrations
{
    /// <inheritdoc />
    public partial class AddAgentTracking : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "agent_kind",
                table: "Sessions",
                type: "character varying(32)",
                maxLength: 32,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "agent_session_id",
                table: "Sessions",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "inferred_title",
                table: "Sessions",
                type: "character varying(200)",
                maxLength: 200,
                nullable: true);

            migrationBuilder.CreateTable(
                name: "SessionAgentEvents",
                columns: table => new
                {
                    id = table.Column<long>(type: "bigint", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    session_id = table.Column<string>(type: "text", nullable: false),
                    event_type = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    payload = table.Column<string>(type: "text", nullable: false),
                    created_at_utc = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_SessionAgentEvents", x => x.id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_SessionAgentEvents_session_id",
                table: "SessionAgentEvents",
                column: "session_id");

            migrationBuilder.CreateIndex(
                name: "IX_SessionAgentEvents_session_id_created_at_utc",
                table: "SessionAgentEvents",
                columns: new[] { "session_id", "created_at_utc" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "SessionAgentEvents");

            migrationBuilder.DropColumn(
                name: "agent_kind",
                table: "Sessions");

            migrationBuilder.DropColumn(
                name: "agent_session_id",
                table: "Sessions");

            migrationBuilder.DropColumn(
                name: "inferred_title",
                table: "Sessions");
        }
    }
}
