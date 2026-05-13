using Workbench.Application.Abstractions;

namespace Workbench.Application;

public sealed class JobMaintenanceApplicationService(IJobRepository jobs) : IJobMaintenanceApplicationService
{
    public async Task<JobCleanupResult> CleanupOldJobsAsync(
        int olderThanDays,
        bool dryRun,
        CancellationToken cancellationToken)
    {
        if (olderThanDays < 1)
            throw new ArgumentOutOfRangeException(nameof(olderThanDays), "olderThanDays must be >= 1.");

        var cutoff = DateTimeOffset.UtcNow.AddDays(-olderThanDays);
        var candidates = await jobs.CountOlderThanAsync(cutoff, cancellationToken).ConfigureAwait(false);

        if (dryRun)
            return new JobCleanupResult(cutoff, candidates, 0, DryRun: true);

        var deleted = await jobs.DeleteOlderThanAsync(cutoff, cancellationToken).ConfigureAwait(false);
        return new JobCleanupResult(cutoff, candidates, deleted, DryRun: false);
    }
}
