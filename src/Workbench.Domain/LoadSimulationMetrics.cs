namespace Workbench.Domain;

/// <summary>
/// Measurements gathered while executing <see cref="LoadSimulator"/>.
/// <see cref="ProcessAvgCpuPercent"/> is process CPU averaged over logical processors (0–100 × cores utilization style).
/// </summary>
public sealed record LoadSimulationMetrics(
    long WallClockMs,
    long PeakWorkingSetBytes,
    double ProcessAvgCpuPercent);
