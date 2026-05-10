namespace Workbench.Domain;

public sealed class Job
{
    public Guid Id { get; set; }
    public string Status { get; set; } = "";
    public JobPayload Payload { get; set; } = null!;
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset? StartedAt { get; set; }
    public DateTimeOffset? FinishedAt { get; set; }
    public string? Error { get; set; }

    /// <summary>Wall-clock execution duration of the simulated load (ms), when finished.</summary>
    public long? ExecutionDurationMs { get; set; }

    /// <summary>Peak process working set during the simulated load.</summary>
    public long? PeakWorkingSetBytes { get; set; }

    /// <summary>Approximate average process CPU utilization vs logical processors.</summary>
    public double? ProcessAvgCpuPercent { get; set; }
}
