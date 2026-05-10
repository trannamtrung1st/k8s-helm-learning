using Workbench.Domain;

namespace Workbench.Application;

public sealed class WorkbenchOptions
{
    public const string SectionName = "Workbench";

    public int DurationSecMin { get; set; } = 1;
    public int DurationSecMax { get; set; } = 300;
    public int CpuPercentMin { get; set; } = 0;
    public int CpuPercentMax { get; set; } = 100;
    public int MemoryMbMin { get; set; } = 0;
    public int MemoryMbMax { get; set; } = 1024;

    public WorkbenchLimits ToLimits() => new(
        DurationSecMin,
        DurationSecMax,
        CpuPercentMin,
        CpuPercentMax,
        MemoryMbMin,
        MemoryMbMax);
}
