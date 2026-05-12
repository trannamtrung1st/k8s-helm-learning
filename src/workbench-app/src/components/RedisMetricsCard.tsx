import type { JobMetrics } from '../types'
import { Spinner } from '../ToastStack'

type Props = {
  metrics: JobMetrics | null
  loading: boolean
}

export function RedisMetricsCard({ metrics, loading }: Props) {
  return (
    <section className="flex h-full flex-col">
      <h2 className="mb-4 text-sm font-medium uppercase tracking-wide text-slate-400">
        Redis metrics
      </h2>
      <div className="flex h-full flex-col rounded-lg border border-slate-700 bg-slate-900/70 p-4">
        {loading && !metrics ? (
          <div className="flex items-center gap-2 text-sm text-slate-400">
            <Spinner className="h-4 w-4 text-slate-400" />
            Loading…
          </div>
        ) : (
          <dl className="grid grid-cols-2 gap-x-2 gap-y-1 text-xs">
            <dt className="text-slate-400">Enqueued</dt>
            <dd className="text-right font-mono text-emerald-300">
              {(metrics?.jobsEnqueuedTotal ?? 0).toLocaleString()}
            </dd>
            <dt className="text-slate-400">Processed</dt>
            <dd className="text-right font-mono text-sky-200">
              {(metrics?.jobsProcessedTotal ?? 0).toLocaleString()}
            </dd>
          </dl>
        )}
      </div>
    </section>
  )
}
