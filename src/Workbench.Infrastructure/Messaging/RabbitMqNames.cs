namespace Workbench.Infrastructure.Messaging;

internal static class RabbitMqNames
{
    internal const string Exchange = "workbench.jobs";
    internal const string Queue = "workbench.jobs.q";
    internal const string RoutingKey = "job";
}
