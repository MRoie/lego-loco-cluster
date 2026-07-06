# Lessons Learned: Win98 ISO Builtin & Minikube Caching

## 1. Issue Description
The emulator pod failed to start with `Init:CrashLoopBackOff`.
Logs revealed the `init-disk-image` container failed to find the built-in disk image:
```
❌ Built-in disk image not found
ls: cannot access '/opt/builtin-images/': No such file or directory
```

## 2. Investigation Steps

### A. Image Verification
We suspected the image build was faulty.
1.  **Repo Check**: Verified `containers/qemu-softgpu/Dockerfile` copies the file.
2.  **Base Image Check**: Ran `docker run ... win98-softgpu:latest find / ...` and CONFIRMED the file exists in the base image.
3.  **Built Image Check**: Ran `docker run ... qemu-loco:$TAG ls -la /opt/builtin-images/` and CONFIRMED the file exists in the locally built image.

### B. Runtime Environment
Since the file existed in the image but not in the running pod, we suspected a deployment artifact.
1.  **Pod Inspection**: `kubectl get pod ... -o jsonpath` revealed the pod was running `qemu-loco:latest`.
2.  **Constraint**: Minikube often caches `latest` tags aggressively or StatefulSet rollouts stall if the previous pod is crashing (OrderedReady strategy).

## 3. Resolution

### Unique Tagging Strategy
We updated `scripts/deploy_backend_rigorous.sh` to use the unique timestamp `$TAG` for the emulator image, replacing the static `latest` tag.

```bash
# Before
docker build ... -t qemu-loco:latest ...
helm upgrade ... --set emulator.tag=latest

# After
docker build ... -t qemu-loco:$TAG ...
helm upgrade ... --set emulator.tag=$TAG
```

### Force Recreation
We deleted the stuck pod to force the StatefulSet controller to create a replacement with the new specification.

## 4. Verification

The new pod `loco-loco-emulator-0` started with the correct tag `qemu-loco:v1768088503`.
Logs confirmed successful initialization:
```
✅ Disk image copied to PVC successfully
...
[2026-01-10 23:50:29] ✅ SUCCESS: ✅ Snapshot created successfully from PVC disk
[2026-01-10 23:50:29] ℹ️  INFO: QEMU started with PID: 86
```

## 5. Conclusion
The emulator storage pipeline is now robust. Using unique tags ensures every deployment uses the exact code/image built, bypassing stale cache issues.
