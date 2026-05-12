using Microsoft.Extensions.Diagnostics.HealthChecks;
using StackExchange.Redis;

namespace Workbench.Infrastructure.Redis;

public sealed class RedisPingHealthCheck(IConnectionMultiplexer multiplexer) : IHealthCheck
{
    public async Task<HealthCheckResult> CheckHealthAsync(
        HealthCheckContext context,
        CancellationToken cancellationToken = default)
    {
        try
        {
            await multiplexer.GetDatabase().PingAsync().ConfigureAwait(false);
            return HealthCheckResult.Healthy();
        }
        catch (Exception ex)
        {
            return HealthCheckResult.Unhealthy(exception: ex);
        }
    }
}
