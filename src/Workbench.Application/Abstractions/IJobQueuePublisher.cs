using Workbench.Domain;

namespace Workbench.Application.Abstractions;

public interface IJobQueuePublisher
{
    Task PublishJobAsync(JobEnvelope envelope, CancellationToken cancellationToken);
}
