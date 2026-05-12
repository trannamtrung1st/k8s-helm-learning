export function formatPeakMiB(bytes: number) {
  return `${(bytes / (1024 * 1024)).toFixed(1)} MiB`
}

export function fmtWhen(iso: string | null) {
  return iso ? new Date(iso).toLocaleString() : '—'
}

export function shortId(id: string) {
  return `${id.slice(0, 8)}…`
}
