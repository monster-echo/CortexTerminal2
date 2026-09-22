using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace CortexTerminal.Gateway.Migrations
{
    /// <inheritdoc />
    public partial class AddReferral : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "referred_by_user_id",
                table: "Users",
                type: "text",
                nullable: true);

            migrationBuilder.CreateTable(
                name: "ReferralCodes",
                columns: table => new
                {
                    id = table.Column<string>(type: "text", nullable: false),
                    user_id = table.Column<string>(type: "text", nullable: false),
                    code = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    created_at_utc = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ReferralCodes", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "ReferralRewards",
                columns: table => new
                {
                    id = table.Column<string>(type: "text", nullable: false),
                    referrer_user_id = table.Column<string>(type: "text", nullable: false),
                    invited_user_id = table.Column<string>(type: "text", nullable: false),
                    invited_username = table.Column<string>(type: "text", nullable: true),
                    reward_days = table.Column<int>(type: "integer", nullable: false),
                    source = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    created_at_utc = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ReferralRewards", x => x.id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_ReferralCodes_code",
                table: "ReferralCodes",
                column: "code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_ReferralCodes_user_id",
                table: "ReferralCodes",
                column: "user_id",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_ReferralRewards_invited_user_id",
                table: "ReferralRewards",
                column: "invited_user_id",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_ReferralRewards_referrer_user_id",
                table: "ReferralRewards",
                column: "referrer_user_id");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "ReferralCodes");

            migrationBuilder.DropTable(
                name: "ReferralRewards");

            migrationBuilder.DropColumn(
                name: "referred_by_user_id",
                table: "Users");
        }
    }
}
