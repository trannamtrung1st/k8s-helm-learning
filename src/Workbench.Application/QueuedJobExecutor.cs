using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Workbench.Application.Abstractions;
using Workbench.Domain;

namespace Workbench.Application;

public sealed class QueuedJobExecutor(
    IJobRepository jobs,
    IOptions<WorkbenchOptions> options,
    ILogger<QueuedJobExecutor> logger) : IQueuedJobExecutor
{
    public async Task ExecuteAsync(Guid jobId, JobPayload payload, CancellationToken cancellationToken)
    {
        var job = await jobs.GetTrackedByIdAsync(jobId, cancellationToken).ConfigureAwait(false);
        if (job is null)
        {
            logger.LogWarning("Job {JobId} not found; acknowledging.", jobId);
            return;
        }

        var limits = options.Value.ToLimits();
        var errors = JobPayloadValidation.Validate(payload, limits);
        if (errors.Count > 0)
        {
            logger.LogWarning(
                "Job {JobId} rejected at execution: validation errors {Errors}",
                jobId,
                string.Join("; ", errors.Select(e => $"{e.Field}: {e.Message}")));
            job.Status = JobStatusNames.Failed;
            job.Error = string.Join("; ", errors.Select(e => $"{e.Field}: {e.Message}"));
            job.FinishedAt = DateTimeOffset.UtcNow;
            await jobs.SaveChangesAsync(cancellationToken).ConfigureAwait(false);
            return;
        }

        job.Status = JobStatusNames.Running;
        job.StartedAt = DateTimeOffset.UtcNow;
        job.ExecutionDurationMs = null;
        job.PeakWorkingSetBytes = null;
        job.ProcessAvgCpuPercent = null;
        await jobs.SaveChangesAsync(cancellationToken).ConfigureAwait(false);

        logger.LogInformation("Job {JobId} running simulation", jobId);

        try
        {
            var metrics = await LoadSimulator.RunAsync(payload, logger, cancellationToken).ConfigureAwait(false);
            job.Status = JobStatusNames.Succeeded;
            job.ExecutionDurationMs = metrics.WallClockMs;
            job.PeakWorkingSetBytes = metrics.PeakWorkingSetBytes;
            job.ProcessAvgCpuPercent = metrics.ProcessAvgCpuPercent;
            job.FinishedAt = DateTimeOffset.UtcNow;
            logger.LogInformation("Job {JobId} succeeded", jobId);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Job {JobId} failed during simulation", jobId);
            job.Status = JobStatusNames.Failed;
            job.Error = ex.Message;
            job.FinishedAt = DateTimeOffset.UtcNow;
        }

        await jobs.SaveChangesAsync(cancellationToken).ConfigureAwait(false);
    }
}
