using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Workbench.Application.Abstractions;
using Workbench.Domain;

namespace Workbench.Application;

public sealed class JobsApplicationService(
    IJobRepository jobs,
    IJobQueuePublisher publisher,
    IWorkbenchJobMetrics jobMetrics,
    IOptions<WorkbenchOptions> options,
    ILogger<JobsApplicationService> logger) : IJobsApplicationService
{
    public async Task<EnqueueJobResult> EnqueueJobAsync(JobPayload payload, CancellationToken cancellationToken)
    {
        var limits = options.Value.ToLimits();
        var errors = JobPayloadValidation.Validate(payload, limits);
        if (errors.Count > 0)
            return new EnqueueJobValidationFailed(errors);

        var id = Guid.NewGuid();
        var now = DateTimeOffset.UtcNow;
        var job = new Job
        {
            Id = id,
            Status = JobStatusNames.Queued,
            Payload = payload,
            CreatedAt = now,
        };
        await jobs.AddAsync(job, cancellationToken).ConfigureAwait(false);
        await jobs.SaveChangesAsync(cancellationToken).ConfigureAwait(false);

        await publisher.PublishJobAsync(
            new JobEnvelope { JobId = id, Payload = payload },
            cancellationToken).ConfigureAwait(false);

        try
        {
            await jobMetrics.RecordEnqueueAsync(cancellationToken).ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Redis enqueue metric failed; job was still enqueued.");
        }

        logger.LogInformation("Job {JobId} enqueued and published to queue", id);
        return new EnqueueJobSuccess(id, JobStatusNames.Queued);
    }

    public async Task<JobDetailDto?> GetJobAsync(Guid id, CancellationToken cancellationToken)
    {
        var job = await jobs.GetByIdReadOnlyAsync(id, cancellationToken).ConfigureAwait(false);
        return job is null ? null : Map(job);
    }

    public async Task<IReadOnlyList<JobDetailDto>> ListJobsAsync(int limit, CancellationToken cancellationToken)
    {
        var take = limit <= 0 ? 20 : Math.Min(limit, 100);
        var list = await jobs.ListRecentReadOnlyAsync(take, cancellationToken).ConfigureAwait(false);
        return list.Select(Map).ToArray();
    }

    public async Task<SyncWorkResult> RunSyncWorkAsync(JobPayload payload, CancellationToken cancellationToken)
    {
        var limits = options.Value.ToLimits();
        var errors = JobPayloadValidation.Validate(payload, limits);
        if (errors.Count > 0)
            return new SyncWorkValidationFailed(errors);

        logger.LogInformation("Sync workload starting (POST /api/wb/work)");
        var metrics =
            await LoadSimulator.RunAsync(payload, logger, cancellationToken).ConfigureAwait(false);
        logger.LogInformation("Sync workload completed in {ElapsedMs} ms", metrics.WallClockMs);
        return new SyncWorkSuccess(metrics);
    }

    private static JobDetailDto Map(Job j) => new(
        j.Id,
        j.Status,
        j.Payload,
        j.CreatedAt,
        j.StartedAt,
        j.FinishedAt,
        j.Error,
        j.ExecutionDurationMs,
        j.PeakWorkingSetBytes,
        j.ProcessAvgCpuPercent);
}
