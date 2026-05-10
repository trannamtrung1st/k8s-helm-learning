# Workbench demo — requirements and specifications

Design-only document for a small **synthetic load** system used to practice Kubernetes, Helm, autoscaling, ingress, and observability. **No implementation commitment** in this repo until you choose to build it.

## Purpose

- Simulate **CPU load**, **resident memory**, and **duration** via explicit parameters (no real business domain).
- Exercise a **multi-service** layout that feels like production software: **web UI**, **API**, **background worker**, **message broker**, **database**, and optionally **cache** after v1.
- Support later practice for **HPA**, **VPA**, **KEDA** (broker backlog), **Ingress**, **TLS**, **NetworkPolicy**, **Datadog** (metrics, logs, APM), **resource requests and limits**, **Deployments / StatefulSets / Jobs**, **Service** types, multi-replica HA, and **secret management** when you wire credentials for Postgres, RabbitMQ, and apps.

## Roadmap alignment

Use [Learning roadmap](roadmap.md) as the syllabus; **keep deploying this workbench** as line items advance. Rough mapping:

| Roadmap theme                 | Workbench touchpoints                                                                                                                               |
| ----------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| Workloads (1–7, 9–11)         | `Deployment` / `Job` for web, api, worker; Postgres, RabbitMQ, Redis charts                                                                         |
| Expose traffic (4, 18–19, 21) | `Service` types, `Ingress`, TLS, DNS to **workbench-app** and **workbench-api**                                                                               |
| Stability (5–6, 32)           | Replicas, PDB, **requests/limits**, rolling updates                                                                                                 |
| Autoscale (33–35)             | HPA on api/worker; **KEDA** on RabbitMQ depth; cluster autoscaler                                                                                   |
| Observability (25–26)         | **Datadog**: cluster agent/agent, logs, APM (or OTel → Datadog) for **workbench-api** / **workbench-worker**                                                  |
| Access control (27–28)        | RBAC and `NetworkPolicy` around workbench namespaces                                                                                                |
| Secret management (20)        | **External Secrets** (or similar) for Postgres and RabbitMQ credentials consumed by **workbench-api** / **workbench-worker**                                  |
| Data durability (22–24)       | Postgres PVCs, backups                                                                                                                              |
| Delivery (46–50)              | **Kustomize** base + env **overlays** for images, config, and cluster-specific patches (see **Kubernetes and networking → Kustomize**); **GitHub Actions** for build/deploy (46–47), previews (**48**), rollbacks (**49**); **Argo CD (50)** optional later to sync the same manifests/Helm |

**Secrets:** Prefer **External Secrets** or equivalent once broker and DB credentials leave plain `Secret` YAML ([roadmap](roadmap.md) item **20**, placed after cert-manager). Store connection strings and API keys for **workbench-api** / **workbench-worker** consistently.

## Technology stack

| Layer        | Choice                       | Notes                                                                                                                                                                                                                                                                                  |
| ------------ | ---------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| API & worker | **.NET 10**                  | `workbench-api`: ASP.NET Core (REST). `workbench-worker`: worker service (e.g. `GenericHost` + hosted consumer, or separate executable). Prefer a **shared class library** for payload models and the **simulation routine** so API and worker stay in sync.                                     |
| Web UI       | **React** + **Tailwind CSS** | SPA (e.g. **Vite** as bundler). Served as static assets behind nginx in Kubernetes. Tailwind for layout and forms; keep the UI utilitarian.                                                                                                                                            |
| Database     | **PostgreSQL**               | **System of record** for jobs (`id`, `status`, `payload` JSON, timestamps, error text). **v1:** migrations with **EF Core** (see section **Implementation defaults (v1)**).                                                                                                            |
| Job queue    | **RabbitMQ**                 | Job envelopes over **`RabbitMQ.Client`**. **Topology** is **not** created by the apps: **[`devops/rabbitmq/definitions.json`](../devops/rabbitmq/definitions.json)** is the shared definitions file—**local Compose** bind-mounts it at broker boot; reuse the **same file** for Kubernetes when you add manifests. **KEDA** can scale workers on queue depth or message rate in cluster deployments.                                                                                                                                                    |
| Cache / aux  | **Redis**                    | **Not used in v1** (all state in Postgres). After v1, optional **idempotency**, **rate limiting**, or **read-through cache** for job status—see Technology stack intent only; no keys required until you add Redis.                                                                    |
| MQTT (later) | **EMQX**                     | **Out of scope for v1.** Add when practicing **certificates**, **TLS**, and **mTLS**: e.g. EMQX in-cluster, clients (or a small bridge service) using signed certs; optional publish of job lifecycle events over MQTT for observability drills—not required for core load simulation. |
| K8s packaging | **Kustomize**               | **Base** manifests (shared workloads, Services, bare ConfigMaps/Secrets structure) plus **overlay** directories per environment (**local-kind**, **dev**, **staging**, **prod**, …). Overlays hold **patches**, **images**, **replicas**, **resources**, **namespace**, **Ingress** hosts, and **env-specific** `ConfigMap`/`Secret` wiring. Use this for **environment differences** before or alongside Helm (roadmap chart conversion stays a separate exercise). |

**Interop (v1):** UI talks HTTP/JSON to the API only. API and workers use **Postgres** and **RabbitMQ** only.

## System overview

- **workbench-app**: React + Tailwind SPA (static build via nginx). Submits jobs and shows status (polling is enough for v1).
- **workbench-api**: .NET 10 HTTP API. Validates payloads, writes job row to **Postgres**, publishes the job envelope to RabbitMQ using **`RabbitMQ.Client`**, exposes job status from **Postgres** (v1: no Redis).
- **workbench-worker**: .NET 10 background host with a **`RabbitMQ.Client`** consumer on the primary job queue; updates Postgres status and runs the CPU-memory-time simulation (shared library).
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
  "memoryTouch": true,
  "forceGcAfterRun": false
}
```

| Field              | Requirement                                                                                                                                                                                |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `durationSec`      | Total time the simulation runs. **Numeric bounds:** see **Validation caps** under **Implementation defaults (v1)**.                                                                        |
| `cpuPercent`       | 0–100. Approximate sustained CPU using a spin/sleep loop per time slice (no need for `stress-ng` in v1). **Algorithm:** see **Simulation routine** under **Implementation defaults (v1)**. |
| `memoryMb`         | Allocate roughly this much memory; reject out-of-range values per **v1 caps** (below).                                                                                                     |
| `memoryTouch`      | If true, touch pages so **RSS** reflects allocation (better for memory-observable demos).                                                                                                  |
| `forceGcAfterRun`  | If true and the run used a **large object heap** allocation, run a blocking full GC with **LOH compaction** after the run so process RSS tends to drop (optional; adds latency; default false). |

## Implementation defaults (v1)

Simple defaults so an implementer can build without extra design meetings. **Principle:** one exchange, one queue, no DLQ in v1; **async** = Postgres + RabbitMQ; **sync** = in-process only.

### RabbitMQ (minimal broker topology)

- **Exchange**: name `workbench.jobs`, type **direct**, **durable**.
- **Queue**: name `workbench.jobs.q`, **durable**; bind with routing key **`job`**.
- **Provisioning (v1):** create virtual host **`/`**, application user (**`workbench`** / **`workbench`** in this repo), and the job **exchange**, **queue**, and **binding** with a **definitions** JSON file imported at **node boot** (`definitions.import_backend = local_filesystem` and `definitions.local.path`, per [RabbitMQ](https://www.rabbitmq.com/docs/definitions)). The canonical file in this repo is **[`devops/rabbitmq/definitions.json`](../devops/rabbitmq/definitions.json)**—**local Compose** bind-mounts it (see **[`local/docker-compose.infra.yaml`](../local/docker-compose.infra.yaml)**); wire the **same file** into cluster brokers when you add Kubernetes or Helm. Boot import **does not** seed Docker’s default user: credentials and topology live in that JSON. **Do not rely on apps declaring topology.** The **API** and **worker** only connect, publish, and consume.
- **Publishing**: **persistent** messages (`delivery mode 2`); API uses the same exchange + routing key `job`.
- **Consumers:** **manual ack** with **prefetch ≈ 5** (see **Worker requirements**). **Ack** after **`IQueuedJobExecutor.ExecuteAsync`** returns without throwing (today’s executor persists `failed` in Postgres for validation/simulation errors and does not rethrow). **Nack without requeue** for poison JSON or unexpected throws (e.g. DB errors) so poison messages are not endlessly redelivered.
- **Optional later (“Phase 1b”):** dead-letter exchange → queue `workbench.jobs.dlq` via a RabbitMQ policy if you want an extra learning exercise.
- **Message body (envelope)** — JSON UTF-8:

```json
{
  "jobId": "550e8400-e29b-41d4-a716-446655440000",
  "payload": {
    "durationSec": 30,
    "cpuPercent": 80,
    "memoryMb": 256,
    "memoryTouch": true,
    "forceGcAfterRun": false
  }
}
```

- **`jobId`** is the same UUID as `jobs.id` in Postgres (string, lowercase).
- **.NET messaging (v1):** use **`RabbitMQ.Client`** (async API) in Infrastructure: **persistent** publish to **`workbench.jobs`** with routing key **`job`**, consume from **`workbench.jobs.q`** with **prefetch ≈ 5** and **manual ack**. Serialization is **System.Text.Json** with **camelCase** to match the HTTP API. **Broker objects** must already exist (definitions import)—the code does **not** declare exchanges or queues.

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
    "memoryTouch": true,
    "forceGcAfterRun": false
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

- **100 ms wall-clock slices** until `durationSec` elapses. Each slice: spin the CPU for **`cpuPercent`%** of 100 ms, **sleep** the remainder. Hold an allocated **`memoryMb`** buffer for the full duration; if **`memoryTouch`**, walk (touch) the buffer each slice. If **`forceGcAfterRun`** is true and the allocation is large-object-heap sized, after the run drop the buffer and run a blocking full GC with LOH compaction (optional; helps RSS drop in demos).

## API requirements (workbench-api)

- `POST /v1/jobs` — Persist job (`queued`), publish to RabbitMQ, return **`201`** with `id` and `status` (see **HTTP JSON examples** in **Implementation defaults (v1)**).
- `GET /v1/jobs/:id` — Return job from **Postgres** (same section for example response).
- `GET /v1/jobs?limit=…` — Recent jobs list from Postgres for the UI (same section for response shape).
- `GET /healthz`, `GET /ready` — Liveness/readiness (readiness should verify Postgres + RabbitMQ connectivity as appropriate).
- `POST /v1/work` — **Synchronous** load only (see section **`POST /v1/work` (sync) semantics** in **Implementation defaults (v1)**).
- **CORS** or single-host **Ingress** so the browser can call the API (`/api` prefix is a common pattern).

Suggested status values: `queued`, `running`, `succeeded`, `failed`.

## UI requirements (workbench-app)

- Form fields matching the payload: duration, CPU %, memory MB, memory touch (checkbox), optional **force GC after run** (checkbox; see **`forceGcAfterRun`**).
- **Submit** creates a job via `POST /v1/jobs`.
- Display **job id** and **status**; **poll** every 1–2s until a terminal state.
- Optional: simple list of recent jobs from `GET /v1/jobs`.
- **Configuration**: API base URL via `import.meta.env` (Vite) at build time or runtime injection via nginx `envsubst` so one image works across clusters.
- Visual polish is not a goal; clarity and fast iteration are.

## Worker requirements (workbench-worker)

- Consume via **`RabbitMQ.Client`** per **Implementation defaults (v1)**. Use **prefetch ≈ 5** and **manual ack** as described there.
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

### Labels (Kubernetes recommended)

- Use **`app.kubernetes.io/name`**, **`app.kubernetes.io/component`**, and optional **`app.kubernetes.io/part-of`** for selectors and object metadata—see **[`devops/k8s/README.md` — Label convention](../devops/k8s/README.md#label-convention-kubernetes-recommended-labels)** (includes a **common `component` value** table: **`api`**, **`worker`**, **`frontend`**, …).

### Kustomize (base + environment overlays)

- **Default approach for env-specific Kubernetes YAML:** maintain a **`base`** (or `kustomize/base`) with the canonical **`workbench-app`**, **`workbench-api`**, and **`workbench-worker`** objects—**Deployments**, **Services**, shared labels/common annotations, and optional **ConfigMap** stubs—then one **overlay** per target environment (**e.g.** `overlays/local-kind`, `overlays/dev`, `overlays/prod`).
- **Overlays** apply only what differs: **`images`** (registry/tags from CI), **`replicas`**, **`resources`**, **namespace**, **Ingress** host/paths/TLS refs, **patches** (JSON or strategic merge) for connection strings or feature flags, and **replacements**/`vars` where appropriate. Keep secrets out of Git where policy requires it: reference **Secret** names in base/overlays and populate via **External Secrets**, sealed secrets, or CICD inject—not plain literals in overlay files.
- **`kubectl apply -k`** (or **`kustomize build … | kubectl apply -f -`**) is the day-to-day render path; **GitOps** tools (**Argo CD**, **Flux**) can point at the same **kustomization.yaml** roots later (roadmap item **50**).
- **Helm:** roadmap still includes **converting manifests to Helm charts**; you can introduce charts later and either **wrap** Kustomize (e.g. chart + post-render) or **migrate**—the spec does not require Helm for the first cluster bring-up if **Kustomize overlays** already express env differences clearly.
- **Layout:** a reference tree for **`apps/`** (per-service `base/` + `overlays/`), **`infrastructure/`**, **`clusters/`**, **`platform/`**, and **`scripts/`** is in **[`devops/k8s/README.md`](../devops/k8s/README.md)** (`devops/k8s/` is the Kubernetes root in this repo).

### Workload kinds (align with roadmap)

- **Application components (`workbench-app`, `workbench-api`, `workbench-worker`):** use **Deployment** (not bare Pods). They are stateless with respect to the cluster: state lives in **Postgres** and the **broker**.
- **Replicas / HA:** for exercises on **multiple replicas** and **availability**, run **at least 2 replicas** of **`workbench-api`** and **`workbench-app`** (API must remain safe with multiple instances: no in-memory-only session state). Run **2+ `workbench-worker`** replicas when practicing **competing consumers** on the same queue; **1** replica is acceptable for minimal bring-up.
- **Postgres, RabbitMQ, Redis:** install with **Helm or an operator**; underlying controllers are often **StatefulSet**. You practice **StatefulSet** explicitly when you follow that roadmap item (inspect or hand-write manifests), not by reimplementing the database in app code.
- **Kubernetes Job / CronJob (optional):** e.g. one-off **migration** Job, or a **CronJob** that triggers synthetic load (HTTP client calling `POST /v1/jobs`). Not required for the core UI/API/worker path.

### Services and external access

- **Default (v1):** **`ClusterIP`** `Service` for **web**, **api**, **worker**, and for in-cluster access to Postgres/RabbitMQ. Prefer **Ingress** (HTTP) from outside the cluster to **web** and **api** when you practice ingress routes.
- **Roadmap follow-up:** use **`NodePort`** or cloud **`LoadBalancer`** only when explicitly practicing those **Service** types; document the chosen `type` in your manifests and how it differs from **Ingress** (L4 vs L7, cost, scope).

### Resource requests and limits (required)

- Every **`workbench-app`**, **`workbench-api`**, and **`workbench-worker`** container MUST declare **`resources.requests`** and **`resources.limits`** for **CPU** and **memory** (avoid **BestEffort** for app components in this learning path unless troubleshooting).
- **`workbench-worker`** **memory limit** MUST stay **above** worst-case process use when a job runs **`memoryMb`** at the spec maximum (runtime CLR overhead + payload allocation + headroom). Enforce **`memoryMb`** validation so simulated allocation fits under the pod limit; lower the **`WorkbenchOptions`** max **`memoryMb`** if your cluster gives workers a small limit.
- **`workbench-api`** limits MUST allow **`POST /v1/work`** at max **`durationSec` / `memoryMb` / `cpuPercent`** without OOM or excessive throttling during demos.
- Record starter **requests/limits** in Helm **`values.yaml`** or in **Kustomize** base/patch YAML and adjust when practicing roadmap items on **resource limits / QoS** and **HPA** (resource metrics rely on **requests**, at minimum).

### Deployments and dependencies

- Separate **Deployment + Service** per application component: **web**, **api**, **worker**, plus install **RabbitMQ** and **PostgreSQL** (and **Redis** after v1). **Redis:** only when you add Redis after v1 (Helm charts or operators are fine for infra).
- **Ingress** (when practiced): e.g. path **`/`** → `workbench-app`, **`/api`** → `workbench-api` (agree whether the API serves routes with or without `/api` prefix and configure rewrite if needed).

## Autoscaling and observability goals

- **Workers**: primary target for **KEDA** (RabbitMQ queue length / message rate) and/or **HPA** (CPU).
- **API**: scale if you load-test synchronous endpoints or high enqueue rate.
- **Observability:** use **Datadog** (roadmap items **25–26**): cluster agent, log collection from stdout, **APM** or **OpenTelemetry** export to Datadog on **workbench-api** / **workbench-worker**; monitors and dashboards in Datadog. Self-hosted Prometheus/Loki are **out of scope for now**.

## Safety and ergonomics

- Enforce numeric caps from **Validation caps** in **Implementation defaults (v1)**; return **`400`** with the validation JSON shape from **HTTP JSON examples** on bad input.
- Keep container **requests/limits** consistent with **Resource requests and limits (required)** and revise together when scenario or cluster size changes.

## Later: EMQX and certificate testing

- Deploy **EMQX** when you are ready to practice **TLS**, client certs, and **mTLS** (broker and/or publishers).
- Possible drills: internal CA with **cert-manager**, signed MQTT clients, topic ACLs, and verifying chain of trust—orthogonal to the HTTP workbench but shareable **jobId** or events if you want cross-protocol demos.
- Does not replace RabbitMQ for the core job pipeline unless you explicitly redesign around MQTT.

## Related demo themes (broader than this workbench)

These align with the learning roadmap but are not fully specified here:

- **Autoscaling**: VPA for suggestions, HPA on CPU/memory (and custom metrics via Datadog or metrics adapters if needed).
- **Networking**: Services, Ingress, egress policies.
- **Istio / mesh**, **canary** traffic: optional layers on top of the same Deployments.
- **GitOps**: **Argo CD** is roadmap item **50** (advanced, after GitHub Actions CI/CD). Repositories can track **Kustomize** roots (`kustomization.yaml` per env overlay) as the deployable unit. **Policy engines, operators, cost tooling**: still deferred; see roadmap “out of scope for now.”
