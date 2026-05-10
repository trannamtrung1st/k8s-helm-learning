# Kubernetes (local cluster)

This directory holds Kubernetes-oriented notes and manifests for the Workbench learning stack. Start from a working cluster before applying anything here.

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
