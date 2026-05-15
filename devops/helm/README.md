# Helm

This directory (**`devops/helm/`**) holds **Helm charts** and **values overlays** for Workbench. Charts ship minimal **`values.yaml`** files; real defaults for platform charts live under **`platform/values/`**, and per-cluster overrides live under **`clusters/<cluster-name>/`**.

## Layout

```text
devops/helm/
  README.md
  platform/
    namespaces/              # Chart: workbench-namespaces (namespace manifests)
      Chart.yaml
      values.yaml              # Sparse defaults (see platform/values for real data)
      values.schema.json
      templates/
    secrets/                   # Chart: workbench-apps-secrets (apps Secret; RabbitMQ + Redis)
      Chart.yaml
      values.yaml
      values.schema.json
      templates/
    values/
      global-values.yaml     # Platform-wide global.* (umbrella-safe); empty broker fields
  clusters/
    local/
      global-values.yaml     # Cluster overlay — fills RabbitMQ URI + Redis connectionString
  umbrella/                  # Umbrella chart: workbench-umbrella
    Chart.yaml               # Depends on workbench-namespaces + workbench-apps-secrets (file://)
    Chart.lock
    charts/                  # Vendored dependency tgz files (refresh after subchart edits)
    values.yaml
```

- **`platform/<chart>/`** — one Helm chart per subdirectory (**`namespaces`**, **`secrets`**, …).
- **`platform/values/global-values.yaml`** — default **`global.*`** shape for Workbench (namespaces, secret metadata, **empty** `global.workbenchRabbitMq.uri` / `global.workbenchRedis.connectionString`). Same file works for **direct** installs and **umbrella** installs: Helm propagates **`global`** to every subchart’s **`.Values.global`**.
- **`clusters/<cluster>/global-values.yaml`** — merged **after** the platform file (**later `-f` wins**). For **`workbench-apps-secrets`**, this layer **must** supply non-empty **`global.workbenchRabbitMq.uri`** and **`global.workbenchRedis.connectionString`** (see **`values.schema.json`** on that chart).

Helm merges values in order: packaged chart **`values.yaml`**, then each **`-f`** file left to right. **Later files win** on duplicate keys.

### `helm lint` and `values.schema.json`

- **`workbench-namespaces`**: packaged **`values.yaml`** is **`{}`**, so **`helm lint devops/helm/platform/namespaces`** with **no `-f`** **fails**. You can lint with **only** **`platform/values/global-values.yaml`** (namespaces do not need broker strings), or add the cluster file for parity with umbrella installs.
- **`workbench-apps-secrets`**: **`values.schema.json`** requires **merged** `global.*` including **non-empty** RabbitMQ and Redis strings, so you **always** pass **both** `-f` files for **`helm lint` / `helm template` / install** of this chart (or of the umbrella that includes it).
- **`workbench-umbrella`**: **`helm lint devops/helm/umbrella`** without **`-f`** fails because dependencies are validated; use the **same two-file `-f` chain** as install.

## Release name convention

Prefer **kebab-case** names that identify **what** and **where**:

```text
<app>-<env>
```

| Part | Meaning |
|------|---------|
| **`<app>`** | What this release installs, for example `namespaces`, `secrets`, `umbrella`. |
| **`<env>`** | Cluster or environment slice, for example `local`, `dev`, `prod`. |

Examples: **`namespaces-local`**, **`secrets-dev`**. A short name like **`namespaces`** is fine if only one environment uses that cluster.

Release metadata is stored in the install namespace (**`-n` / `--namespace`**). Platform charts in this repo are typically installed into **`workbench-platform`**.

## Typical `-f` chain

Use both files so **`workbench-apps-secrets`** (and umbrella) receive connection strings:

```text
-f devops/helm/platform/values/global-values.yaml \
-f devops/helm/clusters/local/global-values.yaml
```

Swap **`clusters/local/`** for another directory when targeting another cluster.

## Single chart: `workbench-namespaces`

**Simulate on the API (no persist)** — drop **`--dry-run=server`** for a real apply:

```bash
helm upgrade namespaces devops/helm/platform/namespaces/ \
  --server-side=true \
  --install \
  -n workbench-platform \
  --create-namespace \
  -f devops/helm/platform/values/global-values.yaml \
  -f devops/helm/clusters/local/global-values.yaml \
  --dry-run=server
```

**Minimum lint** (platform file only is enough for this chart):

```bash
helm lint devops/helm/platform/namespaces \
  -f devops/helm/platform/values/global-values.yaml
```

## Single chart: `workbench-apps-secrets`

**Requires both `-f` layers** — `platform/values/global-values.yaml` leaves RabbitMQ/Redis empty; the cluster file fills them. **`helm lint`** with only the first file **fails** (by design).

```bash
helm lint devops/helm/platform/secrets \
  -f devops/helm/platform/values/global-values.yaml \
  -f devops/helm/clusters/local/global-values.yaml

helm upgrade secrets devops/helm/platform/secrets/ \
  --server-side=true \
  --install \
  -n workbench-platform \
  --create-namespace \
  -f devops/helm/platform/values/global-values.yaml \
  -f devops/helm/clusters/local/global-values.yaml
```

## Umbrella chart (`workbench-umbrella`)

One release applies **namespaces** and **secrets** (see **`umbrella/Chart.yaml`**). Use the **same two `-f` files** so every subchart sees a complete **`global.*`**.

```bash
helm upgrade umbrella devops/helm/umbrella/ \
  --server-side=true \
  --install \
  -n workbench-platform \
  --create-namespace \
  -f devops/helm/platform/values/global-values.yaml \
  -f devops/helm/clusters/local/global-values.yaml \
  --dry-run=server
```

After you change **`platform/namespaces/`**, **`platform/secrets/`**, or their **`Chart.yaml` / `values.yaml` / `values.schema.json` / `templates/`**, refresh vendored packages:

```bash
helm dependency update devops/helm/umbrella
```

## Lint and template (full chain)

```bash
helm lint devops/helm/platform/namespaces \
  -f devops/helm/platform/values/global-values.yaml \
  -f devops/helm/clusters/local/global-values.yaml

helm lint devops/helm/platform/secrets \
  -f devops/helm/platform/values/global-values.yaml \
  -f devops/helm/clusters/local/global-values.yaml

helm lint devops/helm/umbrella \
  -f devops/helm/platform/values/global-values.yaml \
  -f devops/helm/clusters/local/global-values.yaml

helm template umbrella devops/helm/umbrella \
  -f devops/helm/platform/values/global-values.yaml \
  -f devops/helm/clusters/local/global-values.yaml
```

For an interactive menu that builds similar commands (including **multiple `-f`** paths), use **`./scripts/helm-wizard.sh`** from the repo root.

## Charts

| Path | Chart name (`Chart.yaml`) | Role |
|------|---------------------------|------|
| `devops/helm/platform/namespaces` | `workbench-namespaces` | **`Namespace`** objects and labels. **`values.schema.json`** requires **`global.workbenchPartOf`** and **`global.workbenchNamespaces`**; templates use **`required`** / **`fail`**. |
| `devops/helm/platform/secrets` | `workbench-apps-secrets` | **`Secret`** `workbench-apps-secrets` in the apps namespace. **`values.schema.json`** requires **merged** `global.*` including **non-empty** **`global.workbenchRabbitMq.uri`** and **`global.workbenchRedis.connectionString`** (cluster **`global-values.yaml`**). |
| `devops/helm/umbrella` | `workbench-umbrella` | Meta-chart; depends on **`workbench-namespaces`** and **`workbench-apps-secrets`**. |

See also **`devops/k8s/README.md`** for the Kustomize-oriented workflow; Helm here covers bootstrap namespaces plus the apps secret (and can grow with more platform charts).
