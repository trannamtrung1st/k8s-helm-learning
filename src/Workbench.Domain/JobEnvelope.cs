namespace Workbench.Domain;

/// <summary>
/// Message envelope: API publishes, worker consumes (workbench-demo-spec).
/// </summary>
public sealed class JobEnvelope
{
    public Guid JobId { get; set; }
    public JobPayload Payload { get; set; } = null!;
}
