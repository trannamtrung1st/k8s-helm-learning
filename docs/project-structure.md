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

- **RabbitMQ:** canonical broker definitions live in **[`devops/infra/workbench-rabbitmq/files/definitions.json`](../devops/infra/workbench-rabbitmq/files/definitions.json)** (vhost **`/`**, user **`workbench`**, exchange **`workbench.jobs`**, queue **`workbench.jobs.q`**, routing key **`job`**). Boot import is enabled by **[`devops/infra/workbench-rabbitmq/files/conf.d/10-workbench-definitions.conf`](../devops/infra/workbench-rabbitmq/files/conf.d/10-workbench-definitions.conf)** (`definitions.local.path` → **`/etc/rabbitmq/definitions/definitions.json`** in the container). **Local Compose** bind-mounts both files; **Helm** embeds them via **`.Files.Get`** into a definitions **ConfigMap** mounted into operator-managed pods; **legacy Kustomize** applies them through **`devops/kustomization.yaml`** (**`configMapGenerator`** → **`workbench-rabbitmq-definitions`**). On **Helm**, **`./scripts/helm-apply.sh`** installs **`workbench-crds-umbrella`** (RabbitMQ Cluster Operator from **`devops/crds/rabbitmq-operator`**) before **`workbench-umbrella`**, which includes **`workbench-rabbitmq`** (`RabbitmqCluster` CR with **dynamic PVC** persistence, not a local PV).
- **Redis:** **[`devops/infra/workbench-redis/files/workbench.conf`](../devops/infra/workbench-redis/files/workbench.conf)** is the single config file (see **`local/docker-compose.infra.yaml`**); **Helm** and **legacy Kustomize** (**`secretGenerator`** → **`workbench-redis-secrets`**) use the same path.
- **Kubernetes / Helm:** charts live under **`devops/`** (**`crds/`**, **`platform/`**, **`infra/`**, **`apps/`**, **`workbench-crds-umbrella/`**, **`workbench-umbrella/`**; chart dirs use the **`workbench-`** prefix where applicable, e.g. **`platform/workbench-namespaces/`**). **Apply** the full stack with **`./scripts/helm-apply.sh`** (CRDs/operators first, then main umbrella; see **[`devops/README.md`](../devops/README.md)**). Legacy Kustomize manifests under **`devops/k8s/`** are documented in **[`devops/k8s/README.md`](../devops/k8s/README.md)** (**`devops/kustomization.yaml`** is deprecated).

Other infrastructure-as-code (Terraform, raw YAML, additional charts, CI) can live under **`devops/`** as you add it.

### `local/`

Local-only material: environment samples, helper scripts, and Docker Compose files. Nothing here is required for production clusters; it supports developing and testing on a single machine. **RabbitMQ** and **Redis** config files live under each Helm chart’s **`files/`** directory (see **`devops/`** above); Compose bind-mounts those paths into containers.

## Docker Compose

Workbench **v1** app path in [Workbench demo spec](workbench-demo-spec.md) uses **PostgreSQL** and **RabbitMQ** only; **Redis** is still included in Compose so you can practice cache/idempotency patterns after v1 without changing the file layout.

| File                                                                    | Purpose                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| ----------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`local/docker-compose.infra.yaml`](../local/docker-compose.infra.yaml) | **Infrastructure only** — `postgres`, `rabbitmq` (management **15672**), `redis` (**6379**). Postgres uses user/password/database **`workbench`**. **RabbitMQ** mounts **[`devops/infra/workbench-rabbitmq/files/`](../devops/infra/workbench-rabbitmq/files/)** at boot; **Redis** mounts **[`devops/infra/workbench-redis/files/workbench.conf`](../devops/infra/workbench-redis/files/workbench.conf)**. No bind or named volumes: data is **ephemeral** for local resets. |
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
- `RabbitMq__Uri` → `amqp://workbench:workbench@rabbitmq:5672/` (user/password are defined in **[`devops/infra/workbench-rabbitmq/files/definitions.json`](../devops/infra/workbench-rabbitmq/files/definitions.json)**; change the hash there if you rotate the password)
- `Redis__ConnectionString` → `redis:6379` (StackExchange.Redis–style endpoint; no password in local Compose)

These credentials are for **local practice only**; do not reuse in production.

Typical usage (from the **repository root**):

```bash
docker compose -f local/docker-compose.infra.yaml up -d
docker compose -f local/docker-compose.yaml up --build
```

Use the first when you only need Postgres, RabbitMQ, and Redis; use the second for infra plus all app images. Add `-d` for detached mode if you prefer.

**Compose wizard:** **`./scripts/compose-wizard.sh`** — interactive menu or **`./scripts/compose-wizard.sh all`** for build → push (ACR) → **`up -d`** (`INCLUDE_JOBS=1` includes the jobs profile for build/push).

## Relation to the workbench demo

The application built under `src/` is intended to align with [Workbench demo spec](workbench-demo-spec.md) so platform experiments (Gateway API, observability, secrets, policies) stay on one coherent system instead of one-off demos.
