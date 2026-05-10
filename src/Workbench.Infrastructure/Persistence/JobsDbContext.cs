using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using Workbench.Domain;

namespace Workbench.Infrastructure.Persistence;

public sealed class JobsDbContext(DbContextOptions<JobsDbContext> options) : DbContext(options)
{
    public DbSet<Job> Jobs => Set<Job>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<Job>(ConfigureJob);
    }

    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    private static void ConfigureJob(EntityTypeBuilder<Job> e)
    {
        e.ToTable("jobs");
        e.HasKey(x => x.Id);
        e.Property(x => x.Status).HasMaxLength(32).IsRequired();
        e.Property(x => x.Error).HasMaxLength(8192);
        e.Property(x => x.CreatedAt).HasColumnName("created_at");
        e.Property(x => x.StartedAt).HasColumnName("started_at");
        e.Property(x => x.FinishedAt).HasColumnName("finished_at");
        e.Property(x => x.ExecutionDurationMs).HasColumnName("execution_duration_ms");
        e.Property(x => x.PeakWorkingSetBytes).HasColumnName("peak_working_set_bytes");
        e.Property(x => x.ProcessAvgCpuPercent).HasColumnName("process_avg_cpu_percent");

        e.Property(x => x.Payload)
            .HasColumnName("payload")
            .HasColumnType("jsonb")
            .HasConversion(
                v => JsonSerializer.Serialize(v, JsonOptions),
                v => JsonSerializer.Deserialize<JobPayload>(v, JsonOptions)!);

        e.HasIndex(x => x.CreatedAt).IsDescending();
    }
}
