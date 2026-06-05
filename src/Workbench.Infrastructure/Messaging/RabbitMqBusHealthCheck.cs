using Microsoft.Extensions.Diagnostics.HealthChecks;

namespace Workbench.Infrastructure.Messaging;

public sealed class RabbitMqBusHealthCheck(RabbitMqBus bus) : IHealthCheck
{
    public async Task<HealthCheckResult> CheckHealthAsync(
        HealthCheckContext context,
        CancellationToken cancellationToken = default)
    {
        try
        {
            var connection = bus.Connection;
            if (!connection.IsOpen)
                return HealthCheckResult.Unhealthy("RabbitMQ connection is not open.");

            await using var channel = await connection
                .CreateChannelAsync(cancellationToken: cancellationToken)
                .ConfigureAwait(false);

            return HealthCheckResult.Healthy();
        }
        catch (InvalidOperationException ex)
        {
            return HealthCheckResult.Unhealthy("RabbitMQ is not connected yet.", ex);
        }
        catch (Exception ex)
        {
            return HealthCheckResult.Unhealthy("RabbitMQ health check failed.", ex);
        }
    }
}
