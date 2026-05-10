namespace Workbench.Domain;

/// <summary>
/// Caps for payload validation (from configuration in the application layer).
/// </summary>
public readonly record struct WorkbenchLimits(
    int DurationSecMin,
    int DurationSecMax,
    int CpuPercentMin,
    int CpuPercentMax,
    int MemoryMbMin,
    int MemoryMbMax);
