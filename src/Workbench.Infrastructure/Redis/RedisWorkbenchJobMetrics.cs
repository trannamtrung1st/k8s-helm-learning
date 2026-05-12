using StackExchange.Redis;
using Workbench.Application.Abstractions;

namespace Workbench.Infrastructure.Redis;

internal sealed class RedisWorkbenchJobMetrics(IConnectionMultiplexer multiplexer) : IWorkbenchJobMetrics
{
    private const string EnqueuedKey = "workbench:metrics:jobs_enqueued";
    private const string ProcessedKey = "workbench:metrics:jobs_processed";

    private IDatabase Db => multiplexer.GetDatabase();

    public Task RecordEnqueueAsync(CancellationToken cancellationToken = default) =>
        Db.StringIncrementAsync(EnqueuedKey);

    public Task RecordProcessedAsync(CancellationToken cancellationToken = default) =>
        Db.StringIncrementAsync(ProcessedKey);

    public async Task<long> GetEnqueueTotalAsync(CancellationToken cancellationToken = default)
    {
        var v = await Db.StringGetAsync(EnqueuedKey).ConfigureAwait(false);
        return v.HasValue ? (long)v : 0;
    }

    public async Task<long> GetProcessedTotalAsync(CancellationToken cancellationToken = default)
    {
        var v = await Db.StringGetAsync(ProcessedKey).ConfigureAwait(false);
        return v.HasValue ? (long)v : 0;
    }
}
