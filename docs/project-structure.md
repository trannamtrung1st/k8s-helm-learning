# Project structure

This repository uses a small mono-repo layout: application code under `src/`, platform and delivery assets under `devops/`, and local development tooling under `local/`.

## Directory reference

### `src/`

- **Backend (.NET 10, Clean Architecture):** Solution **[`Workbench.sln`](../src/Workbench.sln)** with:
  - **[`Workbench.Domain`](../src/Workbench.Domain)** — entities and domain logic: **`Job`**, **`JobPayload`**, **`JobEnvelope`**, **`JobStatusNames`**, **`WorkbenchLimits`**, validation, **`LoadSimulator`**
  - **[`Workbench.Application`](../src/Workbench.Application)** — use cases and ports: **`IJobsApplicationService`**, **`IQueuedJobExecutor`**, **`IJobRepository`**, **`IJobQueuePublisher`**, **`WorkbenchOptions`**, DTOs
  - **[`Workbench.Infrastructure`](../src/Workbench.Infrastructure)** — adapters: EF Core **`JobsDbContext`**, **`EfJobRepository`**, RabbitMQ **`RabbitMqBus`** (connection only; topology from broker definitions), **`RabbitMqJobQueuePublisher`**, **`JobQueueConsumerHostedService`**, **EF migrations** under `Persistence/Migrations`
  - **[`Workbench.Api`](../src/Workbench.Api)** — HTTP host (minimal APIs, health checks)
  - **[`Workbench.Worker`](../src/Workbench.Worker)** — worker host (**`RabbitMQ.Client`** consumer wired via Infrastructure)
- **Compose (and local) service names** are **`workbench-api`** and **`workbench-worker`**; **.NET assembly** names remain **`Workbench.Api`** and **`Workbench.Worker`**.
- **Frontend:** **[`workbench-app`](../src/workbench-app)** — React + Vite + Tailwind per [Workbench demo spec](workbench-demo-spec.md). Set **`VITE_API_BASE_URL`** at build time (see [`Dockerfile`](../src/workbench-app/Dockerfile)); for local compose the image is built with **`http://localhost:8080`** so the browser can reach the published API port.
- **Docker:** API and worker build from **[`src/`](../src)**; the UI image builds from **[`src/workbench-app`](../src/workbench-app)**. **[`src/.dockerignore`](../src/.dockerignore)** trims .NET `bin`/`obj` from the backend context.

**EF migrations** (from `src/`):

```bash
dotnet ef migrations add <Name> -p Workbench.Infrastructure -s Workbench.Api
```

Design-time scaffolding uses **`JobsDbContextFactory`** (no full API host). Override the DB URL with env **`ConnectionStrings__Default`** or **`Workbench__Migrations__ConnectionString`** if localhost defaults are wrong.

### `devops/`

- **RabbitMQ:** canonical broker definitions for the workbench stack live in **[`devops/rabbitmq/definitions.json`](../devops/rabbitmq/definitions.json)** (vhost **`/`**, user **`workbench`**, exchange **`workbench.jobs`**, queue **`workbench.jobs.q`**, routing key **`job`**). Boot import is enabled by **[`devops/rabbitmq/conf.d/10-workbench-definitions.conf`](../devops/rabbitmq/conf.d/10-workbench-definitions.conf)** (`definitions.local.path` → **`/etc/rabbitmq/definitions/definitions.json`** in the container). **Local Compose** bind-mounts both files into **`rabbitmq:4-management-alpine`**; **Kubernetes** applies the same files through **`devops/kustomization.yaml`** (**`configMapGenerator`** → **`workbench-rabbitmq-definitions`**) so local and cluster stay aligned without duplicate copies under **`k8s/`**.
- **Redis:** **[`devops/redis/workbench.conf`](../devops/redis/workbench.conf)** is the single config file (see **`local/docker-compose.infra.yaml`**); **Kubernetes** loads it via **`secretGenerator`** in **`devops/kustomization.yaml`** (**`workbench-redis-secrets`**).
- **Kubernetes / Kustomize:** the intended tree (**`apps/`**, **`infrastructure/`**, **`clusters/`**, **`platform/`**, **`scripts/`**) is documented in **[`devops/k8s/README.md`](../devops/k8s/README.md)**. In this repo, **apply** the cluster from **`devops/`** using **`devops/kustomization.yaml`** (for example **`kubectl apply --server-side -k devops`**); **manifests** live under **`devops/k8s/`** (**`apps/workbench-api/`** and siblings follow **`base/`** + **`overlays/`** per app). **`devops/rabbitmq/`** and **`devops/redis/`** are the canonical file sources; the top-level Kustomize file uses **`configMapGenerator`** / **`secretGenerator`** so Kubernetes reuses the same paths as Compose without copies under **`k8s/`**. **Directory and manifest filenames** under **`devops/k8s/`** use **kebab-case** (for example **`platform/storage-classes/`**, **`config-map.yaml`**, **`stateful-set.yaml`**). **Labels** use **`app.kubernetes.io/name`** / **`component`** (see the label convention section there). **Namespaces** live under **`devops/k8s/platform/namespaces/`** (**`workbench-apps`**, **`workbench-db`**, **`workbench-storage`**, **`workbench-infra`**); apply with **`kubectl apply --server-side -k devops/k8s/platform/namespaces`** on that directory (see the **Namespaces** section in the k8s README).

Other infrastructure-as-code (Terraform, raw YAML, additional charts, CI) can live under **`devops/`** as you add it.

### `local/`

Local-only material: environment samples, helper scripts, and Docker Compose files. Nothing here is required for production clusters; it supports developing and testing on a single machine. **RabbitMQ** broker config and definitions JSON both live under **`devops/rabbitmq/`** (see **`devops/`** above); Compose only bind-mounts them into the container.

## Docker Compose

Workbench **v1** app path in [Workbench demo spec](workbench-demo-spec.md) uses **PostgreSQL** and **RabbitMQ** only; **Redis** is still included in Compose so you can practice cache/idempotency patterns after v1 without changing the file layout.

| File                                                                    | Purpose                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| ----------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`local/docker-compose.infra.yaml`](../local/docker-compose.infra.yaml) | **Infrastructure only** — `postgres`, `rabbitmq` (management **15672**), `redis` (**6379**). Postgres uses user/password/database **`workbench`**. **RabbitMQ** mounts **[`devops/rabbitmq/conf.d/10-workbench-definitions.conf`](../devops/rabbitmq/conf.d/10-workbench-definitions.conf)** and **[`devops/rabbitmq/definitions.json`](../devops/rabbitmq/definitions.json)** at boot. No bind or named volumes: data is **ephemeral** for local resets. |
| [`local/docker-compose.yaml`](../local/docker-compose.yaml)             | **Full stack** — `include`s infra (same **RabbitMQ** definitions mounts) and adds **`workbench-api`**, **`workbench-worker`**, **`workbench-app`** (React UI) with **`deploy.resources`** limits. Requires **`include`** support.                                                                                                                                                                                                                         |

Published ports (host) when using the full stack file:

| Service       | Ports                          |
| ------------- | ------------------------------ |
| PostgreSQL    | **5432**                       |
| RabbitMQ      | **5672**, management **15672** |
| Redis         | **6379**                       |
| workbench-api | **8080**                       |
| workbench-app | **8081** → container **80**    |

App containers receive **example** connection settings (override in compose or `.env` when your app uses different names):

- `ConnectionStrings__Default` → Postgres at host `postgres`
- `RabbitMq__Uri` → `amqp://workbench:workbench@rabbitmq:5672/` (user/password are defined in **[`devops/rabbitmq/definitions.json`](../devops/rabbitmq/definitions.json)**; change the hash there if you rotate the password)
- `Redis__ConnectionString` → `redis:6379` (StackExchange.Redis–style endpoint; no password in local Compose)

These credentials are for **local practice only**; do not reuse in production.

Typical usage (from the **repository root**):

```bash
docker compose -f local/docker-compose.infra.yaml up -d
docker compose -f local/docker-compose.yaml up --build
```

Use the first when you only need Postgres, RabbitMQ, and Redis; use the second for infra plus all app images. Add `-d` for detached mode if you prefer.

## Relation to the workbench demo

The application built under `src/` is intended to align with [Workbench demo spec](workbench-demo-spec.md) so platform experiments (Gateway API, observability, secrets, policies) stay on one coherent system instead of one-off demos.
