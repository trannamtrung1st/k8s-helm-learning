using System.Diagnostics;
using System.Runtime;
using Microsoft.Extensions.Logging;

namespace Workbench.Domain;

/// <summary>
/// 100 ms wall-clock slices: spin for cpuPercent of each slice, sleep the remainder; hold memoryMb allocation for the full run.
/// </summary>
public static class LoadSimulator
{
    private const int SliceMs = 100;

    /// <summary>
    /// Arrays of this size or larger go on the large object heap; without compaction they may stay reserved in the process
    /// long after the last reference disappears, so RSS does not drop until a full GC compacts the LOH.
    /// </summary>
    private const int LargeObjectHeapThresholdBytes = 85_000;

    public static Task<LoadSimulationMetrics> RunAsync(
        JobPayload payload,
        CancellationToken cancellationToken = default) =>
        RunAsync(payload, logger: null, cancellationToken);

    public static async Task<LoadSimulationMetrics> RunAsync(
        JobPayload payload,
        ILogger? logger,
        CancellationToken cancellationToken)
    {
        using var process = Process.GetCurrentProcess();

        process.Refresh();
        var cpuStart = process.TotalProcessorTime;
        long peakWs = process.WorkingSet64;

        var totalMs = payload.DurationSec * 1000L;
        var allocBytes = payload.MemoryMb > 0 ? checked(payload.MemoryMb * 1024 * 1024) : 0;
        byte[]? buffer = allocBytes > 0 ? GC.AllocateArray<byte>(allocBytes, pinned: false) : null;

        logger?.LogInformation(
            "Load simulation starting: DurationSec={DurationSec}, CpuPercent={CpuPercent}, MemoryMb={MemoryMb}, MemoryTouch={MemoryTouch}, ForceGcAfterRun={ForceGc}, AllocBytes={AllocBytes}",
            payload.DurationSec,
            payload.CpuPercent,
            payload.MemoryMb,
            payload.MemoryTouch,
            payload.ForceGcAfterRun,
            allocBytes);

        process.Refresh();
        peakWs = Math.Max(peakWs, process.WorkingSet64);

        var wallClock = Stopwatch.StartNew();
        try
        {
            var sw = Stopwatch.StartNew();

            while (sw.ElapsedMilliseconds < totalMs)
            {
                cancellationToken.ThrowIfCancellationRequested();

                var spinMs = SliceMs * payload.CpuPercent / 100;
                var sleepMs = SliceMs - spinMs;
                SpinMilliseconds(spinMs);

                if (payload.MemoryTouch && buffer is { Length: > 0 })
                    TouchBuffer(buffer);

                if (sleepMs > 0)
                    await Task.Delay(sleepMs, cancellationToken).ConfigureAwait(false);

                process.Refresh();
                peakWs = Math.Max(peakWs, process.WorkingSet64);
            }
        }
        finally
        {
            buffer = null;

            if (payload.ForceGcAfterRun && allocBytes >= LargeObjectHeapThresholdBytes)
            {
                logger?.LogInformation(
                    "Forcing full GC with LOH compaction (alloc {AllocBytes} bytes >= LOH threshold)",
                    allocBytes);
                GCSettings.LargeObjectHeapCompactionMode = GCLargeObjectHeapCompactionMode.CompactOnce;
                GC.Collect(GC.MaxGeneration, GCCollectionMode.Forced, blocking: true, compacting: true);
            }
        }

        wallClock.Stop();
        process.Refresh();
        peakWs = Math.Max(peakWs, process.WorkingSet64);

        var wallMs = wallClock.ElapsedMilliseconds;
        process.Refresh();
        var cpuElapsedMs = Math.Max(
            (process.TotalProcessorTime - cpuStart).TotalMilliseconds,
            0.0);

        var logical = Math.Max(Environment.ProcessorCount, 1);
        var avgCpu = wallMs > 0 ? cpuElapsedMs / (wallMs * logical) * 100.0 : 0.0;

        logger?.LogInformation(
            "Load simulation finished: DurationSec={DurationSec}, WallClockMs={WallClockMs}, PeakWorkingSetBytes={PeakWs}, ProcessAvgCpuPercent={AvgCpu:F2}",
            payload.DurationSec,
            wallMs,
            peakWs,
            avgCpu);

        return new LoadSimulationMetrics(WallClockMs: wallMs, PeakWorkingSetBytes: peakWs, ProcessAvgCpuPercent: avgCpu);
    }

    private static void SpinMilliseconds(int milliseconds)
    {
        if (milliseconds <= 0)
            return;

        var end = Stopwatch.GetTimestamp() + milliseconds * Stopwatch.Frequency / 1000;
        while (Stopwatch.GetTimestamp() < end)
        {
            // tight spin
        }
    }

    private static void TouchBuffer(byte[] buffer)
    {
        for (var i = 0; i < buffer.Length; i += 4096)
            buffer[i] = (byte)(buffer[i] ^ 1);
    }
}
