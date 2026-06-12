# DevOps (Helm)

This directory (**`devops/`**) holds **Helm charts**, **values overlays**, and **legacy Kustomize** manifests for Workbench. Charts ship minimal **`values.yaml`** files; shared defaults live under **`platform/values/`**, and per-cluster overrides under **`clusters/<cluster-name>/`**.

**Preferred install:** cluster platform layer (Istio, Gateway API, RabbitMQ operator — see e2e scripts), then main umbrella via `./scripts/helm-apply.sh` from the repository root.

## Layout

```text
devops/
  README.md
  kustomization.yaml      # legacy full-stack Kustomize (deprecated)
  k8s/                    # legacy manifests (reference)
  platform/
    workbench-common/       # library chart (shared templates)
    workbench-namespaces/
    workbench-apps-secrets/
    workbench-storage-classes/
    workbench-policies/     # LimitRange, ResourceQuota, PDB, sample NetworkPolicy
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
      global-values.yaml    # kind / dev — connection strings + lean replicas
    aks/
      global-values.yaml    # AKS 3x Standard_D2s_v3 — same sizing targets
  workbench-umbrella/       # platform, infra, and apps (not CRDs/operators)
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
- **`global.imageRegistry`** (`workbenchacr77.azurecr.io`) — app chart images render as `<registry>/<repository>:<tag>` (e.g. `workbenchacr77.azurecr.io/workbench-api:1.0.0-rc1`).
- Cluster overlay fills broker/cache/db connection strings and credentials (**`global.workbenchPostgres.*`**, **`global.workbenchRabbitMq.user` / `password` / `uri`**, **`global.workbenchRedis.*`**). RabbitMQ **`user` / `password`** feed the operator **`workbench-rabbitmq-default-user`** Secret; **`definitions.json`** still declares the same user (password hash) for Compose/Kustomize and boot import. Keep values aligned with the hash in **`definitions.json`** (local default: **`workbench` / `workbench`**).
- **Local kind:** app images use **`workbenchacr77.azurecr.io/...`** from **`global.imageRegistry`** (same as AKS). Build with **`./scripts/compose-wizard.sh build`** (buildx; push creates **`linux/amd64,linux/arm64`** manifest).

## Full stack install

From the repository root (after kind cluster, cluster platform installs, infra node label, volumes, and images — see **`devops/k8s/README.md`** prerequisites):

```bash
# Cluster platform (once per cluster; also run by kind-e2e-first-run.sh / aks-e2e-first-run.sh):
./scripts/istio-helm-install.sh      # Istio ambient + Gateway API CRDs
./scripts/rabbitmq-install.sh        # RabbitMQ Cluster Operator

./scripts/helm-apply.sh
# AKS (3x Standard_D2s_v3):
HELM_CLUSTER=aks ./scripts/helm-apply.sh
```

**Resource sizing:** chart defaults use **Burstable** QoS and low **requests** so the full stack schedules on small nodes (~**1.2 CPU** / **~1.8 GiB** requests cluster-wide with API×2). See **`clusters/aks/global-values.yaml`** for replica and quota overrides.

**First-time kind setup (all steps):** **`./scripts/kind-e2e-first-run.sh`** — Helm apply by default; pass **`--k8s`** for legacy Kustomize.

Dry-run against the API:

```bash
./scripts/helm-apply.sh --dry-run
# or: ./scripts/helm-apply.sh --dry-run=server
```

The script runs **`./scripts/helm-dependency-update.sh`** (subcharts with **`workbench-common`**, then main umbrella), then **`helm upgrade --install`** for **`workbench-umbrella-<cluster>`** (`devops/workbench-umbrella`) — platform (incl. **`workbench-public-gateway`**), infra, apps (incl. **HTTPRoutes** on **`workbench-api`** and **`workbench-app`**). Install **`./scripts/rabbitmq-install.sh`** (and Istio) as cluster platform steps before apply.

The main stack uses **`workbench-platform`** (`HELM_NAMESPACE`) and owns that namespace via **`workbench-namespaces`**. Override **`HELM_RELEASE`**. **`HELM_HISTORY_MAX`** applies to the umbrella upgrade.

Install the RabbitMQ operator ([upstream manifest](https://www.rabbitmq.com/kubernetes/operator/install-operator)) as a cluster platform step (not part of **`helm-apply`**):

```bash
./scripts/rabbitmq-install.sh
# Pin version: RABBITMQ_OPERATOR_VERSION=v2.21.0 ./scripts/rabbitmq-install.sh
```

**`./scripts/helm-destroy.sh`** uninstalls **`workbench-umbrella-<cluster>`** only (apps/infra/platform subcharts, including gateway and HTTPRoutes) so you can **`helm-apply`** again without recreating the cluster. **Istio** (ambient Helm install), **Gateway API CRDs**, and the **RabbitMQ Cluster Operator** stay installed by default; pass **`--with-crds`** to remove the operator via **`./scripts/rabbitmq-install.sh --uninstall`**. Cluster-scoped **CRD** objects may remain until deleted manually.

**Failed or pending upgrade** (e.g. `pending-upgrade`, schema errors mid-apply):

```bash
./scripts/helm-recover.sh --cluster local -y   # rollback if possible, else uninstall
./scripts/helm-apply.sh
```

Requires **`jq`**. For RabbitMQ operator issues, re-run **`./scripts/rabbitmq-install.sh`**.

After apply, verify:

```bash
kubectl get crd rabbitmqclusters.rabbitmq.com
kubectl get pods -n rabbitmq-system
kubectl get rabbitmqclusters -n workbench-infra
kubectl get pvc -n workbench-infra
```

**RabbitMQ sizing (local kind):** [`clusters/local/global-values.yaml`](clusters/local/global-values.yaml) sets **`workbench-rabbitmq.replicas: 1`** (chart default is **3** at **1 CPU** each). Infra charts (**Postgres**, **RabbitMQ**, **Redis**) use **`replicas`**; app charts use **`replicaCount`**.

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

### Container images (ACR)

Workbench app images use **`workbenchacr77.azurecr.io`** (`global.imageRegistry` in **`platform/values/global-values.yaml`**). Infra images (Postgres, RabbitMQ, Redis) stay on Docker Hub.

```bash
ACR=workbenchacr77.azurecr.io
az acr login --name workbenchacr77
docker build -t "${ACR}/workbench-api:1.0.0-rc1" -f src/Workbench.Api/Dockerfile src
docker push "${ACR}/workbench-api:1.0.0-rc1"
# repeat for workbench-worker, workbench-jobs, workbench-app, workbench-local-gateway
az aks update -g workbench -n workbench-aks --attach-acr workbenchacr77   # pull from AKS
```

After chart edits: **`./scripts/helm-dependency-update.sh`** (or manually **`helm dependency update`** on each dependent chart, then main umbrella) before install — refreshes vendored subcharts.

**Library chart:** app and infra charts depend on **`workbench-common`** for shared helpers (`workbench.lib.image`, `workbench.lib.namespace.*`, `workbench.lib.labels.*`, `workbench.lib.infraNode.affinity`). Chart-specific templates (e.g. **`workbench.app.config.js`**) stay in the owning chart.

**`workbench-namespaces`**: can lint with platform values only.

For an interactive menu, use **`./scripts/helm-wizard.sh`**.

## Charts

| Path                                 | Chart name                  | Role                                            |
| ------------------------------------ | --------------------------- | ----------------------------------------------- |
| `platform/workbench-common`          | —                           | Library chart (`workbench.lib.*` templates)     |
| `platform/workbench-namespaces`      | `workbench-namespaces`      | Namespace objects                               |
| `platform/workbench-storage-classes` | `workbench-storage-classes` | `local-storage` StorageClass                    |
| `platform/workbench-apps-secrets`    | `workbench-apps-secrets`    | Apps-namespace broker/cache Secret              |
| `platform/workbench-policies`        | `workbench-policies`        | LimitRange, ResourceQuota, RabbitMQ PDB, sample worker NetworkPolicy |
| `infra/workbench-postgres`           | `workbench-postgres`        | Postgres StatefulSet, PV, db Secret             |
| `infra/workbench-rabbitmq`           | `workbench-rabbitmq`        | `RabbitmqCluster` CR, `{name}-default-user` Secret, definitions ConfigMap |
| `infra/workbench-redis`              | `workbench-redis`           | Redis StatefulSet, config Secret                |
| `apps/workbench-api`                 | `workbench-api`             | API Deployment + Service                        |
| `apps/workbench-worker`              | `workbench-worker`          | Worker Deployment + Service                     |
| `apps/workbench-jobs`                | `workbench-jobs`            | Cleanup CronJob                                 |
| `apps/workbench-app`                 | `workbench-app`             | Frontend Deployment + Service (nginx)           |
| `workbench-umbrella`                 | `workbench-umbrella`        | Platform, infra, and apps (not CRDs/operators)  |

## Release name convention

```text
<app>-<env>
```

Examples: **`workbench-umbrella-local`** (in **`workbench-platform`**), **`workbench-namespaces-local`**.

### Migrating from CRDs umbrella

If the cluster still has a legacy **`workbench-crds-umbrella-<cluster>`** Helm release (operator was previously installed via Helm):

```bash
helm uninstall workbench-crds-umbrella-local -n kube-system   # if release exists
./scripts/rabbitmq-install.sh
```

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
