namespace Workbench.Infrastructure.Messaging;

/// <summary>
/// <paramref name="ConsumerConcurrency"/> independent consumer channels competing on the job queue — each channel processes one delivery at a time.
/// Set <paramref name="PrefetchPerConsumer"/> per-channel prefetch (applied with global: false Basic.QoS).
/// </summary>
public sealed record RabbitMqSettings(
    string UriString,
    int ConsumerConcurrency = 4,
    int PrefetchPerConsumer = 10);
