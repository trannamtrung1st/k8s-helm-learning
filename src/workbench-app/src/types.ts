export type JobPayload = {
  durationSec: number
  cpuPercent: number
  memoryMb: number
  memoryTouch: boolean
  /** When true (and allocation is large-object-heap sized), run blocking full GC + LOH compaction after the run. */
  forceGcAfterRun: boolean
}

export type JobDetail = {
  id: string
  status: string
  payload: JobPayload
  createdAt: string
  startedAt: string | null
  finishedAt: string | null
  error: string | null
  /** Wall-clock time spent in worker load simulation (ms), when finished successfully. */
  executionDurationMs: number | null
  peakWorkingSetBytes: number | null
  /** Average process CPU during the simulation (relative to logical processors). */
  processAvgCpuPercent: number | null
}

export type CreateJobResponse = {
  id: string
  status: string
}

export type ValidationErrorBody = {
  error: string
  details: Record<string, string>
}

export type SyncWorkResponse = {
  mode: 'sync'
  elapsedMs: number
  peakWorkingSetBytes: number
  processAvgCpuPercent: number
}

export type JobMetrics = {
  jobsEnqueuedTotal: number
  jobsProcessedTotal: number
}
