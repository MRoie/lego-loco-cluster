# Stack Requirements and Dependencies

The repository relies on the following tools and libraries:

- **Emulation**: `QEMU`, `PCem`, `Wine`
- **Streaming**: `GStreamer`, `PulseAudio`
- **Web UI**: `React`, `Tailwind CSS`, `WebRTC`, `framer-motion`, `vite`
- **Backend**: `Node.js`, `express`
- **Infrastructure**: `Docker`, `Helm`, `k3s` (Kubernetes)
- **Testing and utilities**: `kubectl`, `tcpdump`, `bash`

Node package dependencies are defined in `backend/package.json` and `frontend/package.json`.

See `AGENTS.md` for instructions on installing the core packages in this workspace.
