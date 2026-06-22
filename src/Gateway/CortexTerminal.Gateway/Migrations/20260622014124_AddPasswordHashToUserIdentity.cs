using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace CortexTerminal.Gateway.Migrations
{
    /// <inheritdoc />
    public partial class AddPasswordHashToUserIdentity : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "password_hash",
                table: "UserIdentities",
                type: "text",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "password_hash",
                table: "UserIdentities");
        }
    }
}
