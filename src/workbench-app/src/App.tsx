import { useCallback, useEffect, useRef, useState, type FormEvent } from 'react'
import * as api from './api'
import type { JobDetail, JobPayload } from './types'
import { Spinner, ToastStack, useToasts } from './ToastStack'

const pollMs = 1500
const terminal = new Set(['succeeded', 'failed'])

function formatPeakMiB(bytes: number) {
  return `${(bytes / (1024 * 1024)).toFixed(1)} MiB`
}

function fmtWhen(iso: string | null) {
  return iso ? new Date(iso).toLocaleString() : '—'
}

function shortId(id: string) {
  return `${id.slice(0, 8)}…`
}

function App() {
  const { toasts, push: pushToast, dismiss: dismissToast } = useToasts()

  const [durationSec, setDurationSec] = useState(30)
  const [cpuPercent, setCpuPercent] = useState(50)
  const [memoryMb, setMemoryMb] = useState(128)
  const [memoryTouch, setMemoryTouch] = useState(true)
  const [forceGcAfterRun, setForceGcAfterRun] = useState(false)
  const [enqueueBusy, setEnqueueBusy] = useState(false)
  const [syncBusy, setSyncBusy] = useState(false)
  const [syncResult, setSyncResult] = useState<{
    elapsedMs: number
    peakWorkingSetBytes: number
    processAvgCpuPercent: number
  } | null>(null)
  const [error, setError] = useState<string | null>(null)

  const [activeId, setActiveId] = useState<string | null>(null)
  const [activeJob, setActiveJob] = useState<JobDetail | null>(null)
  const statusBeforePollRef = useRef<string | null>(null)

  const [recent, setRecent] = useState<JobDetail[]>([])
  const [listLoading, setListLoading] = useState(true)

  const refreshRecent = useCallback(async () => {
    setListLoading(true)
    try {
      setRecent(await api.listJobs(15))
    } catch {
      pushToast('error', 'Could not load recent jobs.')
    } finally {
      setListLoading(false)
    }
  }, [pushToast])

  useEffect(() => {
    void refreshRecent()
  }, [refreshRecent])

  useEffect(() => {
    if (!activeId) {
      setActiveJob(null)
      statusBeforePollRef.current = null
      return
    }

    let cancelled = false
    statusBeforePollRef.current = null

    const tick = async () => {
      try {
        const job = await api.getJob(activeId)
        if (cancelled) return

        if (job) {
          const prev = statusBeforePollRef.current
          statusBeforePollRef.current = job.status

          if (
            prev !== null &&
            (prev === 'queued' || prev === 'running') &&
            terminal.has(job.status)
          ) {
            if (job.status === 'succeeded') {
              pushToast('success', `Job ${shortId(job.id)} finished successfully.`)
            } else {
              pushToast(
                'error',
                job.error
                  ? `Job ${shortId(job.id)} failed: ${job.error}`
                  : `Job ${shortId(job.id)} failed.`,
              )
            }
          }
        }

        setActiveJob(job)
        if (job && terminal.has(job.status)) {
          void refreshRecent()
        }
      } catch (e) {
        if (!cancelled) {
          const msg = e instanceof Error ? e.message : 'Poll failed'
          setError(msg)
          pushToast('error', msg)
        }
      }
    }

    void tick()
    const id = window.setInterval(() => void tick(), pollMs)
    return () => {
      cancelled = true
      window.clearInterval(id)
    }
  }, [activeId, refreshRecent, pushToast])

  const buildPayload = useCallback(
    (): JobPayload => ({
      durationSec,
      cpuPercent,
      memoryMb,
      memoryTouch,
      forceGcAfterRun,
    }),
    [durationSec, cpuPercent, memoryMb, memoryTouch, forceGcAfterRun],
  )

  async function onSyncRun() {
    setError(null)
    setSyncResult(null)
    setSyncBusy(true)
    try {
      const result = await api.runSyncWork(buildPayload())
      setSyncResult({
        elapsedMs: result.elapsedMs,
        peakWorkingSetBytes: result.peakWorkingSetBytes,
        processAvgCpuPercent: result.processAvgCpuPercent,
      })
      pushToast(
        'success',
        `Sync run finished in ${result.elapsedMs.toLocaleString()} ms · peak RSS ${formatPeakMiB(result.peakWorkingSetBytes)} · avg CPU ~${result.processAvgCpuPercent.toFixed(1)}%.`,
      )
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Sync run failed'
      setError(msg)
      pushToast('error', msg)
    } finally {
      setSyncBusy(false)
    }
  }

  async function onSubmit(e: FormEvent) {
    e.preventDefault()
    setError(null)
    setEnqueueBusy(true)
    try {
      const created = await api.createJob(buildPayload())
      setActiveId(created.id)
      setActiveJob(null)
      statusBeforePollRef.current = null
      pushToast('info', `Job ${shortId(created.id)} queued.`)
      void refreshRecent()
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Request failed'
      setError(msg)
      pushToast('error', msg)
    } finally {
      setEnqueueBusy(false)
    }
  }

  const apiLabel =
    import.meta.env.VITE_API_BASE_URL ?? 'http://localhost:8080'

  const activePolling =
    Boolean(activeId) &&
    activeJob !== null &&
    !terminal.has(activeJob.status)

  return (
    <div className="min-h-screen bg-slate-950 text-slate-50">
      <ToastStack toasts={toasts} onDismiss={dismissToast} />
      <div className="mx-auto max-w-3xl px-4 py-10">
        <header className="mb-8 border-b border-slate-700 pb-6">
          <h1 className="text-2xl font-semibold tracking-tight text-white">
            Workbench
          </h1>
          <p className="mt-1 text-sm text-slate-300">
            Synthetic load jobs · API{' '}
            <code className="rounded border border-slate-600 bg-slate-800 px-1.5 py-0.5 text-xs text-slate-100">
              {apiLabel}
            </code>
          </p>
        </header>

        <div className="grid gap-8 md:grid-cols-[1fr,280px]">
          <section>
            <h2 className="mb-4 text-sm font-medium uppercase tracking-wide text-slate-400">
              New job
            </h2>
            <form
              onSubmit={onSubmit}
              className="space-y-4 rounded-lg border border-slate-700 bg-slate-900/70 p-5"
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
                    onChange={(e) => setDurationSec(Number(e.target.value))}
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
                    onChange={(e) => setCpuPercent(Number(e.target.value))}
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
                    onChange={(e) => setMemoryMb(Number(e.target.value))}
                    className="mt-1 w-full rounded border border-slate-600 bg-slate-950 px-3 py-2 text-slate-50 focus-visible:border-violet-400 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-violet-400/90 focus-visible:ring-offset-2 focus-visible:ring-offset-slate-950"
                  />
                </label>
                <label className="flex items-center gap-2 text-sm text-slate-200">
                  <input
                    type="checkbox"
                    checked={memoryTouch}
                    onChange={(e) => setMemoryTouch(e.target.checked)}
                    className="rounded border-slate-500"
                  />
                  Touch memory pages (RSS)
                </label>
                <label className="flex items-start gap-2 text-sm text-slate-200">
                  <input
                    type="checkbox"
                    checked={forceGcAfterRun}
                    onChange={(e) => setForceGcAfterRun(e.target.checked)}
                    className="mt-0.5 rounded border-slate-500"
                  />
                  <span>
                    Force GC after run{' '}
                    <span className="block text-xs font-normal text-slate-400">
                      Large allocations only: blocking full GC + LOH compaction so RSS drops (adds pause at end).
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
                  onClick={() => void onSyncRun()}
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

            <div className="mt-8">
              <h2 className="mb-3 text-sm font-medium uppercase tracking-wide text-slate-400">
                Active job
              </h2>
              {!activeId ? (
                <p className="text-sm text-slate-400">None — submit a job above.</p>
              ) : !activeJob ? (
                <div className="flex items-center gap-2 rounded-lg border border-slate-700 bg-slate-900/70 p-4 text-sm text-slate-300">
                  <Spinner className="h-4 w-4 text-violet-300" />
                  <span>Loading job {shortId(activeId)}…</span>
                </div>
              ) : (
                <div className="space-y-4 rounded-lg border border-slate-700 bg-slate-900/70 p-4 text-sm">
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
                        Synthetic spin/sleep mimics roughly the requested CPU%.
                        Average CPU divides process kernel+user time by wall time ×
                        core count.
                      </p>
                    </div>
                  ) : null}
                </div>
              )}
            </div>
          </section>

          <aside>
            <div className="mb-4 flex items-center justify-between gap-2">
              <h2 className="text-sm font-medium uppercase tracking-wide text-slate-400">
                Recent jobs
              </h2>
              {listLoading ? (
                <Spinner className="h-4 w-4 text-slate-400" />
              ) : null}
            </div>
            <ul className="space-y-2 text-sm">
              {listLoading && recent.length === 0 ? (
                <li className="rounded border border-dashed border-slate-600 px-3 py-6 text-center text-slate-400">
                  Loading…
                </li>
              ) : null}
              {!listLoading && recent.length === 0 ? (
                <li className="rounded border border-dashed border-slate-600 px-3 py-6 text-center text-slate-400">
                  No jobs yet.
                </li>
              ) : null}
              {recent.map((j) => (
                <li key={j.id}>
                  <button
                    type="button"
                    onClick={() => {
                      setActiveId(j.id)
                      setActiveJob(j)
                      setError(null)
                    }}
                    className="w-full rounded border border-slate-700 bg-slate-900/60 px-3 py-2 text-left hover:border-slate-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-violet-400 focus-visible:ring-offset-2 focus-visible:ring-offset-slate-950"
                  >
                    <div className="truncate font-mono text-xs text-slate-300">
                      {j.id.slice(0, 8)}…
                    </div>
                    <div className="font-medium text-slate-100">{j.status}</div>
                    {j.executionDurationMs != null &&
                    j.peakWorkingSetBytes != null &&
                    j.processAvgCpuPercent != null &&
                    j.status === 'succeeded' ? (
                      <div className="mt-1 font-mono text-[0.65rem] text-slate-400">
                        {j.executionDurationMs.toLocaleString()} ms ·{' '}
                        {formatPeakMiB(j.peakWorkingSetBytes)} · ~
                        {j.processAvgCpuPercent.toFixed(0)}% CPU
                      </div>
                    ) : null}
                  </button>
                </li>
              ))}
            </ul>
            <button
              type="button"
              disabled={listLoading}
              onClick={() => void refreshRecent()}
              className="mt-4 inline-flex items-center gap-2 rounded text-xs font-medium text-slate-400 underline decoration-slate-500 underline-offset-2 hover:text-slate-200 hover:decoration-slate-300 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-violet-400 focus-visible:ring-offset-2 focus-visible:ring-offset-slate-950 disabled:cursor-not-allowed disabled:no-underline disabled:opacity-50"
            >
              {listLoading ? (
                <Spinner className="h-3.5 w-3.5" />
              ) : null}
              Refresh list
            </button>
          </aside>
        </div>
      </div>
    </div>
  )
}

export default App
