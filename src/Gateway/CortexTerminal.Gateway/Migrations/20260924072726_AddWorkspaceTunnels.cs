using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace CortexTerminal.Gateway.Migrations
{
    /// <inheritdoc />
    public partial class AddWorkspaceTunnels : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "local_port",
                table: "Tunnels",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<string>(
                name: "name",
                table: "Tunnels",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "remote_address",
                table: "Tunnels",
                type: "character varying(255)",
                maxLength: 255,
                nullable: false,
                defaultValue: "127.0.0.1");

            migrationBuilder.AddColumn<string>(
                name: "workspace_id",
                table: "Tunnels",
                type: "text",
                nullable: false,
                defaultValue: "");

            migrationBuilder.CreateIndex(
                name: "IX_Tunnels_workspace_id",
                table: "Tunnels",
                column: "workspace_id");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_Tunnels_workspace_id",
                table: "Tunnels");

            migrationBuilder.DropColumn(
                name: "local_port",
                table: "Tunnels");

            migrationBuilder.DropColumn(
                name: "name",
                table: "Tunnels");

            migrationBuilder.DropColumn(
                name: "remote_address",
                table: "Tunnels");

            migrationBuilder.DropColumn(
                name: "workspace_id",
                table: "Tunnels");
        }
    }
}
