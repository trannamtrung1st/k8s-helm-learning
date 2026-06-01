using System.Collections.Immutable;
using System.Text.Json;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using RabbitMQ.Client;
using RabbitMQ.Client.Events;
using Workbench.Application.Abstractions;
using Workbench.Domain;

namespace Workbench.Infrastructure.Messaging;

internal sealed class JobQueueConsumerHostedService(
    RabbitMqBus bus,
    RabbitMqSettings rabbitSettings,
    IServiceScopeFactory scopeFactory,
    ILogger<JobQueueConsumerHostedService> logger) : IHostedService, IAsyncDisposable
{
    private readonly CancellationTokenSource _shutdown = new();
    private readonly object _channelLock = new();
    private Task? _runTask;

    /// <remarks>Disposed on stop; concurrent consumers mean one dedicated channel each.</remarks>
    private ImmutableArray<IChannel> _consumerChannels;

    public Task StartAsync(CancellationToken cancellationToken)
    {
        _runTask = RunAsync(cancellationToken);
        _ = LogRunOutcomeAsync(_runTask);
        return Task.CompletedTask;
    }

    private async Task LogRunOutcomeAsync(Task task)
    {
        try
        {
            await task.ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogError(ex, "Job queue consumer stopped unexpectedly.");
        }
    }

    private async Task RunAsync(CancellationToken appStopping)
    {
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(appStopping, _shutdown.Token);
        var ct = linked.Token;

        var concurrency = Math.Clamp(rabbitSettings.ConsumerConcurrency, min: 1, max: 256);
        var prefetchRaw = rabbitSettings.PrefetchPerConsumer;
        var prefetch = (ushort)Math.Clamp(prefetchRaw, min: 1, max: ushort.MaxValue);

        var cleanup = new List<(IChannel Channel, AsyncEventingBasicConsumer Consumer, AsyncEventHandler<BasicDeliverEventArgs> Handler)>(
            concurrency);
        List<IChannel> created = [];

        try
        {
            for (var i = 0; i < concurrency; i++)
            {
                IChannel ch;
                try
                {
                    ch = await bus.Connection.CreateChannelAsync(cancellationToken: ct).ConfigureAwait(false);
                }
                catch (ObjectDisposedException)
                {
                    logger.LogWarning("RabbitMQ connection disposed before consumer could start.");
                    return;
                }

                await ch.BasicQosAsync(prefetchSize: 0, prefetchCount: prefetch, global: false, ct)
                    .ConfigureAwait(false);
                created.Add(ch);

                var consumer = new AsyncEventingBasicConsumer(ch);
                var channelForHandler = ch;
                AsyncEventHandler<BasicDeliverEventArgs> receivedHandler =
                    async (_, ea) => await HandleDeliveryAsync(channelForHandler, ea, ct).ConfigureAwait(false);
                consumer.ReceivedAsync += receivedHandler;

                await ch.BasicConsumeAsync(RabbitMqNames.Queue, autoAck: false, consumer, ct)
                    .ConfigureAwait(false);

                cleanup.Add((ch, consumer, receivedHandler));
            }

            lock (_channelLock)
                _consumerChannels = [.. created];
            created = [];

            logger.LogInformation(
                "Consuming from queue {Queue} with concurrency {Concurrency} and prefetch-per-consumer {Prefetch}",
                RabbitMqNames.Queue,
                concurrency,
                prefetch);

            try
            {
                await Task.Delay(Timeout.InfiniteTimeSpan, ct).ConfigureAwait(false);
            }
            catch (OperationCanceledException) when (ct.IsCancellationRequested)
            {
            }
            finally
            {
                foreach (var (_, consumer, receivedHandler) in cleanup)
                    consumer.ReceivedAsync -= receivedHandler;
                cleanup.Clear();
            }
        }
        finally
        {
            foreach (var ch in created)
            {
                try
                {
                    await ch.DisposeAsync().ConfigureAwait(false);
                }
                catch (Exception ex)
                {
                    logger.LogDebug(ex, "Disposing RabbitMQ consumer channel during failed startup.");
                }
            }
        }
    }

    private async Task HandleDeliveryAsync(IChannel channel, BasicDeliverEventArgs ea, CancellationToken ct)
    {
        JobEnvelope? envelope;
        try
        {
            envelope = JsonSerializer.Deserialize<JobEnvelope>(ea.Body.Span, JobEnvelopeJson.Options);
        }
        catch (JsonException ex)
        {
            logger.LogWarning(ex, "Invalid job envelope JSON; dead-lettering message.");
            await channel.BasicNackAsync(ea.DeliveryTag, multiple: false, requeue: false, ct).ConfigureAwait(false);
            return;
        }

        if (envelope is null)
        {
            await channel.BasicNackAsync(ea.DeliveryTag, multiple: false, requeue: false, ct).ConfigureAwait(false);
            return;
        }

        var id = envelope.JobId;
        logger.LogInformation("Consuming job message {JobId}", id);

        try
        {
            await using var scope = scopeFactory.CreateAsyncScope();
            var executor = scope.ServiceProvider.GetRequiredService<IQueuedJobExecutor>();
            await executor.ExecuteAsync(id, envelope.Payload, ct).ConfigureAwait(false);
            await channel.BasicAckAsync(ea.DeliveryTag, multiple: false, ct).ConfigureAwait(false);
            logger.LogInformation("Finished processing job {JobId}", id);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            logger.LogWarning("Job {JobId} consume cancelled; nacking without requeue.", id);
            await channel.BasicNackAsync(ea.DeliveryTag, multiple: false, requeue: false, CancellationToken.None)
                .ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Job {JobId} failed; nacking without requeue.", id);
            await channel.BasicNackAsync(ea.DeliveryTag, multiple: false, requeue: false, ct).ConfigureAwait(false);
        }
    }

    public async Task StopAsync(CancellationToken cancellationToken)
    {
        _shutdown.Cancel();
        if (_runTask is not null)
        {
            var finished = await Task.WhenAny(_runTask, Task.Delay(TimeSpan.FromSeconds(15), cancellationToken))
                .ConfigureAwait(false);
            if (finished != _runTask)
                logger.LogWarning("Job queue consumer did not stop within timeout.");
        }

        ImmutableArray<IChannel> toDispose;
        lock (_channelLock)
        {
            toDispose = _consumerChannels;
            _consumerChannels = default;
        }

        foreach (var ch in toDispose)
        {
            try
            {
                await ch.DisposeAsync().ConfigureAwait(false);
            }
            catch (Exception ex)
            {
                logger.LogDebug(ex, "Error disposing RabbitMQ consumer channel.");
            }
        }
    }

    public async ValueTask DisposeAsync()
    {
        await StopAsync(default).ConfigureAwait(false);
        _shutdown.Dispose();
    }
}
