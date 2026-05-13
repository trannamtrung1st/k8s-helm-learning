using Microsoft.Extensions.DependencyInjection;
using Workbench.Application;
using Workbench.Infrastructure;

if (args.Length == 0 || HasFlag(args, "-h", "--help"))
{
    PrintHelp();
    return;
}

var command = args[0].Trim().ToLowerInvariant();
var commandArgs = args.Skip(1).ToArray();

var exitCode = command switch
{
    "cleanup-old-jobs" => await RunCleanupOldJobsAsync(commandArgs).ConfigureAwait(false),
    _ => HandleUnknownCommand(command)
};

Environment.ExitCode = exitCode;

static async Task<int> RunCleanupOldJobsAsync(string[] args)
{
    if (!TryGetOption(args, "--older-than-days", out var daysRaw)
        || !int.TryParse(daysRaw, out var olderThanDays)
        || olderThanDays < 1)
    {
        Console.Error.WriteLine("Missing or invalid --older-than-days. It must be an integer >= 1.");
        PrintHelp();
        return 1;
    }

    var dryRun = HasFlag(args, "--dry-run");
    var connectionString = GetConnectionString(args);

    if (string.IsNullOrWhiteSpace(connectionString))
    {
        Console.Error.WriteLine(
            "Database connection string is required. Provide --connection-string or set ConnectionStrings__Default.");
        return 1;
    }

    var services = new ServiceCollection();
    services.AddWorkbenchPersistence(connectionString);
    services.AddWorkbenchApplicationServices();

    Console.WriteLine($"Job: cleanup-old-jobs");

    await using var provider = services.BuildServiceProvider();
    using var scope = provider.CreateScope();
    var maintenance = scope.ServiceProvider.GetRequiredService<IJobMaintenanceApplicationService>();
    var result = await maintenance
        .CleanupOldJobsAsync(olderThanDays, dryRun, CancellationToken.None)
        .ConfigureAwait(false);

    Console.WriteLine($"Cutoff (UTC): {result.CutoffUtc:O}");
    Console.WriteLine($"Candidates: {result.Candidates}");
    if (result.DryRun)
    {
        Console.WriteLine("Dry run enabled. No records were deleted.");
    }
    else
    {
        Console.WriteLine($"Deleted: {result.Deleted}");
    }

    return 0;
}

static string? GetConnectionString(string[] args)
{
    if (TryGetOption(args, "--connection-string", out var fromArg))
    {
        return fromArg;
    }

    return Environment.GetEnvironmentVariable("ConnectionStrings__Default");
}

static bool TryGetOption(string[] args, string optionName, out string value)
{
    for (var i = 0; i < args.Length - 1; i++)
    {
        if (string.Equals(args[i], optionName, StringComparison.OrdinalIgnoreCase))
        {
            value = args[i + 1];
            return true;
        }
    }

    value = string.Empty;
    return false;
}

static bool HasFlag(IEnumerable<string> args, params string[] flags) =>
    args.Any(a => flags.Any(flag => string.Equals(a, flag, StringComparison.OrdinalIgnoreCase)));

static int HandleUnknownCommand(string command)
{
    Console.Error.WriteLine($"Unknown command: {command}");
    PrintHelp();
    return 1;
}

static void PrintHelp()
{
    Console.WriteLine(
        """
        Workbench.Jobs - run one-off maintenance jobs.

        Usage:
          dotnet Workbench.Jobs.dll <command> [options]

        Commands:
          cleanup-old-jobs
            Deletes jobs older than X days.
            Required:
              --older-than-days <int>    Delete jobs where CreatedAt is older than this many days.
            Optional:
              --connection-string <text> PostgreSQL connection string.
              --dry-run                  Prints how many rows would be deleted without deleting.

        Connection string fallback:
          ConnectionStrings__Default environment variable
        """);
}
