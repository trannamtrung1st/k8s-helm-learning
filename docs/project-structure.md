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

- **RabbitMQ:** canonical broker definitions for the workbench stack live in **[`devops/rabbitmq/definitions.json`](../devops/rabbitmq/definitions.json)** (vhost **`/`**, user **`workbench`**, exchange **`workbench.jobs`**, queue **`workbench.jobs.q`**, routing key **`job`**). **Local Compose** bind-mounts this file into **`rabbitmq:4-management`**; when you add Kubernetes manifests or Helm, reuse the **same path** (e.g. ConfigMap/Secret **`kubectl create secret --from-file=...=devops/rabbitmq/definitions.json`**) so local and cluster stay aligned.

Other infrastructure-as-code (Terraform, raw YAML, additional charts, CI) can live under **`devops/`** as you add it.

### `local/`

Local-only material: environment samples, helper scripts, and Docker Compose files. Nothing here is required for production clusters; it supports developing and testing on a single machine. **RabbitMQ** boot config for the official image is **[`local/rabbitmq/conf.d/10-workbench-definitions.conf`](../local/rabbitmq/conf.d/10-workbench-definitions.conf)** (`definitions.local.path` → mounted JSON). Definitions content itself is **`devops/rabbitmq/definitions.json`** (see **`devops/`** above).

## Docker Compose

Workbench **v1** app path in [Workbench demo spec](workbench-demo-spec.md) uses **PostgreSQL** and **RabbitMQ** only; **Redis** is still included in Compose so you can practice cache/idempotency patterns after v1 without changing the file layout.

| File                                                                  | Purpose                                                                                                                                                                                                                        |
| --------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| [`local/docker-compose.infra.yml`](../local/docker-compose.infra.yml) | **Infrastructure only** — `postgres`, `rabbitmq` (management **15672**), `redis` (**6379**). Postgres uses user/password/database **`workbench`**. **RabbitMQ** mounts **[`devops/rabbitmq/definitions.json`](../devops/rabbitmq/definitions.json)** at boot (see [`local/rabbitmq/conf.d/10-workbench-definitions.conf`](../local/rabbitmq/conf.d/10-workbench-definitions.conf)). No bind or named volumes: data is **ephemeral** for local resets.         |
| [`local/docker-compose.yml`](../local/docker-compose.yml)             | **Full stack** — `include`s infra (same **RabbitMQ** definitions mounts) and adds **`workbench-api`**, **`workbench-worker`**, **`workbench-app`** (React UI) with **`deploy.resources`** limits. Requires **`include`** support.                                      |

Published ports (host) when using the full stack file:

| Service    | Ports        |
| ---------- | ------------ |
| PostgreSQL | **5432**     |
| RabbitMQ   | **5672**, management **15672** |
| Redis      | **6379**     |
| workbench-api | **8080**     |
| workbench-app | **8081** → container **80** |

App containers receive **example** connection settings (override in compose or `.env` when your app uses different names):

- `ConnectionStrings__Default` → Postgres at host `postgres`
- `RabbitMq__Uri` → `amqp://workbench:workbench@rabbitmq:5672/` (user/password are defined in **[`devops/rabbitmq/definitions.json`](../devops/rabbitmq/definitions.json)**; change the hash there if you rotate the password)
- `Redis__ConnectionString` → `redis:6379` (StackExchange.Redis–style endpoint; no password in local Compose)

These credentials are for **local practice only**; do not reuse in production.

Typical usage (from the **repository root**):

```bash
docker compose -f local/docker-compose.infra.yml up -d
docker compose -f local/docker-compose.yml up --build
```

Use the first when you only need Postgres, RabbitMQ, and Redis; use the second for infra plus all app images. Add `-d` for detached mode if you prefer.

## Relation to the workbench demo

The application built under `src/` is intended to align with [Workbench demo spec](workbench-demo-spec.md) so platform experiments (Ingress, observability, secrets, policies) stay on one coherent system instead of one-off demos.
