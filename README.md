Loco LAN: Kubernetes-Controlled Lego Loco LAN Cluster

Welcome to Loco LAN — a LAN-based Kubernetes system that runs 9 instances of Lego Loco on emulated Windows 98 environments. Each instance is visualized in a 3×3 web-based KVM grid with Lego-styled borders, full keyboard/mouse control, audio metering, and real-time video streaming. The system also supports VR scene navigation of the game instances.

🧩 Key Features

✅ Runs 9 emulated Win98 environments (QEMU, PCem, Wine supported)

🎮 Each runs Lego Loco with full multiplayer LAN support

🌐 TCP/IP stack patched using virtual TAP bridge

🖼️ Web-based KVM dashboard (React, WebRTC)

🔊 Audio metering and passthrough per instance

🎥 Low-latency streaming using GStreamer + WebRTC

📦 CI/CD with multi-arch Docker builds and Kubernetes deployment

🧠 Fully scripted test plan to validate networking and game state

🚀 Future expansion to 3D VR room interface with live controls



---

🛠️ Stack

Layer	Tech

Emulation	QEMU, PCem, Wine
Streaming	GStreamer, PulseAudio
Web UI	React, Tailwind, WebRTC
Infra	Helm, Kubernetes (k3s)
CI/CD	GitHub Actions, Docker
Testing	Bash, kubectl, tcpdump



---

📁 Repo Structure

loco-lan/
├── frontend/                # React dashboard
├── backend/                 # Signaling + API control server
├── containers/              # Multi-arch Dockerfiles
├── helm/                    # Helm charts and values
├── k8s-tests/               # Cluster and pod health scripts
├── ci/                      # Build + manifest + pipeline
└── README.md


---

🚦 How to Deploy

# Build multi-arch Docker images
export LOCO_REPO=myrepo
docker buildx build --platform linux/amd64,linux/arm64 -t $LOCO_REPO/loco:latest --push .

# Create K8s cluster (k3s or kubeadm)
helm install loco helm/loco-chart --set imageRepo=$LOCO_REPO

# Run connectivity and game-level tests
bash k8s-tests/test-network.sh

# Configure the shared TAP bridge
bash scripts/setup_bridge.sh

# Launch a QEMU-based instance
docker run --rm --network host --cap-add=NET_ADMIN \
  -e TAP_IF=tap0 -e BRIDGE=loco-br \
  -v /path/to/win98.qcow2:/images/win98.qcow2 \
  $LOCO_REPO/qemu-loco


---

🧠 Agent Task Prompts (Spec-Driven)

Each of the following prompts corresponds to a major task described in the project:

1. 🏗️ Bootstrap React Web App (3×3 Grid UI)

> Scaffold a React app using Tailwind and Vite that renders a 3×3 grid of video tiles. Each tile has zoom controls, Lego-styled borders, and a hover control panel with audio meter and fullscreen toggle.



2. 🔌 Create WebRTC Hook for StreamTile

> Build a useWebRTC.ts hook that connects to a signaling server, negotiates a WebRTC stream, and handles cleanup. It should support audio metering via Web Audio API and expose stats.



3. 🧠 Write Signaling Server in Node.js

> Create a lightweight WebSocket signaling server in Node.js using ws. It should assign stream IDs, handle SDP offer/answer exchange, and support reconnections.



4. 🐳 Write Multi-Arch Dockerfiles for Emulators

> Write three Dockerfiles for PCem, QEMU, and Wine environments with VNC output, PulseAudio capture, and GStreamer pipeline that exposes video+audio as WebRTC stream.



5. 📦 Create Docker Manifest Workflow

> Write a GitHub Actions CI workflow that builds all three Dockerfiles for both amd64 and arm64, tags them with digests, and publishes a Docker manifest list for latest.



6. 🔁 Design Helm Chart with Theme Support

> Create a Helm chart that defines a deployment per instance (0–8) with per-pod values for emulator type and UI border theme. Use config maps to pass per-instance style IDs.



7. 🧪 Test Plan CI Job

> Create a Job resource that runs test-network.sh and test-broadcast.sh after each deployment to verify L2/L3/L4 communication across pods.



8. 🎮 Automate In-Game Multiplayer Detection

> Write a script that connects to each VNC output, takes screenshots using vncdotool, and uses OpenCV to detect presence of LAN multiplayer game listings.



9. 🎨 Lego Border Styling with SVG/CSS

> Design a set of SVG patterns and Tailwind



 
