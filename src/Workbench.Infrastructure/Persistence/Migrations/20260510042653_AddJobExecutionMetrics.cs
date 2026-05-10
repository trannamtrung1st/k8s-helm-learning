using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Workbench.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddJobExecutionMetrics : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<long>(
                name: "execution_duration_ms",
                table: "jobs",
                type: "bigint",
                nullable: true);

            migrationBuilder.AddColumn<long>(
                name: "peak_working_set_bytes",
                table: "jobs",
                type: "bigint",
                nullable: true);

            migrationBuilder.AddColumn<double>(
                name: "process_avg_cpu_percent",
                table: "jobs",
                type: "double precision",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "execution_duration_ms",
                table: "jobs");

            migrationBuilder.DropColumn(
                name: "peak_working_set_bytes",
                table: "jobs");

            migrationBuilder.DropColumn(
                name: "process_avg_cpu_percent",
                table: "jobs");
        }
    }
}
