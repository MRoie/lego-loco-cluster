# GitHub Codespaces Setup for Lego Loco Cluster

This repository is optimized for GitHub Codespaces, providing a complete development environment in the cloud with AI-powered coding assistance.

## 🚀 Quick Start with Codespaces

1. **Open in Codespaces**: Click the green "Code" button and select "Open with Codespaces"
2. **Wait for setup**: The environment will automatically install dependencies and configure the workspace
3. **Start coding**: GitHub Copilot is pre-configured and ready to assist with your development

## 🤖 AI Coding Features

### GitHub Copilot Integration
- **Enabled for all file types**: JavaScript, TypeScript, Docker, YAML, Markdown, and more
- **Inline suggestions**: Press `Ctrl+I` (or `Cmd+I` on Mac) for AI completions
- **Chat interface**: Use `Ctrl+Shift+P` and search for "Copilot Chat" to ask questions
- **Context-aware**: Copilot understands the project structure and can suggest appropriate code

### Optimized Settings
- Auto-completion enabled for all languages
- Smart suggestion triggers
- Enhanced IntelliSense for JavaScript/TypeScript
- Automatic imports and refactoring suggestions

## 🛠️ Development Environment

### Pre-installed Tools
- **Node.js 22**: Latest LTS version
- **Docker**: For containerized development
- **kubectl, helm, kind**: Kubernetes development tools
- **QEMU**: For Windows 98 emulation
- **GitHub CLI**: For repository management

### Available Commands
```bash
# Start the full development environment
./scripts/dev-start.sh

# Start individual services
npm run dev          # In backend/ or frontend/ directories
backend-dev          # Alias for backend development
frontend-dev         # Alias for frontend development

# Docker shortcuts
dps                  # docker ps
dls                  # docker ps -a
di                   # docker images

# Kubernetes shortcuts
k                    # kubectl
kgp                  # kubectl get pods
kgs                  # kubectl get services
```

## 🔧 VS Code Configuration

The workspace is pre-configured with:

### Extensions
- **GitHub Copilot**: AI-powered code completion
- **GitHub Copilot Chat**: Conversational AI coding assistant
- **Prettier**: Code formatting
- **ESLint**: JavaScript/TypeScript linting
- **Tailwind CSS**: CSS framework support
- **Kubernetes Tools**: K8s manifest editing and debugging
- **Docker**: Container management

### Debug Configuration
- **Backend debugging**: F5 to start debugging the Node.js server
- **Attach debugger**: Connect to running development server
- **Source maps**: Full debugging support with breakpoints

### Tasks
- **Ctrl+Shift+P** → "Tasks: Run Task" for quick access to:
  - Start Development Environment
  - Backend Development Server
  - Frontend Development Server
  - Build All

## 📁 Project Structure

```
lego-loco-cluster/
├── .devcontainer/          # Development container configuration
│   ├── devcontainer.json   # Enhanced for Codespaces
│   ├── setup.sh           # Automated environment setup
│   └── Dockerfile         # Container image definition
├── .github/codespaces/     # Codespaces-specific configuration
├── .vscode/               # VS Code workspace settings
├── backend/               # Express.js API server
├── frontend/              # React + Vite dashboard
├── containers/            # Docker images for emulators
├── helm/                  # Kubernetes Helm charts
├── scripts/               # Development and deployment scripts
└── docs/                  # Documentation
```

## 🎯 Getting Started with Development

1. **Explore the codebase**:
   ```bash
   # Use Copilot to understand the project structure
   # Ask: "Explain the overall architecture of this project"
   ```

2. **Start the development environment**:
   ```bash
   ./scripts/dev-start.sh
   ```

3. **Use AI assistance**:
   - Ask Copilot Chat: "How do I add a new API endpoint?"
   - Use inline suggestions while typing code
   - Let Copilot help with documentation and comments

4. **Access the applications**:
   - Frontend: `http://localhost:3000`
   - Backend API: `http://localhost:3001`
   - VNC (when emulators running): `http://localhost:6080`

## 🧪 Testing with AI

Copilot can help with:
- Writing unit tests
- Creating integration tests
- Debugging issues
- Code refactoring
- Documentation generation

Example prompts for Copilot Chat:
- "Generate unit tests for the WebRTC functionality"
- "Help me debug the QEMU container startup issue"
- "Refactor this component to use React hooks"
- "Write documentation for the API endpoints"

## 🔗 Resources

- [Project Documentation](docs/REPOSITORY_SUMMARY.md)
- [Development Guide](docs/legacy/DEVELOPMENT_COMPLETE.md)
- [GitHub Copilot Documentation](https://docs.github.com/en/copilot)
- [VS Code Keyboard Shortcuts](https://code.visualstudio.com/docs/getstarted/keybindings)

## 💡 Tips for AI-Assisted Development

1. **Be specific**: More context leads to better suggestions
2. **Use comments**: Describe what you want to achieve
3. **Iterate**: Accept suggestions and refine them
4. **Ask questions**: Use Copilot Chat to understand complex code
5. **Stay in flow**: Let Copilot handle boilerplate while you focus on logic

Happy coding with AI assistance! 🚀