using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using RabbitMQ.Client;

namespace Workbench.Infrastructure.Messaging;

public sealed class RabbitMqBus(RabbitMqSettings settings, ILogger<RabbitMqBus> logger) : IHostedService, IAsyncDisposable
{
    private IConnection? _connection;

    public IConnection Connection => _connection
        ?? throw new InvalidOperationException("RabbitMQ is not connected yet.");

    public async Task StartAsync(CancellationToken cancellationToken)
    {
        var factory = new ConnectionFactory { Uri = new Uri(settings.UriString) };
        _connection = await factory.CreateConnectionAsync(cancellationToken).ConfigureAwait(false);
        logger.LogInformation("RabbitMQ connection established.");
    }

    public async Task StopAsync(CancellationToken cancellationToken)
    {
        if (_connection is null)
            return;

        await _connection.DisposeAsync().ConfigureAwait(false);
        _connection = null;
        logger.LogInformation("RabbitMQ connection closed.");
    }

    public async ValueTask DisposeAsync()
    {
        await StopAsync(default).ConfigureAwait(false);
    }
}
