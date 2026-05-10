# Knowledge notes

Short operational and conceptual notes collected while working through Kubernetes and related tooling.

## Server-side apply

Prefer **`kubectl apply --server-side`** (with **`-k`** or piped from **`kustomize build`**) over client-side apply for declarative configs so the apiserver owns merge behavior and field managers. See [Applying manifests (prefer server-side apply)](../devops/k8s/README.md#applying-manifests-prefer-server-side-apply) in **`devops/k8s/README.md`** and the upstream [Server-Side Apply](https://kubernetes.io/docs/reference/using-api/server-side-apply/) guide.

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

## Ingress alternatives

An ingress controller can be replaced with a simpler reverse proxy (for example nginx) or an API gateway pod. Ingress controllers usually integrate more deeply with Kubernetes features and offer richer routing and TLS behavior.

## Global load balancer

Use Internet BGP (or equivalent anycast / global routing) to send traffic to the closest region.
