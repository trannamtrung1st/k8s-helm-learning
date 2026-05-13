using Workbench.Domain;

namespace Workbench.Application.Abstractions;

public interface IJobRepository
{
    Task AddAsync(Job job, CancellationToken cancellationToken);
    Task<Job?> GetTrackedByIdAsync(Guid id, CancellationToken cancellationToken);
    Task<Job?> GetByIdReadOnlyAsync(Guid id, CancellationToken cancellationToken);
    Task<IReadOnlyList<Job>> ListRecentReadOnlyAsync(int take, CancellationToken cancellationToken);
    Task<int> CountOlderThanAsync(DateTimeOffset cutoff, CancellationToken cancellationToken);
    Task<int> DeleteOlderThanAsync(DateTimeOffset cutoff, CancellationToken cancellationToken);
    Task SaveChangesAsync(CancellationToken cancellationToken);
}
