# Kubernetes and Helm learning

Personal notes and experiments for Kubernetes, Helm, and platform tooling. Documentation lives under [`docs/`](docs/).

## Repository layout

Backend is **`src/Workbench.sln`** (.NET 10, Clean Architecture: **Workbench.Domain**, **Workbench.Application**, **Workbench.Infrastructure**, **Workbench.Api**, **Workbench.Worker**). Frontend is **`src/workbench-app`** (React, Vite, Tailwind). Platform assets live under **`devops/`**; local compose under **`local/`**. See [Project structure](docs/project-structure.md) for details.

## How to practice

1. Pick a **local or small cloud cluster** (e.g. **kind**, **k3d**, **minikube**) and a **container registry** you can push to.
2. Start from [Learning roadmap](docs/roadmap.md): it is **breadth-first** (platform-style). Use the optional **learning tracks** if you want a shorter **application-focused** path.
3. Build and **reuse** the app in [Workbench demo spec](docs/workbench-demo-spec.md) as you complete items — add **Gateway API**, **Datadog**, HPA, secrets, **NetworkPolicy** on the same system instead of one-off demos.
4. Optional earlier focus: after **Gateway API / TLS**, consider **External Secrets** (roadmap item **21**) so DB and broker credentials match production habits.
5. **Observability:** **Datadog** for now (not self-hosted Prometheus/Grafana/Loki). **Delivery:** **GitHub Actions** for CI/CD first; **Argo CD** (roadmap item **48**) is optional advanced GitOps. Kyverno, Falco, Kubebuilder, and standalone cost tooling stay deferred.

## Documentation

| Doc | Description |
|-----|-------------|
| [Roadmap](docs/roadmap.md) | Topics, how to use the list, optional app vs platform tracks |
| [Workbench demo spec](docs/workbench-demo-spec.md) | App requirements, v1 defaults, roadmap alignment (**Datadog** for observability) |
| [Knowledge notes](docs/knowledge-notes.md) | Commands and short explanations (proxy, debug, PDB, TLS, Gateway API, load balancing) |
| [Project structure](docs/project-structure.md) | `src/`, `devops/`, `local/`, and Docker Compose layout |
| [Terraform (Azure)](devops/terraform/README.md) | Remote state, Entra OIDC federation, Storage Blob Data RBAC |

## Development

Git hooks via [pre-commit](https://pre-commit.com/):

```bash
pip install pre-commit   # or: brew install pre-commit
pre-commit install
pre-commit run --all-files
```

Config: [`.pre-commit-config.yaml`](.pre-commit-config.yaml)

| Hook | What it runs |
| ---- | ------------- |
| General | Trailing whitespace, YAML, merge conflicts, private keys |
| Terraform | `terraform fmt` + `terraform validate` (`scripts/pre-commit-terraform-validate.sh`, uses `vars/prod.tfvars` and auto-includes `vars/secrets.tfvars` when present; no remote backend) |
| Helm | `helm dependency update` via **`scripts/helm-dependency-update.sh`**; **`pre-commit-helm-lint.sh`** runs that plus **`helm lint --strict`** and **`helm template`** smoke |
| Scripts | ShellCheck + `bash -n` |
| .NET | `dotnet format --verify-no-changes` (requires SDK) |

Requires **terraform** and **helm** on `PATH` for infra hooks.

## References

- [Kubernetes documentation](https://kubernetes.io/docs/home/)
