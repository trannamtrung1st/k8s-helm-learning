# Learning roadmap

Numbered sequence of topics for this repository.

1. (**DONE**) Build local multi-service Kubernetes app
2. Configure liveness, readiness, and startup probes for workloads
3. Use Deployments for stateless workloads (replicas, rolling update fundamentals)
4. Expose workloads with Services — ClusterIP, NodePort, LoadBalancer — and when Ingress fits instead
5. Run multiple replicas with topology spread and PodDisruptionBudgets for basic application HA
6. Configure CPU and memory requests and limits for Pods (QoS classes; optional LimitRanges and ResourceQuotas)
7. Run batch and scheduled tasks with Jobs and CronJobs
8. Build worker + queue system on Kubernetes
9. Deploy PostgreSQL on Kubernetes
10. Run stateful workloads with StatefulSets (stable identity, ordered rollout, volume claim templates)
11. Deploy Redis on Kubernetes
12. Build reusable Kubernetes YAML templates
13. Convert manifests to Helm charts
14. Build self-service provisioning API using Kubernetes API
15. Build async job processing platform
16. Build preview environment system
17. Build multi-tenant namespace isolation system
18. Configure ingress controller
19. Configure TLS with cert-manager
20. Configure secret management with External Secrets Operator
21. Configure DNS routing
22. Configure persistent volumes and StorageClasses
23. Configure dynamic storage provisioning
24. Configure backup and restore workflows
25. Install and configure Datadog on Kubernetes (agent, metrics, logs)
26. Wire application telemetry to Datadog (APM, custom metrics, monitors/dashboards; OpenTelemetry export optional)
27. Configure RBAC permissions
28. Configure NetworkPolicies
29. Build multi-node Kubernetes cluster
30. Configure HA control plane
31. Simulate node failures and recovery
32. Configure rolling upgrades
33. Configure autoscaling with HPA
34. Configure event-driven autoscaling with KEDA
35. Configure cluster autoscaling
36. Install and configure Cilium
37. Configure Cilium network policies
38. Enable kube-proxy replacement with Cilium
39. Install and configure Istio
40. Configure mTLS between services
41. Configure canary deployments
42. Configure traffic splitting and retries
43. Provision cloud infrastructure using Terraform
44. Provision managed Kubernetes cluster (EKS / AKS / GKE)
45. Configure cloud networking and IAM
46. Build CI pipeline for container builds (e.g. GitHub Actions)
47. Build CD pipeline for Kubernetes deployments (e.g. GitHub Actions)
48. Configure ephemeral preview environments in CI/CD
49. Configure rollback and deployment promotion flows
50. Configure GitOps with Argo CD (advanced; optional after GitHub Actions CD, previews, and rollbacks)
51. Build internal developer platform APIs
52. Build reusable platform templates/modules
53. Mature Datadog usage (tags, SLOs, unified views across services)
54. Build disaster recovery workflow
55. Build multi-cluster deployment workflow
56. Build production debugging workflow and runbooks
