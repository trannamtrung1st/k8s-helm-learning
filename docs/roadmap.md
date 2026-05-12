# Learning roadmap

Topics are ordered so you **run the whole Workbench-shaped system on-cluster first** (apps talking to Postgres and a broker over **Services** and **PVCs**), then **harden and expose** (Gateway API, TLS, External Secrets), then go **deeper** (StatefulSet theory — **RabbitMQ cluster** and **Redis Cluster** labs in item **16**, mesh, cloud, GitOps, platform).

Within each band, earlier items unblock later ones. Skip ahead only when you already have substitutes (e.g. managed DB outside the cluster).

## Foundation — cluster, workloads, data path

1. (**DONE**) Build local multi-service Kubernetes app
2. (**DONE**) Configure Kubernetes cluster (kubectl, kubeconfig, context, cluster access, and minimum bootstrap) — set this up first; you need a working cluster before deploying workloads
3. (**DONE**) Configure liveness, readiness, and startup probes for workloads
4. (**DONE**) Use Deployments for stateless workloads (replicas, rolling update fundamentals)
5. (**DONE**) Apply **namespaces** and baseline **platform** layout (e.g. `workbench-system`, `workbench-db`, `workbench-infra` — see `devops/k8s/platform/namespaces/`)
6. (**DONE**) **ConfigMaps** and in-cluster **Secrets** — env and volume mounts; plain `Secret` objects before operators (External Secrets comes later)
7. (**DONE**) **Services** — ClusterIP for east-west, NodePort / LoadBalancer for north-south L4; **cluster DNS**; use **`kubectl port-forward`** for HTTP access until Gateway API is in place
8. (**DONE**) **PersistentVolumes** and **StorageClasses** — enough to attach **durable disks** to Postgres and other stateful components
9. (**DONE**) Deploy **PostgreSQL** on Kubernetes (operator or chart; run API migrations against it)
10. (**DONE**) Deploy **RabbitMQ** (or your broker) on Kubernetes — keep topology aligned with **`devops/rabbitmq/definitions.json`** where practical; evolve to a **multi-node cluster** under item **16**
11. **Worker + queue system** on Kubernetes — connect the worker to the broker; competing consumers, failure behavior

## Hygiene and reliability

12. Configure **CPU and memory** requests and limits (QoS classes; optional LimitRanges and ResourceQuotas)
13. Run **multiple replicas** with **topology spread** and **PodDisruptionBudgets** for basic application HA
14. **Rolling updates** — strategy fields, rollout status, and rollback basics (`kubectl rollout …`)
15. Run batch and scheduled tasks with **Jobs** and **CronJobs**
16. **StatefulSets** in depth — stable identity, ordered rollout, volume claim templates (beyond “only ever installed Postgres via a chart”); reinforce with **clustered middleware** (not “many pods behind one DNS name” without a real cluster story):
    - **RabbitMQ cluster** on Kubernetes — peer discovery, governing **headless** Service and per-pod DNS, ordered StatefulSet (or operator); quorum queues / mirrored queues vs single node; keep topology aligned with **`devops/rabbitmq`** where practical
    - **Redis Cluster** on Kubernetes — slot-aware sharding (StatefulSet-based shards, operator, or upstream topology docs), failover and **cluster-aware clients** (e.g. StackExchange.Redis cluster configuration); contrast with one standalone Redis behind a Service
17. Deploy **Redis** on Kubernetes (optional; cache and idempotency patterns; treat **Redis Cluster** as the StatefulSet-deep-dive under item **16** when you want multi-primary data sharding, not N unrelated `redis-server` replicas)

## Edge HTTP, identity of traffic, secrets at scale

18. Configure **Gateway API** — install a **gateway implementation** (controller), then **Gateway**, **HTTPRoute**, and **ReferenceGrant** for cross-namespace routing rules
19. Configure **TLS** with cert-manager (including certificates for **Gateway** TLS listeners and Services as needed)
20. Configure **DNS** routing (records to load balancer / **Gateway** addresses; optional ExternalDNS)
21. Configure secret management with **External Secrets Operator** (replace long-lived plain Secrets for Postgres, broker, apps)

## Storage and data lifecycle (deeper)

22. Configure **dynamic** storage provisioning (CSI, default StorageClass, volume binding modes)
23. Configure **backup and restore** workflows (Postgres, broker config, RPO/RTO drills)

## Observability

24. Install and configure **Datadog** on Kubernetes (agent, metrics, logs)
25. Wire **application telemetry** to Datadog (APM, custom metrics, monitors/dashboards; OpenTelemetry export optional)

## Security and policy

26. Configure **RBAC** permissions
27. Configure **NetworkPolicies**

## Cluster topology and failure

28. Build **multi-node** Kubernetes cluster
29. Configure **HA control plane**
30. **Simulate node failures** and recovery

## Autoscaling

31. Configure autoscaling with **HPA**
32. Configure event-driven autoscaling with **KEDA**
33. Configure **cluster** autoscaling

## Advanced CNI

34. Install and configure **Cilium**
35. Configure **Cilium** network policies
36. Enable **kube-proxy replacement** with Cilium

## Service mesh

37. Install and configure **Istio**
38. Configure **mTLS** between services
39. Configure **canary** deployments
40. Configure **traffic splitting** and retries

## Cloud and IaC

41. Provision cloud infrastructure using **Terraform**
42. Provision **managed Kubernetes** cluster (EKS / AKS / GKE)
43. Configure **cloud networking** and IAM

## Delivery

44. Build **CI** pipeline for container builds (e.g. GitHub Actions)
45. Build **CD** pipeline for Kubernetes deployments (e.g. GitHub Actions)
46. Configure **ephemeral preview environments** in CI/CD
47. Configure **rollback** and deployment promotion flows
48. Configure **GitOps** with Argo CD (advanced; optional after GitHub Actions CD, previews, and rollbacks)

## Platform depth (reuse, productization, maturity)

49. Build **reusable Kubernetes YAML** templates and **Kustomize** composition patterns
50. Convert manifests to **Helm** charts
51. Build **self-service provisioning API** using Kubernetes API
52. Build **async job processing platform** abstractions on top of the cluster
53. Build **multi-tenant** namespace isolation system
54. Build **preview environment** system (platform-wide: provisioning, data, teardown beyond a single pipeline job)
55. Build **internal developer platform** APIs
56. Build **reusable platform** templates/modules
57. **Mature Datadog** usage (tags, SLOs, unified views across services)
58. Build **disaster recovery** workflow
59. Build **multi-cluster** deployment workflow
60. Build **production debugging** workflow and runbooks
