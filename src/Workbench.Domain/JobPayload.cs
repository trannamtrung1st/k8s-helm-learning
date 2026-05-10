namespace Workbench.Domain;

public sealed class JobPayload
{
    public int DurationSec { get; set; }
    public int CpuPercent { get; set; }
    public int MemoryMb { get; set; }
    public bool MemoryTouch { get; set; }

    /// <summary>
    /// When true and the run used a large object heap allocation, run a blocking full GC with LOH compaction after the buffer is dropped (helps RSS drop in demos; has latency cost).
    /// </summary>
    public bool ForceGcAfterRun { get; set; }
}
