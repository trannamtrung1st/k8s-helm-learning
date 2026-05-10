using Workbench.Domain;

namespace Workbench.Application;

public sealed record JobDetailDto(
    Guid Id,
    string Status,
    JobPayload Payload,
    DateTimeOffset CreatedAt,
    DateTimeOffset? StartedAt,
    DateTimeOffset? FinishedAt,
    string? Error,
    long? ExecutionDurationMs,
    long? PeakWorkingSetBytes,
    double? ProcessAvgCpuPercent);
