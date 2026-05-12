import type {
  CreateJobResponse,
  JobMetrics,
  JobDetail,
  JobPayload,
  SyncWorkResponse,
  ValidationErrorBody,
} from './types'

const baseUrl = () =>
  (import.meta.env.VITE_API_BASE_URL ?? 'http://localhost:8080/api').replace(/\/$/, '')

async function throwValidationIfNeeded(res: Response): Promise<void> {
  if (res.status !== 400) return
  const body = (await res.json()) as ValidationErrorBody
  const msg = Object.entries(body.details ?? {})
    .map(([k, v]) => `${k}: ${v}`)
    .join('; ')
  throw new Error(msg || body.error || 'Validation failed')
}

export async function createJob(payload: JobPayload): Promise<CreateJobResponse> {
  const res = await fetch(`${baseUrl()}/v1/jobs`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  })
  await throwValidationIfNeeded(res)
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  return (await res.json()) as CreateJobResponse
}

export async function runSyncWork(payload: JobPayload): Promise<SyncWorkResponse> {
  const res = await fetch(`${baseUrl()}/v1/work`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  })
  await throwValidationIfNeeded(res)
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  return (await res.json()) as SyncWorkResponse
}

export async function getJob(id: string): Promise<JobDetail | null> {
  const res = await fetch(`${baseUrl()}/v1/jobs/${id}`)
  if (res.status === 404) return null
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  return (await res.json()) as JobDetail
}

export async function listJobs(limit: number): Promise<JobDetail[]> {
  const res = await fetch(`${baseUrl()}/v1/jobs?limit=${limit}`)
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  return (await res.json()) as JobDetail[]
}

export async function getJobMetrics(): Promise<JobMetrics> {
  const res = await fetch(`${baseUrl()}/v1/metrics`)
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  return (await res.json()) as JobMetrics
}
