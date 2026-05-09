# Kubernetes and Helm learning

Personal notes and experiments for Kubernetes, Helm, and platform tooling. Documentation lives under [`docs/`](docs/).

## How to practice

1. Pick a **local or small cloud cluster** (e.g. **kind**, **k3d**, **minikube**) and a **container registry** you can push to.
2. Start from [Learning roadmap](docs/roadmap.md): it is **breadth-first** (platform-style). Use the optional **learning tracks** if you want a shorter **application-focused** path.
3. Build and **reuse** the app in [Workbench demo spec](docs/workbench-demo-spec.md) as you complete items — add Ingress, **Datadog**, HPA, secrets, **NetworkPolicy** on the same system instead of one-off demos.
4. Optional earlier focus: after **Ingress / TLS**, consider **External Secrets** (roadmap item **20**) so DB and broker credentials match production habits.
5. **Observability:** **Datadog** for now (not self-hosted Prometheus/Grafana/Loki). **Delivery:** **GitHub Actions** for CI/CD first; **Argo CD** (roadmap item **50**) is optional advanced GitOps. Kyverno, Falco, Kubebuilder, and standalone cost tooling stay deferred.

## Documentation

| Doc | Description |
|-----|-------------|
| [Roadmap](docs/roadmap.md) | Topics, how to use the list, optional app vs platform tracks |
| [Workbench demo spec](docs/workbench-demo-spec.md) | App requirements, v1 defaults, roadmap alignment (**Datadog** for observability) |
| [Knowledge notes](docs/knowledge-notes.md) | Commands and short explanations (proxy, debug, PDB, TLS, ingress, load balancing) |

## References

- [Kubernetes documentation](https://kubernetes.io/docs/home/)
