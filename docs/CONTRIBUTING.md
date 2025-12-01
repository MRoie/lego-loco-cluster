# Contributing to Lego Loco Cluster

Welcome to the Lego Loco Cluster project! We welcome contributions from both human developers and AI agents. This guide will help you get started.

## 📚 Documentation First

Before you start, please familiarize yourself with the project structure:
- **[Architecture Overview](ARCHITECTURE.md)**: Understand how the pieces fit together.
- **[README](../README.md)**: General project overview and quick start.
- **[AGENTS.md](../AGENTS.md)**: Specific instructions and context for AI Agents.

## 🛠️ For Human Developers

### Prerequisites
- **Docker**: Required for building containers and running the dev environment.
- **Node.js (v22+)**: For backend and frontend development.
- **Kubernetes Tools** (Optional but recommended): `kubectl`, `helm`, `kind`.

### Setting Up Your Environment
The easiest way to start is using the provided development script:

```bash
./scripts/dev-start.sh
```

This script will:
1.  Install dependencies for backend and frontend.
2.  Start the backend server (port 3001).
3.  Start the frontend dev server (port 3000).

### Running Tests
We have several test suites. Please ensure they pass before submitting a PR.

- **Unit Tests**:
  ```bash
  cd backend && npm test
  ```
- **Integration Tests**:
  ```bash
  ./scripts/test_monitoring_integration.sh
  ```

## 🤖 For AI Agents

If you are an AI agent working on this repository, please follow these guidelines to ensure smooth collaboration.

### 1. Context Acquisition
- **Read `AGENTS.md`**: This is your primary source of truth for current tasks and environment specifics.
- **Read `docs/ARCHITECTURE.md`**: Understand the system design before making changes.
- **Check `CI_TASKS.md`**: See what CI checks will run on your code.

### 2. Tool Usage
- **Prefer Scripts**: This repo has a robust `scripts/` directory. Before writing a complex command sequence, check if a script already exists.
  - Example: Use `./scripts/deploy_single.sh` instead of manually running `helm install ...`.
- **File Manipulation**: When editing configuration files (like `values.yaml` or `package.json`), read the file first to preserve existing structure.

### 3. Verification
- **Self-Correction**: If a step fails, analyze the error output. Do not blindly retry.
- **Test Your Changes**: Use the provided test scripts.
  - If you modify the backend, run `npm test` in `backend/`.
  - If you modify the infrastructure, run `./scripts/validate_ci_resources.sh`.

### 4. Documentation
- **Update Docs**: If you add a feature or change a workflow, update the relevant documentation (README, ARCHITECTURE, etc.).
- **Log Changes**: Update `RELEASE_NOTES.md` if the change is significant.

## 🤝 Code Style
- **JavaScript/Node**: Use modern ES6+ syntax. Async/Await is preferred over callbacks.
- **React**: Functional components with Hooks.
- **Scripts**: Bash scripts should have `set -e` to fail fast on errors.

Thank you for contributing! 🚂
