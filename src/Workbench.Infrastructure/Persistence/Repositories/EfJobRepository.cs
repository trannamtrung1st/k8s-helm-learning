using Microsoft.EntityFrameworkCore;
using Workbench.Application.Abstractions;
using Workbench.Domain;

namespace Workbench.Infrastructure.Persistence;

public sealed class EfJobRepository(JobsDbContext db) : IJobRepository
{
    public Task AddAsync(Job job, CancellationToken cancellationToken)
    {
        db.Jobs.Add(job);
        return Task.CompletedTask;
    }

    public Task<Job?> GetTrackedByIdAsync(Guid id, CancellationToken cancellationToken) =>
        db.Jobs.FirstOrDefaultAsync(j => j.Id == id, cancellationToken);

    public Task<Job?> GetByIdReadOnlyAsync(Guid id, CancellationToken cancellationToken) =>
        db.Jobs.AsNoTracking().FirstOrDefaultAsync(j => j.Id == id, cancellationToken);

    public async Task<IReadOnlyList<Job>> ListRecentReadOnlyAsync(int take, CancellationToken cancellationToken)
    {
        var list = await db.Jobs.AsNoTracking()
            .OrderByDescending(j => j.CreatedAt)
            .Take(take)
            .ToListAsync(cancellationToken)
            .ConfigureAwait(false);
        return list;
    }

    public Task<int> CountOlderThanAsync(DateTimeOffset cutoff, CancellationToken cancellationToken) =>
        db.Jobs.CountAsync(j => j.CreatedAt < cutoff, cancellationToken);

    public Task<int> DeleteOlderThanAsync(DateTimeOffset cutoff, CancellationToken cancellationToken) =>
        db.Jobs.Where(j => j.CreatedAt < cutoff).ExecuteDeleteAsync(cancellationToken);

    public Task SaveChangesAsync(CancellationToken cancellationToken) =>
        db.SaveChangesAsync(cancellationToken);
}
