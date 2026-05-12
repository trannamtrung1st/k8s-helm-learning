import type { JobDetail } from '../types'
import { Spinner } from '../ToastStack'
import { formatPeakMiB, shortId } from '../utils/format'

type Props = {
  jobs: JobDetail[]
  loading: boolean
  onSelectJob: (job: JobDetail) => void
  onRefresh: () => void
}

export function RecentJobsSection({ jobs, loading, onSelectJob, onRefresh }: Props) {
  return (
    <section className="mt-8">
      <div className="mb-4 flex items-center justify-between gap-2">
        <h2 className="text-sm font-medium uppercase tracking-wide text-slate-400">
          Recent jobs
        </h2>
        {loading ? <Spinner className="h-4 w-4 text-slate-400" /> : null}
      </div>
      <ul className="grid gap-2 text-sm sm:grid-cols-2 xl:grid-cols-3">
        {loading && jobs.length === 0 ? (
          <li className="rounded border border-dashed border-slate-600 px-3 py-6 text-center text-slate-400 sm:col-span-2 xl:col-span-3">
            Loading…
          </li>
        ) : null}
        {!loading && jobs.length === 0 ? (
          <li className="rounded border border-dashed border-slate-600 px-3 py-6 text-center text-slate-400 sm:col-span-2 xl:col-span-3">
            No jobs yet.
          </li>
        ) : null}
        {jobs.map((job) => (
          <li key={job.id}>
            <button
              type="button"
              onClick={() => onSelectJob(job)}
              className="h-full w-full rounded border border-slate-700 bg-slate-900/60 px-3 py-2 text-left hover:border-slate-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-violet-400 focus-visible:ring-offset-2 focus-visible:ring-offset-slate-950"
            >
              <div className="truncate font-mono text-xs text-slate-300">
                {shortId(job.id)}
              </div>
              <div className="font-medium text-slate-100">{job.status}</div>
              {job.executionDurationMs != null &&
              job.peakWorkingSetBytes != null &&
              job.processAvgCpuPercent != null &&
              job.status === 'succeeded' ? (
                <div className="mt-1 font-mono text-[0.65rem] text-slate-400">
                  {job.executionDurationMs.toLocaleString()} ms ·{' '}
                  {formatPeakMiB(job.peakWorkingSetBytes)} · ~
                  {job.processAvgCpuPercent.toFixed(0)}% CPU
                </div>
              ) : null}
            </button>
          </li>
        ))}
      </ul>
      <button
        type="button"
        disabled={loading}
        onClick={onRefresh}
        className="mt-4 inline-flex items-center gap-2 rounded text-xs font-medium text-slate-400 underline decoration-slate-500 underline-offset-2 hover:text-slate-200 hover:decoration-slate-300 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-violet-400 focus-visible:ring-offset-2 focus-visible:ring-offset-slate-950 disabled:cursor-not-allowed disabled:no-underline disabled:opacity-50"
      >
        {loading ? <Spinner className="h-3.5 w-3.5" /> : null}
        Refresh list
      </button>
    </section>
  )
}
