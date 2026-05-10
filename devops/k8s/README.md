# Kubernetes (local cluster)

This directory holds Kubernetes-oriented notes and manifests for the Workbench learning stack. Start from a working cluster before applying anything here.

## Repository layout for Kustomize (templates)

Work in this monorepo treats **`devops/k8s/`** as the **Kubernetes root** (`<k8s-root>`). The same hierarchy can live under `kubernetes/` or another folder elsewhere; keep the **inner structure** consistent so apps, cluster glue, and platform concerns stay separated.

```text
<k8s-root>/
├── apps/
│   ├── payment-service/
│   │   ├── base/
│   │   │   ├── deployment.yaml
│   │   │   ├── service.yaml
│   │   │   ├── configmap.yaml
│   │   │   ├── secrets.yaml
│   │   │   ├── hpa.yaml
│   │   │   ├── pdb.yaml
│   │   │   └── kustomization.yaml
│   │   │
│   │   ├── overlays/
│   │   │   ├── local-kind/
│   │   │   ├── dev/
│   │   │   ├── staging/
│   │   │   └── prod/
│   │   │
│   │   └── …
│   │
│   └── auth-service/
│       └── …
│
├── infrastructure/
│   ├── ingress-nginx/
│   ├── cert-manager/
│   ├── prometheus/
│   ├── loki/
│   ├── cilium/
│   └── istio/
│
├── clusters/
│   ├── dev/
│   ├── staging/
│   └── prod/
│
├── platform/
│   ├── namespaces/
│   ├── network-policies/
│   ├── rbac/
│   ├── limitranges/
│   └── policies/
│
└── scripts/
```

| Area                  | Role                                                                                                                                                                                                                                                                    |
| --------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **`apps/`**           | One directory per workload (microservice). **`base/`** holds the canonical Kustomize resources; **`overlays/<env>/`** patches images, replicas, resources, namespaces, and env-specific config. Optional **`hpa.yaml`**, **`pdb.yaml`** when you practice HA (roadmap). |
| **`infrastructure/`** | Cluster add-ons and third-party stacks (ingress controller, certs, mesh, observability). Often Helm-rendered or upstream manifests wrapped in Kustomize—keep them separate from app **Deployments**.                                                                    |
| **`clusters/`**       | Environment- or cluster-level **entrypoints**: what Argo CD, Flux, or humans **`apply`** per cluster (e.g. one **`kustomization.yaml`** root per **`dev`** / **`staging`** / **`prod`** that pulls **`apps/*`** and **`platform/*`**).                                  |
| **`platform/`**       | Shared policies: **NetworkPolicy**, **RBAC**, **LimitRange**, org guardrails—referenced by cluster roots instead of duplicated per app.                                                                                                                                 |
| **`scripts/`**        | Helper **`kubectl`**, **`kustomize build`**, bootstrap, or CI glue—no long-lived YAML required.                                                                                                                                                                         |

**This repo today:** under **`apps/`** you will find **`workbench-api`** (and can add **`workbench-worker`**, **`workbench-app`**, …) following the same **`base/` + `overlays/`** pattern; **`infrastructure/`**, **`clusters/`**, **`platform/`**, and **`scripts/`** can grow as roadmap items land.

## Label convention (Kubernetes recommended labels)

Use the upstream **[recommended labels](https://kubernetes.io/docs/concepts/overview/working-with-objects/common-labels/)** (`app.kubernetes.io/*`). Common keys only:

| Label                              | Purpose                                                                           |
| ---------------------------------- | --------------------------------------------------------------------------------- |
| **`app.kubernetes.io/name`**       | Logical application name (e.g. `workbench-api`).                                  |
| **`app.kubernetes.io/instance`**   | Distinct deployment of that app (e.g. `workbench-api-prod`, `workbench-api-dev`). |
| **`app.kubernetes.io/version`**    | Application version (often image or semver), e.g. `1.0.0-rc1`.                    |
| **`app.kubernetes.io/component`**  | Role in the architecture, e.g. `api`, `worker`, `database`.                       |
| **`app.kubernetes.io/part-of`**    | Larger product or system this resource belongs to, e.g. `workbench`.              |
| **`app.kubernetes.io/managed-by`** | Tool that created/manages the resource, e.g. `helm`, `kustomize`, `argocd`.       |

This repo uses **`name`** + **`component`** everywhere for selectors; add **`instance`**, **`version`**, **`part-of`**, and **`managed-by`** when Helm, GitOps, or multi-env naming needs them. Do not duplicate app identity with extra custom keys when **`name`** (and **`instance`** if needed) already cover it.

- **Selectors:** **`matchLabels`** / **`Service.spec.selector`** should include at least **`app.kubernetes.io/name`**; include **`app.kubernetes.io/component`** when one chart or repo hosts multiple workloads with distinct roles (e.g. **`api`** vs **`worker`**).

**Common `app.kubernetes.io/component` values** (repo convention—pick one per workload; add others only when needed):

| Value            | Meaning                                                        |
| ---------------- | -------------------------------------------------------------- |
| **`api`**        | HTTP API service                                               |
| **`frontend`**   | UI / frontend                                                  |
| **`backend`**    | Backend service (non-API app tier, if distinct from **`api`**) |
| **`worker`**     | Async / background worker                                      |
| **`database`**   | Database component                                             |
| **`cache`**      | Redis / cache                                                  |
| **`queue`**      | Queue broker                                                   |
| **`scheduler`**  | Cron / scheduled jobs                                          |
| **`proxy`**      | Proxy / gateway                                                |
| **`controller`** | Operator / controller                                          |

Pair each **`component`** with **`app.kubernetes.io/name`** (e.g. `name: workbench-api`, `component: api`).

- **Non-selector labels** (`instance`, `version`, `part-of`, `managed-by`) use **`includeSelectors: false`** and **`includeTemplates: true`** in **`kustomization.yaml`** so they appear on **object metadata** and **Pod templates** but stay out of **Deployment / Service** selectors (avoid coupling rollouts to version changes).

**Arbitrary domain keys:** there is no recommended **`environment`** label in the common set. For deploy-target hints (e.g. `local-kind`, `prod`), use a DNS-valid prefix such as **`workbench.io/environment`** on metadata only—never on **`matchLabels`** / **`Service`** selectors unless every pod in that tier shares the value.

## Namespaces

Workbench uses several namespaces so DNS and RBAC can target tiers without mixing concerns. All are defined under **`platform/namespaces/`** and share **`app.kubernetes.io/part-of: workbench`** plus **`workbench.io/purpose`** for humans and policies.

| Namespace              | `workbench.io/purpose` | Intended workloads                                                                 |
| ---------------------- | ---------------------- | ---------------------------------------------------------------------------------- |
| **`workbench-system`** | **`system`**           | First-party apps: **API**, **worker**, **UI**, platform **Secrets** used today.    |
| **`workbench-db`**     | **`database`**         | **PostgreSQL** (operators, StatefulSets, jobs, backups).                          |
| **`workbench-storage`** | **`storage`**          | Object/block storage integrations, CSI-related app components, volume helpers.   |
| **`workbench-infra`**  | **`shared-infra`**     | Cluster add-ons scoped to this product: **ingress**, **cert-manager**, brokers, cache, mesh ingress, etc.—keep separate from **`apps/`** Deployments. |

**Today:** **`workbench-api`** and **`workbench-worker`** Kustomize bases still target **`workbench-system`** only. As you add Postgres/RabbitMQ/Redis to the cluster, place their namespaces **`workbench-db`** / **`workbench-infra`** (or split further) and point **Services** / **Secrets** from app overlays accordingly.

Apply every namespace at once:

```bash
kubectl apply --server-side -k devops/k8s/platform/namespaces
```

## Applying manifests (prefer server-side apply)

For declarative YAML in this repo, **prefer [server-side apply](https://kubernetes.io/docs/reference/using-api/server-side-apply/)** over default client-side `kubectl apply` when your cluster supports it. The apiserver tracks **field managers** and ownership; that scales better with GitOps and multiple controllers and avoids stuffing large `last-applied-configuration` annotations on objects.

Examples:

```bash
kubectl apply --server-side -k devops/k8s/platform/namespaces
# workbench-api base — files under base/ are Kustomize fragments; use -k (not plain -f on that directory)
kubectl apply --server-side -k devops/k8s/apps/workbench-api/base
```

With the **`local-kind`** overlay (**[`apps/workbench-api/overlays/local-kind/kustomization.yaml`](apps/workbench-api/overlays/local-kind/kustomization.yaml)**): **1 replica**, metadata label **`workbench.io/environment: local-kind`** (not a Kubernetes **`app.kubernetes.io/*`** key; **not on selectors**). Needs namespace, **Postgres / RabbitMQ / Redis** Services matching **`base` Secrets**, and the image on kind nodes:

```bash
# repo root — build and load (use your kind cluster name if not workbench-0)
docker build -t workbench/workbench-api:1.0.0-rc1 -f src/Workbench.Api/Dockerfile src
kind load docker-image workbench/workbench-api:1.0.0-rc1 --name workbench-0

kubectl apply --server-side -k devops/k8s/platform/namespaces
kubectl apply --server-side -k devops/k8s/apps/workbench-api/overlays/local-kind
# preview: kubectl kustomize devops/k8s/apps/workbench-api/overlays/local-kind
```

Other overlays: **`kubectl apply --server-side -k devops/k8s/apps/workbench-api/overlays/<env>`** when **`kustomization.yaml`** exists.

If you hit ownership conflicts during adoption, see **`kubectl apply --server-side --help`** (e.g. **`--force-conflicts`** only when you intend to overwrite other managers’ fields). For CI and production, align field managers and manifests so conflicts stay rare.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) (or another container runtime kind supports)
- [kind](https://kind.sigs.k8s.io/docs/user/quick-start/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/) aligned with your cluster version

## Instructions

### 1. Create a local cluster

Create your first cluster with a fixed name so `kubectl` can target it reliably:

```bash
kind create cluster -n workbench-0
```

`kind` merges kubeconfig entries into your default config (usually `~/.kube/config`) and sets the current context to `kind-workbench-0`.

### 2. Verify access

```bash
kubectl cluster-info
kubectl get nodes
```

### 3. Switch context (if you use multiple clusters)

```bash
kubectl config get-contexts
kubectl config use-context kind-workbench-0
```

### 4. Delete the cluster (when finished)

```bash
kind delete cluster -n workbench-0
```

For more options (extra nodes, port mappings, custom kubeconfig path), see [kind configuration](https://kind.sigs.k8s.io/docs/user/configuration/).
