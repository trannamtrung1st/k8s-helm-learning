# Knowledge notes

Short operational and conceptual notes collected while working through Kubernetes and related tooling.

## Server-side apply

Prefer **`kubectl apply --server-side`** (with **`-k devops`** or piped from **`kustomize build`**) over client-side apply for declarative configs so the apiserver owns merge behavior and field managers. See **Day-two commands (repo root)** in **[`devops/k8s/README.md`](../devops/k8s/README.md)** and the upstream [Server-Side Apply](https://kubernetes.io/docs/reference/using-api/server-side-apply/) guide.

## Workbench Kubernetes namespaces

Four namespaces are defined under **`devops/k8s/platform/namespaces/`**: **`workbench-apps`** (apps and current platform secrets), **`workbench-db`**, **`workbench-storage`**, and **`workbench-infra`**. Purposes and apply command: [Namespaces](../devops/k8s/README.md#namespaces) in **`devops/k8s/README.md`**.

**Path naming:** directories and manifest files under **`devops/k8s/`** use **kebab-case** (for example **`platform/storage-classes/`**, **`config-map.yaml`**). **Full-cluster apply** uses **`devops/kustomization.yaml`**: **`kubectl apply --server-side -k devops`** (see **`devops/k8s/README.md`**).

## Proxy Kubernetes API to localhost

```sh
kubectl proxy
```

## Ephemeral containers

Use the CLI:

```sh
kubectl run -i --tty --rm debug --image=busybox --restart=Never -- sh
# or
kubectl debug -it --image=busybox --target=pod/pod-name
```

Manual ephemeral container snippet:

```yaml
ephemeralContainers:
  - name: debugger
    image: busybox
    command: ["sh"]
    stdin: true
    tty: true
```

## PDB (Pod Disruption Budget)

- `minAvailable` vs `maxUnavailable`

## SSL/TLS (handshake outline)

1. CA exists (trusted root or private CA).
2. Server generates a key pair (private + public).
3. CA signs the server certificate (binds identity + public key).
4. Client starts TLS handshake (connects to domain).
5. Server sends certificate.
6. Server proves ownership by signing handshake data with the private key.
7. Client verifies:
   - CA signature (trust the CA manually or via OS trust store).
   - Server signature (ownership check using the public key in the cert).
8. Client and server perform ECDHE key exchange.
9. Both derive symmetric session keys.
10. Encrypted communication starts (TLS established).

## Edge routing alternatives

**Kubernetes Gateway API** (**Gateway**, **HTTPRoute**) is the preferred cluster-native HTTP edge in this repo’s [roadmap](roadmap.md). For local development only, **Workbench.LocalGateway** (YARP) in Docker Compose fills a similar role without installing a gateway implementation on the cluster.

## Global load balancer

Use Internet BGP (or equivalent anycast / global routing) to send traffic to the closest region.
