using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace CortexTerminal.Gateway.Migrations
{
    /// <inheritdoc />
    public partial class AddMembership : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<DateTimeOffset>(
                name: "membership_expires_at_utc",
                table: "Users",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "membership_plan_id",
                table: "Users",
                type: "character varying(64)",
                maxLength: 64,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "membership_tier",
                table: "Users",
                type: "character varying(16)",
                maxLength: 16,
                nullable: false,
                defaultValue: "");

            migrationBuilder.CreateTable(
                name: "IapWebhookEvents",
                columns: table => new
                {
                    id = table.Column<string>(type: "text", nullable: false),
                    platform = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    external_event_id = table.Column<string>(type: "character varying(128)", maxLength: 128, nullable: false),
                    raw_payload = table.Column<string>(type: "text", nullable: false),
                    received_at_utc = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    processed = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_IapWebhookEvents", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "MembershipOrders",
                columns: table => new
                {
                    id = table.Column<string>(type: "text", nullable: false),
                    user_id = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    plan_id = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    billing_period = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    amount = table.Column<decimal>(type: "numeric", nullable: false),
                    currency = table.Column<string>(type: "character varying(8)", maxLength: 8, nullable: false),
                    channel = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    status = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    receipt = table.Column<string>(type: "character varying(2048)", maxLength: 2048, nullable: true),
                    provider_order_id = table.Column<string>(type: "character varying(128)", maxLength: 128, nullable: true),
                    created_at_utc = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    completed_at_utc = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_MembershipOrders", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "Plans",
                columns: table => new
                {
                    id = table.Column<string>(type: "text", nullable: false),
                    code = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    tier = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    billing_period = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    price_amount = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    price_currency = table.Column<string>(type: "character varying(8)", maxLength: 8, nullable: false),
                    max_workers = table.Column<int>(type: "integer", nullable: false),
                    max_artifacts_per_session = table.Column<int>(type: "integer", nullable: false),
                    max_artifact_size_bytes = table.Column<long>(type: "bigint", nullable: false),
                    max_artifact_age_days = table.Column<int>(type: "integer", nullable: false),
                    max_scrollback_megabytes = table.Column<int>(type: "integer", nullable: false),
                    feature_flags = table.Column<string>(type: "character varying(512)", maxLength: 512, nullable: true),
                    is_active = table.Column<bool>(type: "boolean", nullable: false),
                    sort_order = table.Column<int>(type: "integer", nullable: false),
                    created_at_utc = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    updated_at_utc = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Plans", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "RedeemCodes",
                columns: table => new
                {
                    id = table.Column<string>(type: "text", nullable: false),
                    code = table.Column<string>(type: "character varying(24)", maxLength: 24, nullable: false),
                    plan_id = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    billing_period = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    batch_id = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: true),
                    max_uses = table.Column<int>(type: "integer", nullable: false),
                    used_count = table.Column<int>(type: "integer", nullable: false),
                    expires_at_utc = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    created_by_user_id = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    is_active = table.Column<bool>(type: "boolean", nullable: false),
                    created_at_utc = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_RedeemCodes", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "RedeemCodeUsages",
                columns: table => new
                {
                    id = table.Column<string>(type: "text", nullable: false),
                    redeem_code_id = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    user_id = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    order_id = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    subscription_id = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    redeemed_at_utc = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_RedeemCodeUsages", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "Subscriptions",
                columns: table => new
                {
                    id = table.Column<string>(type: "text", nullable: false),
                    user_id = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    plan_id = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    status = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    period = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    start_at_utc = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    expires_at_utc = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    source = table.Column<string>(type: "character varying(24)", maxLength: 24, nullable: false),
                    source_order_id = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: true),
                    source_redeem_code_id = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: true),
                    platform_transaction_id = table.Column<string>(type: "character varying(128)", maxLength: 128, nullable: true),
                    created_at_utc = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    updated_at_utc = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Subscriptions", x => x.id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_IapWebhookEvents_platform_external_event_id",
                table: "IapWebhookEvents",
                columns: new[] { "platform", "external_event_id" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_MembershipOrders_user_id",
                table: "MembershipOrders",
                column: "user_id");

            migrationBuilder.CreateIndex(
                name: "IX_Plans_code",
                table: "Plans",
                column: "code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_RedeemCodes_batch_id",
                table: "RedeemCodes",
                column: "batch_id");

            migrationBuilder.CreateIndex(
                name: "IX_RedeemCodes_code",
                table: "RedeemCodes",
                column: "code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_RedeemCodeUsages_redeem_code_id_user_id",
                table: "RedeemCodeUsages",
                columns: new[] { "redeem_code_id", "user_id" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_Subscriptions_source_platform_transaction_id",
                table: "Subscriptions",
                columns: new[] { "source", "platform_transaction_id" });

            migrationBuilder.CreateIndex(
                name: "IX_Subscriptions_user_id_status",
                table: "Subscriptions",
                columns: new[] { "user_id", "status" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "IapWebhookEvents");

            migrationBuilder.DropTable(
                name: "MembershipOrders");

            migrationBuilder.DropTable(
                name: "Plans");

            migrationBuilder.DropTable(
                name: "RedeemCodes");

            migrationBuilder.DropTable(
                name: "RedeemCodeUsages");

            migrationBuilder.DropTable(
                name: "Subscriptions");

            migrationBuilder.DropColumn(
                name: "membership_expires_at_utc",
                table: "Users");

            migrationBuilder.DropColumn(
                name: "membership_plan_id",
                table: "Users");

            migrationBuilder.DropColumn(
                name: "membership_tier",
                table: "Users");
        }
    }
}
