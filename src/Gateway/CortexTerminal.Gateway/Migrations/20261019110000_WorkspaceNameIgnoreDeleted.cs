using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace CortexTerminal.Gateway.Migrations
{
    /// <inheritdoc />
    public partial class WorkspaceNameIgnoreDeleted : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_Workspaces_worker_id_name",
                table: "Workspaces");

            migrationBuilder.CreateIndex(
                name: "IX_Workspaces_worker_id_name",
                table: "Workspaces",
                columns: new[] { "worker_id", "name" },
                unique: true,
                filter: "\"deleted_at_utc\" IS NULL");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_Workspaces_worker_id_name",
                table: "Workspaces");

            migrationBuilder.CreateIndex(
                name: "IX_Workspaces_worker_id_name",
                table: "Workspaces",
                columns: new[] { "worker_id", "name" },
                unique: true);
        }
    }
}
