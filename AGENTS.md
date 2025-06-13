# Workspace Agent Instructions

This repository uses the Codex agent to set up the environment. To install all core packages required by the stack, run the following commands in the workspace shell:

```bash
sudo apt-get update
sudo apt-get install -y nodejs npm qemu-system-x86 qemu-kvm wine gstreamer1.0-tools pulseaudio kubectl docker.io tcpdump
cd backend && npm install && cd ..
cd frontend && npm install && cd ..
```

These steps should be executed before running any tests or development servers.
