# Lego Loco Cluster Architecture

This document provides a high-level overview of the Lego Loco Cluster architecture, explaining how the different components interact to deliver a multiplayer Windows 98 gaming experience in the browser.

## High-Level Overview

The system runs multiple instances of **Lego Loco** (a 1998 PC game) inside emulated Windows 98 environments. These instances are containerized and orchestrated by **Kubernetes**. Users interact with these instances via a **React-based Frontend** that displays the game video streams and captures input. A **Node.js Backend** manages the cluster, handles WebRTC signaling, and monitors the health of the emulators.

```mermaid
graph TD
    User[User / Browser] -->|HTTPS| Frontend[Frontend (React)]
    User -->|WebSocket| Backend[Backend (Node.js)]
    User -->|WebRTC| Emulator[Emulator (QEMU/Win98)]
    
    Frontend -->|API| Backend
    Backend -->|K8s API| K8s[Kubernetes Cluster]
    
    subgraph "Kubernetes Cluster"
        Backend
        Frontend
        Emulator
        NFS[NFS Server]
    end
    
    Emulator -->|Mount| NFS
```

## Components

### 1. Frontend (`frontend/`)
- **Tech Stack**: React, Vite, Tailwind CSS, `react-vnc`.
- **Purpose**: Provides the user interface for viewing and controlling the games.
- **Key Features**:
    - **Grid View**: Displays multiple instances in a 3x3 grid.
    - **Interactive Control**: Captures mouse and keyboard input and sends it to the emulator via VNC (over WebRTC/WebSocket).
    - **VR Mode**: Uses A-Frame to render the game screens in a 3D virtual environment.
    - **Audio**: Plays audio streams from the instances.

### 2. Backend (`backend/`)
- **Tech Stack**: Node.js, Express, `ws` (WebSockets), `@kubernetes/client-node`.
- **Purpose**: Acts as the control plane for the application.
- **Key Responsibilities**:
    - **Signaling**: Facilitates WebRTC connection establishment between the browser and the emulators.
    - **Cluster Management**: Interacts with the Kubernetes API to discover running emulator pods (`kubernetesDiscovery.js`).
    - **Health Monitoring**: Probes the health of QEMU instances (video, audio, performance) and exposes metrics (`streamQualityMonitor.js`).
    - **Auto-Recovery**: Detects failed instances and attempts to recover them.

### 3. Emulator (`containers/`)
- **Tech Stack**: Docker, QEMU, Windows 98 SE, Wine (for some tools), GStreamer.
- **Purpose**: Runs the actual game.
- **Key Features**:
    - **SoftGPU**: Provides software-accelerated 3D graphics for the game.
    - **VNC Server**: Exposes the visual output and accepts input.
    - **Audio Streaming**: Captures audio from the emulated sound card and streams it.
    - **Health Endpoints**: Exposes internal health metrics (frame rate, audio levels) via an HTTP server inside the container.

### 4. Infrastructure (`helm/`, `k8s/`)
- **Tech Stack**: Kubernetes, Helm, Kustomize.
- **Deployment**:
    - **StatefulSet**: Used for emulators to ensure stable network identities (`loco-emulator-0`, `loco-emulator-1`, etc.).
    - **Deployment**: Used for stateless services like Backend and Frontend.
    - **Services**: Expose the components within the cluster.
    - **NFS**: A shared file system for game assets ("Art Resources") that allows instances to share custom Lego Loco data.

## Data Flows

### Video & Audio Streaming
1.  **Capture**: QEMU renders the game. VNC server captures the screen. PulseAudio captures the sound.
2.  **Encoding**: GStreamer (or similar tools inside the container) encodes the streams.
3.  **Transmission**: The streams are sent to the browser via WebRTC (UDP/TCP).
4.  **Playback**: The Frontend decodes and plays the streams using `<video>` and `<audio>` elements (or canvas for VNC).

### Input Handling
1.  **Capture**: Frontend captures mouse moves and key presses.
2.  **Transmission**: Events are sent via WebSocket to the Backend (or directly to a VNC proxy).
3.  **Injection**: The VNC server inside the container injects these events into the emulated Windows 98 input queue.

### Auto-Discovery & Health
1.  **Discovery**: The Backend polls the Kubernetes API for pods matching the emulator selector.
2.  **Registration**: New pods are added to the active instances list.
3.  **Monitoring**: The Backend periodically queries the `/health` endpoint of each emulator pod.
4.  **Recovery**: If a pod reports "unhealthy" for too long, the Backend may trigger a restart or alert the user.

## Directory Structure
- `backend/`: Node.js server code.
- `frontend/`: React application code.
- `containers/`: Dockerfiles for the emulator and other services.
- `helm/`: Helm charts for deployment.
- `scripts/`: Automation scripts for dev, test, and deploy.
- `docs/`: Project documentation.
