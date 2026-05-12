import { useCallback, useEffect, useRef, useState, type FormEvent } from 'react'
import * as api from './api'
import type { JobDetail, JobMetrics, JobPayload } from './types'
import { ToastStack, useToasts } from './ToastStack'
import { ActiveJobCard } from './components/ActiveJobCard'
import { NewJobCard } from './components/NewJobCard'
import { RedisMetricsCard } from './components/RedisMetricsCard'
import { RecentJobsSection } from './components/RecentJobsSection'
import { formatPeakMiB, shortId } from './utils/format'

const POLL_MS = 1500
const terminal = new Set(['succeeded', 'failed'])

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
  const [metrics, setMetrics] = useState<JobMetrics | null>(null)
  const [metricsLoading, setMetricsLoading] = useState(true)

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

  const refreshMetrics = useCallback(async () => {
    try {
      const data = await api.getJobMetrics()
      setMetrics(data)
    } catch {
      // Keep UI non-blocking; errors are surfaced via health/other flows.
    } finally {
      setMetricsLoading(false)
    }
  }, [])

  useEffect(() => {
    let cancelled = false

    const tick = async () => {
      if (cancelled) return
      await refreshMetrics()
    }

    void tick()
    const id = window.setInterval(() => void tick(), 3000)
    return () => {
      cancelled = true
      window.clearInterval(id)
    }
  }, [refreshMetrics])

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
    const id = window.setInterval(() => void tick(), POLL_MS)
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
    import.meta.env.VITE_API_BASE_URL ?? 'http://localhost:8080/api'

  const activePolling =
    Boolean(activeId) &&
    activeJob !== null &&
    !terminal.has(activeJob.status)

  return (
    <div className="min-h-screen bg-slate-950 text-slate-50">
      <ToastStack toasts={toasts} onDismiss={dismissToast} />
      <div className="mx-auto max-w-7xl px-4 py-10">
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

        <div className="grid items-stretch gap-8 xl:grid-cols-3">
          <NewJobCard
            durationSec={durationSec}
            cpuPercent={cpuPercent}
            memoryMb={memoryMb}
            memoryTouch={memoryTouch}
            forceGcAfterRun={forceGcAfterRun}
            enqueueBusy={enqueueBusy}
            syncBusy={syncBusy}
            error={error}
            syncResult={syncResult}
            onDurationChange={setDurationSec}
            onCpuChange={setCpuPercent}
            onMemoryChange={setMemoryMb}
            onMemoryTouchChange={setMemoryTouch}
            onForceGcChange={setForceGcAfterRun}
            onSubmit={onSubmit}
            onSyncRun={() => void onSyncRun()}
          />

          <ActiveJobCard
            activeId={activeId}
            activeJob={activeJob}
            activePolling={activePolling}
          />

          <RedisMetricsCard metrics={metrics} loading={metricsLoading} />
        </div>

        <RecentJobsSection
          jobs={recent}
          loading={listLoading}
          onSelectJob={(job) => {
            setActiveId(job.id)
            setActiveJob(job)
            setError(null)
          }}
          onRefresh={() => void refreshRecent()}
        />
        </div>
      </div>
  )
}

export default App
