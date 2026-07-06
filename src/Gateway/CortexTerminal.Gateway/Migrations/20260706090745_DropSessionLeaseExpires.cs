using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace CortexTerminal.Gateway.Migrations
{
    /// <inheritdoc />
    public partial class DropSessionLeaseExpires : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "lease_expires_at_utc",
                table: "Sessions");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<DateTimeOffset>(
                name: "lease_expires_at_utc",
                table: "Sessions",
                type: "timestamp with time zone",
                nullable: true);
        }
    }
}
