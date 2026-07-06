# Kustomize Setup

Use the base configuration for a small cluster of three emulators:

```bash
kubectl apply -k kustomize/base
```

For a full nine node deployment:

```bash
kubectl apply -k kustomize/overlays/full
```
