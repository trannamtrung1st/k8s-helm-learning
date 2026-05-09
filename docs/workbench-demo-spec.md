# Workbench demo — requirements and specifications

Design-only document for a small **synthetic load** system used to practice Kubernetes, Helm, autoscaling, ingress, and observability. **No implementation commitment** in this repo until you choose to build it.

## Purpose

- Simulate **CPU load**, **resident memory**, and **duration** via explicit parameters (no real business domain).
- Exercise a **multi-service** layout that feels like production software: **web UI**, **API**, **background worker**, **message broker**, **database**, and optionally **cache** after v1.
- Support later practice for **HPA**, **VPA**, **KEDA** (broker backlog), **Ingress**, **TLS**, **NetworkPolicy**, metrics, and tracing.

## Technology stack

| Layer | Choice | Notes |
|-------|--------|--------|
| API & worker | **.NET 10** | `load-api`: ASP.NET Core (REST). `load-worker`: worker service (e.g. `GenericHost` + hosted consumer, or separate executable). Prefer a **shared class library** for payload models and the **simulation routine** so API and worker stay in sync. |
| Web UI | **React** + **Tailwind CSS** | SPA (e.g. **Vite** as bundler). Served as static assets behind nginx in Kubernetes. Tailwind for layout and forms; keep the UI utilitarian. |
| Database | **PostgreSQL** | **System of record** for jobs (`id`, `status`, `payload` JSON, timestamps, error text). **v1:** migrations with **EF Core** (see section **Implementation defaults (v1)**). |
| Job queue | **RabbitMQ** | Primary path: API **publishes** job messages; workers **consume** from a named queue (and exchange). **KEDA** can scale workers on **queue length** or **message rate** (RabbitMQ scaler). Topology: **Implementation defaults (v1)**. |
| Cache / aux | **Redis** | **Not used in v1** (all state in Postgres). After v1, optional **idempotency**, **rate limiting**, or **read-through cache** for job status—see Technology stack intent only; no keys required until you add Redis. |
| MQTT (later) | **EMQX** | **Out of scope for v1.** Add when practicing **certificates**, **TLS**, and **mTLS**: e.g. EMQX in-cluster, clients (or a small bridge service) using signed certs; optional publish of job lifecycle events over MQTT for observability drills—not required for core load simulation. |

**Interop (v1):** UI talks HTTP/JSON to the API only. API and workers use **Postgres** and **RabbitMQ** only.

## System overview

- **load-web**: React + Tailwind SPA (static build via nginx). Submits jobs and shows status (polling is enough for v1).
- **load-api**: .NET 10 HTTP API. Validates payloads, writes job row to **Postgres**, publishes message to **RabbitMQ**, exposes job status from **Postgres** (v1: no Redis).
- **load-worker**: .NET 10 consumer. Pulls from **RabbitMQ**, updates Postgres status, runs the CPU/memory/time simulation (shared library).
- **RabbitMQ**: Decouples API from workers; supports **KEDA**-driven scale-out.
- **PostgreSQL**: Durable jobs and history (backup/restore exercises on the roadmap).
- **Redis**: Omit in v1; add when you want a dedicated Redis exercise on the roadmap.
- **EMQX**: Deferred; used later for **certificate and mTLS** testing with MQTT, separate from the core request path.

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
| `durationSec` | Total time the simulation runs. **Numeric bounds:** see **Validation caps** under **Implementation defaults (v1)**. |
| `cpuPercent` | 0–100. Approximate sustained CPU using a spin/sleep loop per time slice (no need for `stress-ng` in v1). **Algorithm:** see **Simulation routine** under **Implementation defaults (v1)**. |
| `memoryMb` | Allocate roughly this much memory; reject out-of-range values per **v1 caps** (below). |
| `memoryTouch` | If true, touch pages so **RSS** reflects allocation (better for memory-observable demos). |

## Implementation defaults (v1)

Simple defaults so an implementer can build without extra design meetings. **Principle:** one exchange, one queue, no DLQ in v1; **async** = Postgres + RabbitMQ; **sync** = in-process only.

### RabbitMQ (minimal broker topology)

- **Exchange**: name `workbench.jobs`, type **direct**, **durable**.
- **Queue**: name `workbench.jobs.q`, **durable**; bind with routing key **`job`**.
- **Publishing**: **persistent** messages (`delivery mode 2`); API uses the same exchange + routing key `job`.
- **Consumers**: **manual ack**; **prefetch** `5` per channel (single consumer channel per worker process is enough for v1).
- **Failure handling (simple):** on handler success → **ack**; on uncaught failure after DB update to `failed` → **ack** anyway (message was processed; bad payload is visible in Postgres). Avoid requeue loops in v1.
- **Optional later (“Phase 1b”):** dead-letter exchange → queue `workbench.jobs.dlq` via a RabbitMQ policy if you want an extra learning exercise.
- **Message body (envelope)** — JSON UTF-8:

```json
{
  "jobId": "550e8400-e29b-41d4-a716-446655440000",
  "payload": {
    "durationSec": 30,
    "cpuPercent": 80,
    "memoryMb": 256,
    "memoryTouch": true
  }
}
```

- **`jobId`** is the same UUID as `jobs.id` in Postgres (string, lowercase).
- **.NET client (v1):** use **`RabbitMQ.Client`** (official driver, small surface area, easy to reason about in Kubernetes). **MassTransit** or similar is optional if you prefer a higher-level API; it does not change how you practice probes, ingress, or KEDA.

### PostgreSQL + .NET persistence

- **Migrations:** **EF Core**; one `DbContext`, `Job` entity matching [PostgreSQL conventions](#postgresql-conventions). FluentMigrator is out of scope unless you prefer it later.
- **IDs:** UUID v4, generated in the API on `POST /v1/jobs` **before** publishing to RabbitMQ.

### Validation caps (configurable constants)

Single `WorkbenchOptions` (or `appsettings`) section in code; document the same limits here:

- `durationSec`: **1–300** (inclusive).
- `cpuPercent`: **0–100** (inclusive).
- `memoryMb`: **0–1024** (inclusive) for v1 local practice. Lower the maximum if your cluster pod memory limit is small.
- Reject invalid input with **400** and a small JSON body (see **HTTP JSON examples** below).

### `POST /v1/work` (sync) semantics

- **Does not** insert a `jobs` row and **does not** publish to RabbitMQ.
- Runs the **same shared simulation routine** in the API process (same validation and caps); returns **200** with a short summary, e.g. `{ "mode": "sync", "elapsedMs": 30000 }`.
- Use for quick CPU/memory spikes and debugging. Roadmap practice for **async** jobs remains **`POST /v1/jobs`**.

### HTTP JSON examples

**`POST /v1/jobs` — response `201 Created`:**

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "queued"
}
```

**`GET /v1/jobs/{id}` — response `200 OK`:**

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "running",
  "payload": {
    "durationSec": 30,
    "cpuPercent": 80,
    "memoryMb": 256,
    "memoryTouch": true
  },
  "createdAt": "2026-05-09T12:00:00Z",
  "startedAt": "2026-05-09T12:00:01Z",
  "finishedAt": null,
  "error": null
}
```

**`GET /v1/jobs?limit=20`:** JSON array of the same object shape, ordered by `created_at` descending.

**Validation error — response `400 Bad Request`:**

```json
{
  "error": "validation_failed",
  "details": {
    "memoryMb": "must be between 0 and 1024"
  }
}
```

ASP.NET **ProblemDetails** is fine as long as the same information appears.

### Redis (v1)

- **Omit Redis** from the v1 codebase and from local `compose` unless you are actively practicing Redis on the roadmap. All reads/writes go through **Postgres**.

### Simulation routine

- **100 ms wall-clock slices** until `durationSec` elapses. Each slice: spin the CPU for **`cpuPercent`%** of 100 ms, **sleep** the remainder. Hold an allocated **`memoryMb`** buffer for the full duration; if **`memoryTouch`**, walk (touch) the buffer each slice.

## API requirements (load-api)

- `POST /v1/jobs` — Persist job (`queued`), publish to RabbitMQ, return **`201`** with `id` and `status` (see **HTTP JSON examples** in **Implementation defaults (v1)**).
- `GET /v1/jobs/:id` — Return job from **Postgres** (same section for example response).
- `GET /v1/jobs?limit=…` — Recent jobs list from Postgres for the UI (same section for response shape).
- `GET /healthz`, `GET /ready` — Liveness/readiness (readiness should verify Postgres + RabbitMQ connectivity as appropriate).
- `POST /v1/work` — **Synchronous** load only (see section **`POST /v1/work` (sync) semantics** in **Implementation defaults (v1)**).
- **CORS** or single-host **Ingress** so the browser can call the API (`/api` prefix is a common pattern).

Suggested status values: `queued`, `running`, `succeeded`, `failed`.

## UI requirements (load-web)

- Form fields matching the payload: duration, CPU %, memory MB, memory touch (checkbox).
- **Submit** creates a job via `POST /v1/jobs`.
- Display **job id** and **status**; **poll** every 1–2s until a terminal state.
- Optional: simple list of recent jobs from `GET /v1/jobs`.
- **Configuration**: API base URL via `import.meta.env` (Vite) at build time or runtime injection via nginx `envsubst` so one image works across clusters.
- Visual polish is not a goal; clarity and fast iteration are.

## Worker requirements (load-worker)

- Consume from **RabbitMQ** per **Implementation defaults (v1)** (competing consumers, **prefetch 5**, manual ack).
- On message: deserialize payload, set Postgres status to `running`, execute simulation, then `succeeded` or `failed` (store errors in DB).
- **Graceful shutdown:** allow in-flight work to finish when possible; ack policy follows **Implementation defaults** (no silent message loss if the process dies mid-job beyond broker redelivery semantics).
- Same caps and validation as the API where applicable.

## RabbitMQ conventions

Canonical v1 exchange, queue, routing key, message envelope, and ack rules are defined in **Implementation defaults (v1)**.

## Redis conventions

**v1:** Not used—see **Redis (v1)** under **Implementation defaults (v1)**. After v1, if you add Redis, define key prefixes, TTLs, and cache strategy then.

## PostgreSQL conventions

- Table `jobs` (or equivalent) with at least: `id`, `status`, `payload` (JSONB), `created_at`, `started_at`, `finished_at`, `error`.
- Indexes for list-by-time queries for the UI (e.g. on `created_at` DESC).
- **v1:** primary key **UUID v4**; migrations via **EF Core** (see **PostgreSQL + .NET persistence** under **Implementation defaults (v1)**).

## Kubernetes and networking

- Separate **Deployment + Service** per application component: **web**, **api**, **worker**, plus **RabbitMQ** and **PostgreSQL**. **Redis:** only when you add Redis after v1 (Helm charts or operators are fine for infra).
- Set **resource requests and limits** on api and worker (and small limits on web) so HPA/VPA and cgroup behavior are visible.
- **Ingress** (when practiced): e.g. path **`/`** → `load-web`, **`/api`** → `load-api` (agree whether the API serves routes with or without `/api` prefix and configure rewrite if needed).

## Autoscaling and observability goals

- **Workers**: primary target for **KEDA** (RabbitMQ queue length / message rate) and/or **HPA** (CPU).
- **API**: scale if you load-test synchronous endpoints or high enqueue rate.
- **Prometheus** metrics: use .NET **OpenTelemetry** or `prometheus-net` on api/worker (throughput, latency, failures).
- Logs to stdout for **Loki**; trace context propagated API → broker → worker where practical.

## Safety and ergonomics

- Enforce numeric caps from **Validation caps** in **Implementation defaults (v1)**; return **`400`** with the validation JSON shape from **HTTP JSON examples** on bad input.
- Document recommended **requests/limits** per practice scenario (steady vs burst) when you deploy to a cluster.

## Later: EMQX and certificate testing

- Deploy **EMQX** when you are ready to practice **TLS**, client certs, and **mTLS** (broker and/or publishers).
- Possible drills: internal CA with **cert-manager**, signed MQTT clients, topic ACLs, and verifying chain of trust—orthogonal to the HTTP workbench but shareable **jobId** or events if you want cross-protocol demos.
- Does not replace RabbitMQ for the core job pipeline unless you explicitly redesign around MQTT.

## Related demo themes (broader than this workbench)

These align with the learning roadmap but are not fully specified here:

- **Autoscaling**: VPA for suggestions, HPA on CPU/memory (and custom metrics later).
- **Networking**: Services, Ingress, egress policies.
- **Istio / mesh**, **canary** traffic: optional layers on top of the same Deployments.
