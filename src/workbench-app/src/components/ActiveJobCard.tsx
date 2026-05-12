import type { JobDetail } from '../types'
import { Spinner } from '../ToastStack'
import { fmtWhen, formatPeakMiB, shortId } from '../utils/format'

const terminal = new Set(['succeeded', 'failed'])

type Props = {
  activeId: string | null
  activeJob: JobDetail | null
  activePolling: boolean
}

export function ActiveJobCard({ activeId, activeJob, activePolling }: Props) {
  return (
    <section className="flex h-full flex-col">
      <h2 className="mb-4 text-sm font-medium uppercase tracking-wide text-slate-400">
        Active job
      </h2>
      {!activeId ? (
        <div className="h-full rounded-lg border border-slate-700 bg-slate-900/70 p-4 text-sm text-slate-400">
          None — submit a job above.
        </div>
      ) : !activeJob ? (
        <div className="flex h-full items-center gap-2 rounded-lg border border-slate-700 bg-slate-900/70 p-4 text-sm text-slate-300">
          <Spinner className="h-4 w-4 text-violet-300" />
          <span>Loading job {shortId(activeId)}…</span>
        </div>
      ) : (
        <div className="h-full space-y-4 rounded-lg border border-slate-700 bg-slate-900/70 p-4 text-sm">
          <dl className="space-y-2">
            <div className="flex justify-between gap-4">
              <dt className="text-slate-400">Id</dt>
              <dd className="truncate font-mono text-xs text-slate-200">
                {activeJob.id}
              </dd>
            </div>
            <div className="flex justify-between gap-4">
              <dt className="text-slate-400">Status</dt>
              <dd className="flex items-center gap-2 font-medium text-violet-200">
                {activePolling ? (
                  <Spinner className="h-3.5 w-3.5 shrink-0 text-violet-300" />
                ) : null}
                <span
                  className={
                    terminal.has(activeJob.status)
                      ? activeJob.status === 'succeeded'
                        ? 'text-emerald-300'
                        : 'text-red-300'
                      : undefined
                  }
                >
                  {activeJob.status}
                </span>
              </dd>
            </div>
            <div className="flex justify-between gap-4">
              <dt className="text-slate-400">Queued</dt>
              <dd className="text-right text-slate-300">
                {fmtWhen(activeJob.createdAt)}
              </dd>
            </div>
            <div className="flex justify-between gap-4">
              <dt className="text-slate-400">Started</dt>
              <dd className="text-right text-slate-300">
                {fmtWhen(activeJob.startedAt)}
              </dd>
            </div>
            <div className="flex justify-between gap-4">
              <dt className="text-slate-400">Finished</dt>
              <dd className="text-right text-slate-300">
                {fmtWhen(activeJob.finishedAt)}
              </dd>
            </div>
            {activeJob.error ? (
              <div className="pt-2">
                <dt className="text-slate-400">Error</dt>
                <dd className="mt-1 font-mono text-xs text-red-300">
                  {activeJob.error}
                </dd>
              </div>
            ) : null}
          </dl>

          <div className="border-t border-slate-700 pt-3">
            <h3 className="mb-2 text-[0.65rem] font-semibold uppercase tracking-wide text-slate-400">
              Scheduled workload
            </h3>
            <dl className="grid grid-cols-2 gap-x-3 gap-y-1 text-xs text-slate-200">
              <dt className="text-slate-400">Duration</dt>
              <dd>{activeJob.payload.durationSec}s</dd>
              <dt className="text-slate-400">CPU (target)</dt>
              <dd>{activeJob.payload.cpuPercent}%</dd>
              <dt className="text-slate-400">Memory</dt>
              <dd>{activeJob.payload.memoryMb} MiB</dd>
              <dt className="text-slate-400">Touch pages</dt>
              <dd>{activeJob.payload.memoryTouch ? 'yes' : 'no'}</dd>
              <dt className="text-slate-400">Force GC after</dt>
              <dd>{activeJob.payload.forceGcAfterRun ? 'yes' : 'no'}</dd>
            </dl>
          </div>

          {terminal.has(activeJob.status) &&
          activeJob.status === 'succeeded' &&
          activeJob.executionDurationMs != null &&
          activeJob.peakWorkingSetBytes != null &&
          activeJob.processAvgCpuPercent != null ? (
            <div className="border-t border-slate-700 pt-3">
              <h3 className="mb-2 text-[0.65rem] font-semibold uppercase tracking-wide text-slate-400">
                Measured on worker process
              </h3>
              <dl className="grid grid-cols-2 gap-x-3 gap-y-1 text-xs text-slate-200">
                <dt className="text-slate-400">Runtime</dt>
                <dd className="font-mono text-emerald-300">
                  {activeJob.executionDurationMs.toLocaleString()} ms
                </dd>
                <dt className="text-slate-400">Peak working set</dt>
                <dd className="font-mono text-sky-200">
                  {formatPeakMiB(activeJob.peakWorkingSetBytes)}
                </dd>
                <dt className="col-span-2 text-slate-400">
                  Avg CPU
                  <span className="ml-1 font-normal text-slate-500">
                    (vs logical cores)
                  </span>
                </dt>
                <dd className="col-span-2 font-mono text-amber-100">
                  {activeJob.processAvgCpuPercent.toFixed(1)}%
                </dd>
              </dl>
              <p className="mt-2 text-[0.65rem] leading-relaxed text-slate-500">
                Synthetic spin/sleep mimics roughly the requested CPU%. Average CPU
                divides process kernel+user time by wall time × core count.
              </p>
            </div>
          ) : null}
        </div>
      )}
    </section>
  )
}
