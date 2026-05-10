using Workbench.Domain;

namespace Workbench.Application.Abstractions;

public interface IQueuedJobExecutor
{
    Task ExecuteAsync(Guid jobId, JobPayload payload, CancellationToken cancellationToken);
}
