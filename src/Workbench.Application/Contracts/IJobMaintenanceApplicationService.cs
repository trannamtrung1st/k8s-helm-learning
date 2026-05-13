namespace Workbench.Application;

public interface IJobMaintenanceApplicationService
{
    Task<JobCleanupResult> CleanupOldJobsAsync(int olderThanDays, bool dryRun, CancellationToken cancellationToken);
}

public sealed record JobCleanupResult(DateTimeOffset CutoffUtc, int Candidates, int Deleted, bool DryRun);
