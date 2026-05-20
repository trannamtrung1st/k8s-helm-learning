# DevOps (Helm)

This directory (**`devops/`**) holds **Helm charts**, **values overlays**, and **legacy Kustomize** manifests for Workbench. Charts ship minimal **`values.yaml`** files; shared defaults live under **`platform/values/`**, and per-cluster overrides under **`clusters/<cluster-name>/`**.

**Preferred install:** umbrella chart + `./scripts/helm-apply.sh` from the repository root.

## Layout

```text
devops/
  README.md
  kustomization.yaml      # legacy full-stack Kustomize (deprecated)
  k8s/                    # legacy manifests (reference)
  platform/
    workbench-namespaces/
    workbench-apps-secrets/
    workbench-storage-classes/
    workbench-policies/     # LimitRange, ResourceQuota, PDB
    values/
      global-values.yaml
  infra/
    workbench-postgres/
    workbench-rabbitmq/     # files/definitions.json, files/conf.d/…
    workbench-redis/        # files/workbench.conf
  apps/
    workbench-api/
    workbench-worker/
    workbench-jobs/         # cleanup CronJob
    workbench-app/          # React SPA (nginx)
  clusters/
    local/
      global-values.yaml    # connection strings + local-kind replica overlays
  workbench-umbrella/       # all charts above
    Chart.yaml
    Chart.lock
    charts/                 # vendored .tgz (refresh after subchart edits)
```

**RabbitMQ** and **Redis** config files live under each chart’s **`files/`** directory. **Docker Compose**, **Helm** (`.Files.Get`), and **legacy Kustomize** (`configMapGenerator` / `secretGenerator` in **`kustomization.yaml`**) all read the same paths so local and cluster stay aligned.

Legacy Kustomize manifests remain under **`devops/k8s/`** for reference; **`devops/kustomization.yaml`** is deprecated in favor of Helm.

## Values chain

Helm merges values in order: packaged chart **`values.yaml`**, then each **`-f`** file left to right. **Later files win** on duplicate keys.

```text
-f devops/platform/values/global-values.yaml \
-f devops/clusters/local/global-values.yaml
```

- **`global.*`** propagates to every subchart (namespaces, secrets, infra, apps).
- Cluster overlay fills broker/cache/db connection strings and credentials (**`global.workbenchPostgres.*`**, **`global.workbenchRabbitMq.uri`**, **`global.workbenchRedis.*`**). Infra charts leave **`user` / `password` / `database`** empty in packaged **`values.yaml`**; **`clusters/<cluster>/global-values.yaml`** supplies them.

## Full stack install

From the repository root (after kind cluster, infra node label, volumes, and images — see **`devops/k8s/README.md`** prerequisites):

```bash
./scripts/helm-apply.sh
```

**First-time kind setup (all steps):** **`./scripts/kind-e2e-first-run.sh`** — Helm apply by default; pass **`--k8s`** for legacy Kustomize.

Dry-run against the API:

```bash
./scripts/helm-apply.sh --dry-run
# or: ./scripts/helm-apply.sh --dry-run=server
```

The script runs **`helm dependency update`** on the umbrella chart, then **`helm upgrade --install`** with **`--history-max 5`**. Release name defaults to **`workbench-umbrella-local`** in namespace **`workbench-platform`** (`HELM_RELEASE`, `HELM_NAMESPACE`, and `HELM_HISTORY_MAX` override).

## Lint and template

```bash
helm lint devops/workbench-umbrella \
  -f devops/platform/values/global-values.yaml \
  -f devops/clusters/local/global-values.yaml

helm template umbrella devops/workbench-umbrella \
  -f devops/platform/values/global-values.yaml \
  -f devops/clusters/local/global-values.yaml
```

**`workbench-apps-secrets`**: **`values.schema.json`** requires merged **`global.*`** including non-empty broker strings — always pass **both** `-f` files for that chart or the umbrella.

**`workbench-namespaces`**: can lint with platform values only.

For an interactive menu, use **`./scripts/helm-wizard.sh`**.

## Charts

| Path                                 | Chart name                  | Role                                            |
| ------------------------------------ | --------------------------- | ----------------------------------------------- |
| `platform/workbench-namespaces`      | `workbench-namespaces`      | Namespace objects                               |
| `platform/workbench-storage-classes` | `workbench-storage-classes` | `local-storage` StorageClass                    |
| `platform/workbench-apps-secrets`    | `workbench-apps-secrets`    | Apps-namespace broker/cache Secret              |
| `platform/workbench-policies`        | `workbench-policies`        | LimitRange, ResourceQuota, RabbitMQ PDB         |
| `infra/workbench-postgres`           | `workbench-postgres`        | Postgres StatefulSet, PV, db Secret             |
| `infra/workbench-rabbitmq`           | `workbench-rabbitmq`        | RabbitMQ StatefulSet, definitions ConfigMap, PV |
| `infra/workbench-redis`              | `workbench-redis`           | Redis StatefulSet, config Secret                |
| `apps/workbench-api`                 | `workbench-api`             | API Deployment + Service                        |
| `apps/workbench-worker`              | `workbench-worker`          | Worker Deployment + Service                     |
| `apps/workbench-jobs`                | `workbench-jobs`            | Cleanup CronJob                                 |
| `apps/workbench-app`                 | `workbench-app`             | Frontend Deployment + Service (nginx)           |
| `workbench-umbrella`                 | `workbench-umbrella`        | All of the above                                |

## Release name convention

```text
<app>-<env>
```

Examples: **`workbench-umbrella-local`**, **`workbench-namespaces-local`**. Platform charts typically install into **`workbench-platform`**.

## Single-chart examples

**Namespaces:**

```bash
helm upgrade --install namespaces devops/platform/workbench-namespaces/ \
  --server-side=true -n workbench-platform --create-namespace \
  -f devops/platform/values/global-values.yaml \
  -f devops/clusters/local/global-values.yaml
```

**Postgres only:**

```bash
helm upgrade --install postgres devops/infra/workbench-postgres/ \
  --server-side=true \
  -f devops/platform/values/global-values.yaml \
  -f devops/clusters/local/global-values.yaml
```

See also **`devops/k8s/README.md`** for cluster prerequisites (kind, node labels, volumes, image load).
