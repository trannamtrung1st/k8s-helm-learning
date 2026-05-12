import type { FormEvent } from 'react'
import { Spinner } from '../ToastStack'
import { formatPeakMiB } from '../utils/format'

type SyncResult = {
  elapsedMs: number
  peakWorkingSetBytes: number
  processAvgCpuPercent: number
}

type Props = {
  durationSec: number
  cpuPercent: number
  memoryMb: number
  memoryTouch: boolean
  forceGcAfterRun: boolean
  enqueueBusy: boolean
  syncBusy: boolean
  error: string | null
  syncResult: SyncResult | null
  onDurationChange: (value: number) => void
  onCpuChange: (value: number) => void
  onMemoryChange: (value: number) => void
  onMemoryTouchChange: (value: boolean) => void
  onForceGcChange: (value: boolean) => void
  onSubmit: (e: FormEvent) => void
  onSyncRun: () => void
}

export function NewJobCard(props: Props) {
  const {
    durationSec,
    cpuPercent,
    memoryMb,
    memoryTouch,
    forceGcAfterRun,
    enqueueBusy,
    syncBusy,
    error,
    syncResult,
    onDurationChange,
    onCpuChange,
    onMemoryChange,
    onMemoryTouchChange,
    onForceGcChange,
    onSubmit,
    onSyncRun,
  } = props

  return (
    <section className="flex h-full flex-col">
      <h2 className="mb-4 text-sm font-medium uppercase tracking-wide text-slate-400">
        New job
      </h2>
      <form
        onSubmit={onSubmit}
        className="flex h-full flex-col space-y-4 rounded-lg border border-slate-700 bg-slate-900/70 p-5"
      >
        <fieldset
          disabled={enqueueBusy || syncBusy}
          className="space-y-4 disabled:opacity-80"
        >
          <label className="block text-sm">
            <span className="font-medium text-slate-200">Duration (sec)</span>
            <input
              type="number"
              min={1}
              max={300}
              value={durationSec}
              onChange={(e) => onDurationChange(Number(e.target.value))}
              className="mt-1 w-full rounded border border-slate-600 bg-slate-950 px-3 py-2 text-slate-50 focus-visible:border-violet-400 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-violet-400/90 focus-visible:ring-offset-2 focus-visible:ring-offset-slate-950"
            />
          </label>
          <label className="block text-sm">
            <span className="font-medium text-slate-200">CPU %</span>
            <input
              type="number"
              min={0}
              max={100}
              value={cpuPercent}
              onChange={(e) => onCpuChange(Number(e.target.value))}
              className="mt-1 w-full rounded border border-slate-600 bg-slate-950 px-3 py-2 text-slate-50 focus-visible:border-violet-400 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-violet-400/90 focus-visible:ring-offset-2 focus-visible:ring-offset-slate-950"
            />
          </label>
          <label className="block text-sm">
            <span className="font-medium text-slate-200">Memory (MB)</span>
            <input
              type="number"
              min={0}
              max={1024}
              value={memoryMb}
              onChange={(e) => onMemoryChange(Number(e.target.value))}
              className="mt-1 w-full rounded border border-slate-600 bg-slate-950 px-3 py-2 text-slate-50 focus-visible:border-violet-400 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-violet-400/90 focus-visible:ring-offset-2 focus-visible:ring-offset-slate-950"
            />
          </label>
          <label className="flex items-center gap-2 text-sm text-slate-200">
            <input
              type="checkbox"
              checked={memoryTouch}
              onChange={(e) => onMemoryTouchChange(e.target.checked)}
              className="rounded border-slate-500"
            />
            Touch memory pages (RSS)
          </label>
          <label className="flex items-start gap-2 text-sm text-slate-200">
            <input
              type="checkbox"
              checked={forceGcAfterRun}
              onChange={(e) => onForceGcChange(e.target.checked)}
              className="mt-0.5 rounded border-slate-500"
            />
            <span>
              Force GC after run{' '}
              <span className="block text-xs font-normal text-slate-400">
                Large allocations only: blocking full GC + LOH compaction so RSS
                drops (adds pause at end).
              </span>
            </span>
          </label>
        </fieldset>
        {error ? (
          <p className="text-sm font-medium text-red-300" role="alert">
            {error}
          </p>
        ) : null}
        <div className="flex flex-col gap-3 sm:flex-row sm:flex-wrap">
          <button
            type="submit"
            disabled={enqueueBusy || syncBusy}
            className="inline-flex min-h-10 flex-1 items-center justify-center gap-2 rounded bg-violet-500 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-violet-400 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-violet-300 focus-visible:ring-offset-2 focus-visible:ring-offset-slate-950 disabled:cursor-not-allowed disabled:opacity-60 sm:flex-none"
          >
            {enqueueBusy ? (
              <>
                <Spinner className="h-4 w-4 text-white" />
                Enqueuing…
              </>
            ) : (
              'Enqueue job'
            )}
          </button>
          <button
            type="button"
            disabled={enqueueBusy || syncBusy}
            onClick={onSyncRun}
            className="inline-flex min-h-10 flex-1 items-center justify-center gap-2 rounded border-2 border-violet-400 bg-slate-900 px-4 py-2 text-sm font-semibold text-violet-100 hover:border-violet-300 hover:bg-slate-800 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-violet-300 focus-visible:ring-offset-2 focus-visible:ring-offset-slate-950 disabled:cursor-not-allowed disabled:opacity-60 sm:flex-none"
          >
            {syncBusy ? (
              <>
                <Spinner className="h-4 w-4 text-violet-100" />
                Running sync…
              </>
            ) : (
              'Run sync (HTTP)'
            )}
          </button>
        </div>
        <p className="text-xs leading-relaxed text-slate-400">
          <strong className="font-medium text-slate-300">Enqueue</strong>{' '}
          publishes to the queue for the worker.{' '}
          <strong className="font-medium text-slate-300">Sync</strong> calls{' '}
          <code className="rounded border border-slate-600 bg-slate-800 px-1 py-0.5 text-[0.7rem] text-slate-100">
            POST /v1/work
          </code>{' '}
          and runs load in the API process (no job row, no worker).
        </p>
        {syncResult ? (
          <div className="text-sm text-slate-300" role="status">
            <p>
              Last sync:{' '}
              <span className="font-mono font-medium text-emerald-300">
                {syncResult.elapsedMs.toLocaleString()} ms
              </span>{' '}
              ·{' '}
              <span className="font-mono text-sky-200">
                {formatPeakMiB(syncResult.peakWorkingSetBytes)} peak WS
              </span>{' '}
              ·{' '}
              <span className="font-mono text-amber-100">
                ~{syncResult.processAvgCpuPercent.toFixed(1)}% avg CPU
              </span>{' '}
              <span className="text-slate-500">(API process).</span>
            </p>
          </div>
        ) : null}
      </form>
    </section>
  )
}
