# Workbench demo — requirements and specifications

Design-only document for a small **synthetic load** system used to practice Kubernetes, Helm, autoscaling, ingress, and observability. **No implementation commitment** in this repo until you choose to build it.

## Purpose

- Simulate **CPU load**, **resident memory**, and **duration** via explicit parameters (no real business domain).
- Exercise a **multi-service** layout that feels like production software: **web UI**, **API**, **background worker**, **queue**, optional **database**.
- Support later practice for **HPA**, **VPA**, **KEDA** (queue depth), **Ingress**, **TLS**, **NetworkPolicy**, metrics, and tracing.

## System overview

- **load-web**: Browser UI (e.g. static SPA served by nginx). Submits jobs and shows status (polling is enough for v1).
- **load-api**: HTTP API. Validates payloads, enqueues work, exposes job status. Optional synchronous “run now” endpoint for debugging.
- **load-worker**: Consumes jobs from the queue, runs the same CPU/memory/time simulation, updates job status.
- **Redis**: Queue (list or stream) and ephemeral job status keys. Enables **KEDA** scaling on backlog.
- **PostgreSQL** (optional, later): Durable `jobs` table for history, backups, and persistence drills on the learning roadmap.

## Job payload (shared contract)

All of API, worker, and UI must agree on one JSON shape. Example:

```json
{
  "durationSec": 30,
  "cpuPercent": 80,
  "memoryMb": 256,
  "memoryTouch": true
}
```

| Field | Requirement |
|-------|-------------|
| `durationSec` | Total time the simulation runs (bounded with a **maximum**, e.g. 300s, to avoid hung requests). |
| `cpuPercent` | 0–100. Approximate sustained CPU using a spin/sleep loop per time slice (no need for `stress-ng` in v1). |
| `memoryMb` | Allocate roughly this much memory; validate below pod **memory limit** and reject or cap unsafe values. |
| `memoryTouch` | If true, touch pages so **RSS** reflects allocation (better for memory-observable demos). |

## API requirements (load-api)

- `POST /v1/jobs` — Enqueue a job. Response includes `id` and initial `status` (e.g. `queued`).
- `GET /v1/jobs/:id` — Return `id`, `status`, `payload`, timestamps, optional error message.
- `GET /v1/jobs?limit=…` — Optional recent jobs list for the UI (implementation may use Redis or Postgres).
- `GET /healthz`, `GET /ready` — Liveness/readiness.
- Optional `POST /v1/work` — **Synchronous** run with the same body as the job payload (for quick tests without the worker).
- **CORS** or single-host **Ingress** so the browser can call the API (`/api` prefix is a common pattern).

Suggested status values: `queued`, `running`, `succeeded`, `failed`.

## UI requirements (load-web)

- Form fields matching the payload: duration, CPU %, memory MB, memory touch (checkbox).
- **Submit** creates a job via `POST /v1/jobs`.
- Display **job id** and **status**; **poll** every 1–2s until a terminal state.
- Optional: simple list of recent jobs if `GET /v1/jobs` exists.
- **Configuration**: API base URL via build-time env or runtime injection (e.g. nginx `envsubst`) so one image works across clusters.
- Visual polish is not a goal; clarity and fast iteration are.

## Worker requirements (load-worker)

- Block on the Redis queue; on message, deserialize payload, set status to `running`, execute simulation, then `succeeded` or `failed`.
- **Graceful shutdown**: finish or re-queue according to a documented policy (at minimum: don’t lose queue semantics on SIGTERM).
- Same caps and validation as the API where applicable.

## Redis conventions (specify before coding)

- Queue key name(s) and whether you use **List + BRPOP** or **Streams + consumer group**.
- Job status key pattern, e.g. `job:{id}` with JSON or hash fields.
- TTL or cleanup policy for finished jobs if storage is only Redis.

## Kubernetes and networking

- Separate **Deployment + Service** per component: web, api, worker, Redis (Redis may be a chart or operator in-cluster).
- Set **resource requests and limits** on api and worker (and small limits on web) so HPA/VPA and cgroup behavior are visible.
- **Ingress** (when practiced): e.g. path **`/`** → `load-web`, **`/api`** → `load-api` ( agree whether the API serves routes with or without `/api` prefix and configure rewrite if needed).

## Autoscaling and observability goals

- **Workers**: primary target for **KEDA** (queue depth) and/or **HPA** (CPU).
- **API**: scale if you load-test synchronous endpoints or high enqueue rate.
- Optional **Prometheus** metrics on api/worker (jobs completed, duration, errors) for dashboards and future custom metrics.
- Logs to stdout for **Loki**; optional **OpenTelemetry** on API later.

## Safety and ergonomics

- Hard caps on `durationSec` and `memoryMb`; return `400` with a clear message when invalid.
- Document recommended **requests/limits** per practice scenario (steady vs burst).

## Related demo themes (broader than this workbench)

These align with the learning roadmap but are not fully specified here:

- **Autoscaling**: VPA for suggestions, HPA on CPU/memory (and custom metrics later).
- **Networking**: Services, Ingress, egress policies.
- **EMQX**, certificates, and **mTLS** as a separate exercise (could publish the same job envelope over MQTT later).
