import { useCallback, useEffect, useRef, useState } from 'react'

export type ToastVariant = 'success' | 'error' | 'info'

export type ToastEntry = {
  id: number
  variant: ToastVariant
  message: string
}

export function Spinner({ className = 'h-4 w-4' }: { className?: string }) {
  return (
    <svg
      className={`animate-spin ${className}`}
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
      aria-hidden="true"
    >
      <circle
        className="opacity-25"
        cx="12"
        cy="12"
        r="10"
        stroke="currentColor"
        strokeWidth="4"
      />
      <path
        className="opacity-75"
        fill="currentColor"
        d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
      />
    </svg>
  )
}

const dismissMs = 5200

export function useToasts() {
  const nextId = useRef(0)
  const timeouts = useRef<Map<number, number>>(new Map())
  const [toasts, setToasts] = useState<ToastEntry[]>([])

  const dismiss = useCallback((id: number) => {
    const t = timeouts.current.get(id)
    if (t !== undefined) window.clearTimeout(t)
    timeouts.current.delete(id)
    setToasts((prev) => prev.filter((x) => x.id !== id))
  }, [])

  const push = useCallback(
    (variant: ToastVariant, message: string) => {
      const id = ++nextId.current
      setToasts((prev) => [...prev, { id, variant, message }])
      const handle = window.setTimeout(() => dismiss(id), dismissMs)
      timeouts.current.set(id, handle)
    },
    [dismiss],
  )

  useEffect(
    () => () => {
      timeouts.current.forEach((h) => window.clearTimeout(h))
      timeouts.current.clear()
    },
    [],
  )

  return { toasts, push, dismiss }
}

export function ToastStack({
  toasts,
  onDismiss,
}: {
  toasts: ToastEntry[]
  onDismiss: (id: number) => void
}) {
  if (toasts.length === 0) return null

  return (
    <div
      className="pointer-events-none fixed bottom-4 right-4 z-50 flex max-w-sm flex-col gap-2"
      role="region"
      aria-live="polite"
      aria-label="Notifications"
    >
      {toasts.map((t) => (
        <div
          key={t.id}
          role="status"
          className={[
            'pointer-events-auto flex items-start gap-3 rounded-lg border px-4 py-3 text-sm shadow-lg transition [animation:toast-in_0.22s_ease-out]',
            t.variant === 'success' &&
              'border-emerald-800/80 bg-emerald-950/95 text-emerald-100',
            t.variant === 'error' &&
              'border-red-800/80 bg-red-950/95 text-red-100',
            t.variant === 'info' &&
              'border-violet-800/80 bg-slate-900/95 text-slate-100',
          ]
            .filter(Boolean)
            .join(' ')}
        >
          <span className="min-w-0 flex-1 leading-snug">{t.message}</span>
          <button
            type="button"
            onClick={() => onDismiss(t.id)}
            className="-m-1 shrink-0 rounded p-1 text-current opacity-70 hover:opacity-100"
            aria-label="Dismiss notification"
          >
            ×
          </button>
        </div>
      ))}
    </div>
  )
}
