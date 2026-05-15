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
      templates/
    values/
      global-values.yaml     # Platform-wide values under global.* (umbrella-safe)
  clusters/
    local/
      global-values.yaml     # Cluster overlay (optional; add global.* overrides here)
  umbrella/                  # Umbrella chart: workbench-umbrella
    Chart.yaml               # Depends on workbench-namespaces (file://../platform/namespaces)
    Chart.lock
    charts/                  # Vendored dependency tgz (refresh after subchart edits)
    values.yaml
```

- **`platform/<chart>/`** — one Helm chart per subdirectory (for example **`namespaces`**).
- **`platform/values/global-values.yaml`** — default **`global.*`** values for Workbench. Workbench fields live **directly under `global`** (`global.workbenchPartOf`, `global.workbenchNamespaces`) so the **same file** works for a **direct** install of `workbench-namespaces` and for an **umbrella** install: Helm copies **`global`** from the parent release into every subchart’s **`.Values.global`**.
- **`clusters/<cluster>/global-values.yaml`** — last layer in the usual **`-f`** chain for that cluster (local, dev, prod, …). Put overrides under the same **`global.*`** keys here so umbrella subcharts still see them.

Helm merges values in order: packaged chart **`values.yaml`**, then each **`-f`** file left to right. **Later files win** on duplicate keys.

The **`workbench-namespaces`** chart includes **`values.schema.json`**: the packaged **`values.yaml`** is only **`{}`**, so **`helm lint devops/helm/platform/namespaces`** with **no `-f`** **fails by design** until you merge **`global.*`** (same **`-f`** chain as install). **`helm lint devops/helm/umbrella`** behaves the same without **`-f`** because the dependency is validated too.

## Release name convention

Prefer **kebab-case** names that identify **what** and **where**:

```text
<app>-<env>
```

| Part | Meaning |
|------|---------|
| **`<app>`** | What this release installs, for example `namespaces`, `platform-secrets`. |
| **`<env>`** | Cluster or environment slice, for example `local`, `dev`, `prod`. |

Examples: **`namespaces-local`**, **`namespaces-dev`**. A short name like **`namespaces`** is fine if only one environment uses that cluster.

Release metadata is stored in the install namespace (**`-n` / `--namespace`**). Platform charts in this repo are typically installed into **`workbench-platform`**.

## Typical command (single chart)

From the **repository root**:

**Simulate on the API (no persist)** — drop **`--dry-run=server`** when you want a real apply:

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

**Apply for real** (same line without dry-run):

```bash
helm upgrade namespaces devops/helm/platform/namespaces/ \
  --server-side=true \
  --install \
  -n workbench-platform \
  --create-namespace \
  -f devops/helm/platform/values/global-values.yaml \
  -f devops/helm/clusters/local/global-values.yaml
```

## Umbrella chart (`workbench-umbrella`)

Install everything declared in **`umbrella/Chart.yaml`** with one release. Parent **`-f`** files merge at the **parent** root; subcharts do **not** see arbitrary sibling keys—only their own subchart block and **`global`**. Put workbench settings under **`global.workbenchPartOf`** and **`global.workbenchNamespaces`** (same shape as the single-chart install) so dependencies receive them via **`.Values.global`**.

```bash
helm upgrade namespaces devops/helm/umbrella/ \
  --server-side=true \
  --install \
  -n workbench-platform \
  --create-namespace \
  -f devops/helm/platform/values/global-values.yaml \
  -f devops/helm/clusters/local/global-values.yaml \
  --dry-run=server
```

After you change **`platform/namespaces/`** (templates, `Chart.yaml`, default `values.yaml`), refresh the vendored package so the umbrella uses the latest subchart:

```bash
helm dependency update devops/helm/umbrella
```

## Lint and template

Use the **same `-f` chain** you use for install:

```bash
helm lint devops/helm/platform/namespaces \
  -f devops/helm/platform/values/global-values.yaml \
  -f devops/helm/clusters/local/global-values.yaml

helm template namespaces devops/helm/platform/namespaces \
  -f devops/helm/platform/values/global-values.yaml \
  -f devops/helm/clusters/local/global-values.yaml
```

For the umbrella, use the **same `-f` chain** as for install so subcharts receive **`global.*`** and **`helm lint`** validates the real merged values:

```bash
helm lint devops/helm/umbrella \
  -f devops/helm/platform/values/global-values.yaml \
  -f devops/helm/clusters/local/global-values.yaml

helm template namespaces devops/helm/umbrella \
  -f devops/helm/platform/values/global-values.yaml \
  -f devops/helm/clusters/local/global-values.yaml
```

For an interactive menu that builds similar commands (including **multiple `-f`** paths), use **`./scripts/helm-wizard.sh`** from the repo root.

## Charts

| Path | Chart name (`Chart.yaml`) | Role |
|------|---------------------------|------|
| `devops/helm/platform/namespaces` | `workbench-namespaces` | Declares Workbench **`Namespace`** objects and labels. **`values.schema.json`** requires **`global.workbenchPartOf`** and **`global.workbenchNamespaces`**; templates also use **`required`** / **`fail`** so bad merges error at render time. |
| `devops/helm/umbrella` | `workbench-umbrella` | Meta-chart; depends on **`workbench-namespaces`**. |

See also **`devops/k8s/README.md`** for the Kustomize-oriented workflow; Helm here is mainly for bootstrap-style installs (namespaces and future platform charts).
