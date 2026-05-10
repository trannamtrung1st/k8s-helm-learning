using Workbench.Application.Abstractions;
using Workbench.Domain;

namespace Workbench.Application;

public interface IJobsApplicationService
{
    Task<EnqueueJobResult> EnqueueJobAsync(JobPayload payload, CancellationToken cancellationToken);
    Task<JobDetailDto?> GetJobAsync(Guid id, CancellationToken cancellationToken);
    Task<IReadOnlyList<JobDetailDto>> ListJobsAsync(int limit, CancellationToken cancellationToken);
    Task<SyncWorkResult> RunSyncWorkAsync(JobPayload payload, CancellationToken cancellationToken);
}

public abstract record EnqueueJobResult;
public sealed record EnqueueJobSuccess(Guid Id, string Status) : EnqueueJobResult;
public sealed record EnqueueJobValidationFailed(IReadOnlyList<JobPayloadValidation.ValidationError> Errors) : EnqueueJobResult;

public abstract record SyncWorkResult;
public sealed record SyncWorkSuccess(LoadSimulationMetrics Metrics) : SyncWorkResult;
public sealed record SyncWorkValidationFailed(IReadOnlyList<JobPayloadValidation.ValidationError> Errors) : SyncWorkResult;
