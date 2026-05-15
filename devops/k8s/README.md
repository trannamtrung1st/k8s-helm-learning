# Kubernetes (local cluster)

> **Migration:** The full stack is now available as Helm charts under **`devops/helm/`**. Prefer **`./scripts/helm-apply.sh`** from the repository root. Kustomize under **`devops/k8s/`** and **`devops/kustomization.yaml`** remain for reference; new changes belong in Helm.

This directory (**`devops/k8s/`**) holds **legacy manifests** (apps, infra, platform). The **top-level Kustomize entrypoint** is **`devops/kustomization.yaml`** (one directory up): apply with **`kubectl apply -k devops`** from the repository root so **RabbitMQ** and **Redis** `ConfigMap` / `Secret` generators can read canonical files from **`devops/rabbitmq/`** and **`devops/redis/`** without duplicating them under **`k8s/`**.

**Naming:** folders and YAML filenames under **`k8s/`** use **kebab-case** (for example `platform/storage-classes/`, `config-map.yaml`, `stateful-set.yaml`, `persistent-volume.yaml`) so paths stay readable and consistent.

Apply manifests through Kustomize entrypoints (`kubectl apply -k devops` or `./scripts/k8s-apply.sh` from the **repository root**), not by applying raw files from individual `base/` folders unless you know you want that.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/)
- [kind](https://kind.sigs.k8s.io/docs/user/quick-start/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)

## First run (kind, from repo root)

Run these from the **repository root** so script paths and **`devops/`** / **`devops/k8s/`** resolve correctly.

1. **Create the kind cluster** — use the interactive wizard (worker count, delete/recreate, list clusters):

   ```bash
   ./scripts/kind-wizard.sh
   ```

   Non-interactive examples: `./scripts/kind-wizard.sh create --name workbench-0 --workers 1`, `./scripts/kind-wizard.sh recreate --name workbench-0 --workers 0`.

   Then point kubectl at the cluster (kind sets this after create; if needed):

   ```bash
   kubectl config use-context kind-workbench-0
   kubectl get nodes
   ```

2. **Label the infra node** — Postgres and RabbitMQ use **local** PVs under `/mnt/disks/...` with **node affinity** to `workbench.io/infra-node=true`. Pick the node that will host those paths (often a **worker** on multi-node kind; the only node on single-node clusters). The Kubernetes **node name** matches the kind **Docker container name** (for example `workbench-0-worker`).

   ```bash
   ./scripts/k8s-node-label-wizard.sh
   ```

   Or with kubectl:

   ```bash
   kubectl get nodes
   kubectl label node <your-infra-node-name> workbench.io/infra-node=true --overwrite
   ```

3. **Create volume directories on labeled nodes** — `docker exec` on every node with that label:

   ```bash
   ./scripts/k8s-volumes-init.sh
   ```

   Override discovery: `./scripts/k8s-volumes-init.sh --node <kind-container-name>`.

4. **Build and load workload images into kind** — build locally, then load (cluster name must match kind, default `workbench-0`):

   ```bash
   docker build -t workbench/workbench-api:1.0.0-rc1 -f src/Workbench.Api/Dockerfile src
   docker build -t workbench/workbench-worker:1.0.0-rc1 -f src/Workbench.Worker/Dockerfile src

   ./scripts/kind-load-images.sh --cluster workbench-0
   ```

5. **Apply the stack** — Helm (recommended):

   ```bash
   ./scripts/helm-apply.sh
   ```

   Legacy Kustomize equivalent:

   ```bash
   ./scripts/k8s-apply.sh
   ```

**Verify**

```bash
kubectl get ns
kubectl get pods -n workbench-db
kubectl get pods -n workbench-infra
kubectl get pods -n workbench-apps
kubectl get svc -n workbench-infra
kubectl get svc -n workbench-apps
```

If Postgres or RabbitMQ stay **Pending**, confirm the infra label and that `./scripts/k8s-volumes-init.sh` ran successfully on those nodes.

**Clear local PV data** (destructive): `./scripts/k8s-volumes-clear.sh --yes` — same node discovery by `workbench.io/infra-node=true`, or pass `--node` once.

**Delete the kind cluster**: `./scripts/kind-wizard.sh` → option 3, or `kind delete cluster --name workbench-0`.

## Day-two commands (repo root)

```bash
./scripts/k8s-apply.sh
./scripts/k8s-delete.sh
./scripts/k8s-events.sh                 # all namespaces
./scripts/k8s-events.sh workbench-infra # one namespace
./scripts/k8s-events.sh all Failed      # filter by reason
./scripts/k8s-port-forward.sh -n workbench-apps svc/workbench-api 8080:80
```

Raw kubectl equivalents:

```bash
kubectl apply --server-side --force-conflicts -k devops
kubectl delete --server-side -k devops
```

## What top-level Kustomize applies

**`devops/kustomization.yaml`** lists **`k8s/...`** resources and **Kustomize generators** for shared broker/cache files:

- **`configMapGenerator`** → **`workbench-rabbitmq-definitions`** in **`workbench-infra`** from **`rabbitmq/definitions.json`** and **`rabbitmq/conf.d/10-workbench-definitions.conf`** (same sources as Docker Compose).
- **`secretGenerator`** → **`workbench-redis-secrets`** in **`workbench-infra`** from **`redis/workbench.conf`**.

Resources are applied in this intent order:

1. platform prerequisites  
   - `k8s/platform/namespaces`  
   - `k8s/platform/storage-classes/local-storage.yaml`  
   - `k8s/platform/secrets/workbench-apps-secrets.yaml`  
2. infra dependencies  
   - `k8s/infra/workbench-postgres-db/base`  
   - `k8s/infra/workbench-rabbitmq/base`  
   - `k8s/infra/workbench-redis/base`  
3. app workloads (local-kind overlays)  
   - `k8s/apps/workbench-api/overlays/local-kind`  
   - `k8s/apps/workbench-worker/overlays/local-kind`  
   - `k8s/apps/workbench-jobs/overlays/local-kind`  

The generated **`ConfigMap`** / **`Secret`** are merged with the same build as the **`StatefulSet`** references (`workbench-rabbitmq-definitions`, `workbench-redis-secrets`); **do not** apply **`k8s/infra/workbench-rabbitmq/base`** or **`k8s/infra/workbench-redis/base`** alone if you expect those mounts to exist—use **`kubectl apply -k devops`** (or the full tree) unless you supply equivalent objects another way.

## Repository layout

```text
devops/
├── kustomization.yaml    # top-level apply: k8s/ resources + CM/Secret generators
├── rabbitmq/             # canonical broker definitions (Compose + Kustomize)
├── redis/                # canonical redis config (Compose + Kustomize)
└── k8s/
    ├── apps/             # first-party workloads (base + overlays)
    ├── infra/            # postgres, rabbitmq, redis, ...
    ├── platform/         # namespaces, storage-classes, secrets, policies
    └── ...
```

## Namespaces

- `workbench-apps`: first-party workloads (API, worker, UI)
- `workbench-db`: database tier
- `workbench-infra`: shared infra tier (broker/cache/etc.)
- `workbench-storage`: storage tier

Apply namespaces only:

```bash
kubectl apply --server-side -k devops/k8s/platform/namespaces
```

## Local volumes and the infra node label

- PV manifests: `k8s/infra/workbench-postgres-db/base/persistent-volume.yaml`, `k8s/infra/workbench-rabbitmq/base/persistent-volume.yaml` — **required** affinity to `workbench.io/infra-node=true`.
- Volume scripts discover nodes with that label; keep **kubectl context** aligned with the kind cluster when using discovery.

## Kustomize usage notes

- Prefer server-side apply in this repo: `kubectl apply --server-side -k ...`
- Preview rendered manifests without applying: `kubectl kustomize devops`
- If ownership conflicts appear, check `kubectl apply --server-side --help`
- Use `--force-conflicts` only intentionally (`./scripts/k8s-apply.sh` includes it)

## Overlay usage

```bash
kubectl apply --server-side -k devops/k8s/apps/workbench-api/overlays/local-kind
kubectl apply --server-side -k devops/k8s/apps/workbench-api/overlays/<env>
```

Use this when you intentionally patch **only** that app. It **does not** include **`devops/kustomization.yaml`** generators (**RabbitMQ** definitions **ConfigMap**, **Redis** **Secret**) or other namespaces; for a **full stack** bring-up, apply **`devops`** (see **Day-two commands**).

For **`local-kind`** as a **full stack**, apply **`devops`**, ensure secrets match workloads, and **local images are built and loaded** (see **First run** step 4).

## Label convention

Use Kubernetes recommended labels (`app.kubernetes.io/*`) consistently:

- `app.kubernetes.io/name`
- `app.kubernetes.io/component`
- `app.kubernetes.io/instance`
- `app.kubernetes.io/version`
- `app.kubernetes.io/part-of`
- `app.kubernetes.io/managed-by`

Guidance:

- Keep selectors stable (`name`, optionally `component`)
- Do not include rollout-varying labels such as `version` in selectors
- For environment hints, use metadata-only domain labels such as `workbench.io/environment`
- For **local** infra volumes, use `workbench.io/infra-node=true` on every node that owns `/mnt/disks/` paths; volume init/clear scripts target the same label

## Config and secrets guidance

- Small config: use `ConfigMap` / `Secret` with Kustomize generators
- Large blobs or file trees: prefer volumes (PVC/CSI/external store/init sync)
- Avoid oversized ConfigMaps/Secrets for data that should live outside the Kubernetes object API
