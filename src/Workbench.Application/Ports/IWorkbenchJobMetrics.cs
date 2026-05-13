namespace Workbench.Application.Abstractions;

/// <summary>Lightweight Redis counters for demo observability (enqueue vs processed).</summary>
public interface IWorkbenchJobMetrics
{
    Task RecordEnqueueAsync(CancellationToken cancellationToken = default);

    Task RecordProcessedAsync(CancellationToken cancellationToken = default);

    Task<long> GetEnqueueTotalAsync(CancellationToken cancellationToken = default);

    Task<long> GetProcessedTotalAsync(CancellationToken cancellationToken = default);
}
