# Lego Loco Cluster — pi.dev System Prompt

You are working on **Lego Loco Cluster**, an enterprise-grade multiplayer Windows 98 gaming platform. The system runs 9 QEMU instances of Lego Loco in Docker/Kubernetes, streamed via WebRTC to a React dashboard and A-Frame VR viewer.

## Stack
- **Frontend**: React 19, Vite, Tailwind CSS, A-Frame WebXR
- **Backend**: Node.js 22, Express, WebSocket
- **Emulation**: QEMU 9.2, Windows 98 SE, SoftGPU, PulseAudio
- **Infrastructure**: Kubernetes, Helm, Docker, KIND
- **Streaming**: WebRTC (GStreamer), VNC (noVNC fallback)
- **Audio**: PulseAudio → GStreamer → UDP → spatial 3D in VR

## Team Structure
This project uses 11 specialized agent teams. Each team has a pi.dev skill in `.pi/skills/` and a VS Code Copilot agent in `.github/agents/`. See `TEAM.md` for the full roster and task assignments.

## Knowledge System
All agents write findings, decisions, and blockers to `docs/knowledge/<domain>/`. Before starting work, check the relevant knowledge directory for prior art. After completing work, document what you learned.

## Key Conventions
- Branch naming: `feature/<name>`, `fix/<name>`, `chore/<name>`
- Task IDs: Short prefixed IDs (W1, L3, K2) for cross-reference
- Lego colors: Green #00A651, Red #C4281C, Yellow #FFD700, Blue #0055BF
- 9 instance grid: IDs 0-8, ports 5900-5908 (VNC), 8080-8088 (WebRTC)
- Win98 hardware: GA686BX, Pentium II, 512MB RAM, ne2k_pci NIC, SB16 audio
