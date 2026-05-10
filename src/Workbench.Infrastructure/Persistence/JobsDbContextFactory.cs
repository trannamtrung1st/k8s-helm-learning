using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace Workbench.Infrastructure.Persistence;

/// <summary>
/// Allows <c>dotnet ef</c> to create <see cref="JobsDbContext"/> without starting the API host (avoids host timeout / DI issues).
/// Override connection with env <c>Workbench__Migrations__ConnectionString</c> or <c>ConnectionStrings__Default</c>.
/// </summary>
public sealed class JobsDbContextFactory : IDesignTimeDbContextFactory<JobsDbContext>
{
    public JobsDbContext CreateDbContext(string[] args)
    {
        var conn =
            Environment.GetEnvironmentVariable("Workbench__Migrations__ConnectionString")
            ?? Environment.GetEnvironmentVariable("ConnectionStrings__Default")
            ?? "Host=localhost;Port=5432;Database=workbench;Username=workbench;Password=workbench";

        var options = new DbContextOptionsBuilder<JobsDbContext>()
            .UseNpgsql(conn)
            .Options;

        return new JobsDbContext(options);
    }
}
