using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace CortexTerminal.Gateway.Migrations
{
    /// <inheritdoc />
    public partial class AddAvatarColumns : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "avatar_content_type",
                table: "Users",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<byte[]>(
                name: "avatar_data",
                table: "Users",
                type: "bytea",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "avatar_content_type",
                table: "Users");

            migrationBuilder.DropColumn(
                name: "avatar_data",
                table: "Users");
        }
    }
}
