using System.Text.Json;
using Microsoft.Extensions.Logging;
using RabbitMQ.Client;
using Workbench.Application.Abstractions;
using Workbench.Domain;

namespace Workbench.Infrastructure.Messaging;

public sealed class RabbitMqJobQueuePublisher(RabbitMqBus bus, ILogger<RabbitMqJobQueuePublisher> logger) : IJobQueuePublisher
{
    public async Task PublishJobAsync(JobEnvelope envelope, CancellationToken cancellationToken)
    {
        await using var channel = await bus.Connection.CreateChannelAsync(cancellationToken: cancellationToken)
            .ConfigureAwait(false);
        var body = JsonSerializer.SerializeToUtf8Bytes(envelope, JobEnvelopeJson.Options);
        var props = new BasicProperties { Persistent = true };

        await channel
            .BasicPublishAsync(
                exchange: RabbitMqNames.Exchange,
                routingKey: RabbitMqNames.RoutingKey,
                mandatory: false,
                basicProperties: props,
                body: body,
                cancellationToken: cancellationToken)
            .ConfigureAwait(false);

        logger.LogInformation(
            "Published job {JobId} to exchange {Exchange} routing key {RoutingKey}",
            envelope.JobId,
            RabbitMqNames.Exchange,
            RabbitMqNames.RoutingKey);
    }
}
