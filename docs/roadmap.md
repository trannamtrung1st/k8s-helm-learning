# Learning roadmap

Numbered sequence of topics for this repository.

1. (**DONE**) Build local multi-service Kubernetes app
2. Configure Kubernetes cluster (kubectl, kubeconfig, context, cluster access, and minimum bootstrap) — set this up first; you need a working cluster before deploying workloads
3. Configure liveness, readiness, and startup probes for workloads
4. Use Deployments for stateless workloads (replicas, rolling update fundamentals)
5. Expose workloads with Services — ClusterIP, NodePort, LoadBalancer — and when Ingress fits instead
6. Run multiple replicas with topology spread and PodDisruptionBudgets for basic application HA
7. Configure CPU and memory requests and limits for Pods (QoS classes; optional LimitRanges and ResourceQuotas)
8. Run batch and scheduled tasks with Jobs and CronJobs
9. Build worker + queue system on Kubernetes
10. Deploy PostgreSQL on Kubernetes
11. Run stateful workloads with StatefulSets (stable identity, ordered rollout, volume claim templates)
12. Deploy Redis on Kubernetes
13. Build reusable Kubernetes YAML templates
14. Convert manifests to Helm charts
15. Build self-service provisioning API using Kubernetes API
16. Build async job processing platform
17. Build preview environment system
18. Build multi-tenant namespace isolation system
19. Configure ingress controller
20. Configure TLS with cert-manager
21. Configure secret management with External Secrets Operator
22. Configure DNS routing
23. Configure persistent volumes and StorageClasses
24. Configure dynamic storage provisioning
25. Configure backup and restore workflows
26. Install and configure Datadog on Kubernetes (agent, metrics, logs)
27. Wire application telemetry to Datadog (APM, custom metrics, monitors/dashboards; OpenTelemetry export optional)
28. Configure RBAC permissions
29. Configure NetworkPolicies
30. Build multi-node Kubernetes cluster
31. Configure HA control plane
32. Simulate node failures and recovery
33. Configure rolling upgrades
34. Configure autoscaling with HPA
35. Configure event-driven autoscaling with KEDA
36. Configure cluster autoscaling
37. Install and configure Cilium
38. Configure Cilium network policies
39. Enable kube-proxy replacement with Cilium
40. Install and configure Istio
41. Configure mTLS between services
42. Configure canary deployments
43. Configure traffic splitting and retries
44. Provision cloud infrastructure using Terraform
45. Provision managed Kubernetes cluster (EKS / AKS / GKE)
46. Configure cloud networking and IAM
47. Build CI pipeline for container builds (e.g. GitHub Actions)
48. Build CD pipeline for Kubernetes deployments (e.g. GitHub Actions)
49. Configure ephemeral preview environments in CI/CD
50. Configure rollback and deployment promotion flows
51. Configure GitOps with Argo CD (advanced; optional after GitHub Actions CD, previews, and rollbacks)
52. Build internal developer platform APIs
53. Build reusable platform templates/modules
54. Mature Datadog usage (tags, SLOs, unified views across services)
55. Build disaster recovery workflow
56. Build multi-cluster deployment workflow
57. Build production debugging workflow and runbooks
