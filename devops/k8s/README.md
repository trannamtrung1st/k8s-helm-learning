# Kubernetes (local cluster)

This directory is the Kubernetes root for the Workbench learning stack.

Use Kustomize entrypoints (`kubectl apply -k ...`) instead of applying raw files from `base/` folders.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/)
- [kind](https://kind.sigs.k8s.io/docs/user/quick-start/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)

## Quick start

From repo root:

```bash
# apply all resources (platform + infra + apps)
kubectl apply --server-side -k devops/k8s

# delete all resources
kubectl delete --server-side -k devops/k8s
```

Helper scripts:

```bash
./scripts/k8s-apply.sh
./scripts/k8s-delete.sh
./scripts/k8s-events.sh                 # all namespaces
./scripts/k8s-events.sh workbench-infra # one namespace
./scripts/k8s-events.sh all Failed      # filter by reason
```

## What top-level Kustomize applies

`devops/k8s/kustomization.yaml` applies resources in this intent order:

1. platform prerequisites
   - `platform/namespaces`
   - `platform/storageclasses/local-storage.yaml`
   - `platform/secrets/workbench-platform-secrets.yaml`
2. infra dependencies
   - `infra/workbench-postgres-db/base`
   - `infra/workbench-rabbitmq/base`
   - `infra/workbench-redis/base`
3. app workloads (local-kind overlays)
   - `apps/workbench-api/overlays/local-kind`
   - `apps/workbench-worker/overlays/local-kind`

## Repository layout

```text
devops/k8s/
├── apps/                 # first-party workloads (base + overlays)
├── infra/                # product infrastructure (postgres, rabbitmq, redis, ...)
├── platform/             # namespaces, storageclasses, shared secrets/policies
└── kustomization.yaml    # top-level apply entrypoint
```

## Namespaces

- `workbench-system`: first-party workloads (API, worker, UI)
- `workbench-db`: database tier
- `workbench-infra`: shared infra tier (broker/cache/etc.)
- `workbench-storage`: storage tier

Apply namespaces only:

```bash
kubectl apply --server-side -k devops/k8s/platform/namespaces
```

## Local kind workflow

### 1) Create and verify cluster

```bash
kind create cluster -n workbench-0
kubectl config use-context kind-workbench-0
kubectl cluster-info
kubectl get nodes
```

### 2) Build and load local images

```bash
docker build -t workbench/workbench-api:1.0.0-rc1 -f src/Workbench.Api/Dockerfile src
docker build -t workbench/workbench-worker:1.0.0-rc1 -f src/Workbench.Worker/Dockerfile src

kind load docker-image workbench/workbench-api:1.0.0-rc1 --name workbench-0
kind load docker-image workbench/workbench-worker:1.0.0-rc1 --name workbench-0
```

### 3) Apply manifests

```bash
kubectl apply --server-side -k devops/k8s
```

### 4) Verify workloads

```bash
kubectl get ns
kubectl get pods -n workbench-db
kubectl get pods -n workbench-infra
kubectl get pods -n workbench-system
kubectl get svc -n workbench-infra
kubectl get svc -n workbench-system
```

### 5) Delete cluster

```bash
kind delete cluster -n workbench-0
```

## Kustomize usage notes

- Prefer server-side apply in this repo: `kubectl apply --server-side -k ...`
- Preview rendered manifests without applying: `kubectl kustomize devops/k8s`
- If ownership conflicts appear, check `kubectl apply --server-side --help`
- Use `--force-conflicts` only intentionally

## Overlay usage

Use overlays via Kustomize:

```bash
kubectl apply --server-side -k devops/k8s/apps/workbench-api/overlays/local-kind
kubectl apply --server-side -k devops/k8s/apps/workbench-api/overlays/<env>
```

For `local-kind`, ensure:

- namespace resources are applied
- dependent services (Postgres/RabbitMQ/Redis) exist and match secret references
- local images are built and loaded into kind nodes

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

## Config and secrets guidance

- Small config: use `ConfigMap` / `Secret` with Kustomize generators
- Large blobs or file trees: prefer volumes (PVC/CSI/external store/init sync)
- Avoid oversized ConfigMaps/Secrets for data that should live outside the Kubernetes object API
