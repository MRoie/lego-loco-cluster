#!/bin/bash

# Lego Loco Cluster - Development Environment Setup
# This script runs after the devcontainer is created to set up the development environment

set -e

echo "🚀 Setting up Lego Loco Cluster development environment..."

# Determine the workspace root
WORKSPACE_ROOT=${WORKSPACE_ROOT:-$(pwd)}
if [ -d "/workspaces" ]; then
    WORKSPACE_ROOT="/workspaces/$(basename $(pwd))"
elif [ -d "/workspace" ]; then
    WORKSPACE_ROOT="/workspace"
fi

echo "📍 Workspace root: $WORKSPACE_ROOT"

# Install Node.js dependencies
echo "📦 Installing Node.js dependencies..."
if [ -d "$WORKSPACE_ROOT/backend" ]; then
    cd "$WORKSPACE_ROOT/backend" && npm install
fi
if [ -d "$WORKSPACE_ROOT/frontend" ]; then
    cd "$WORKSPACE_ROOT/frontend" && npm install
fi
cd "$WORKSPACE_ROOT"

# Set up Git configuration for Codespaces
echo "🔧 Configuring Git for Codespaces..."
if [ -n "$GITHUB_USER" ]; then
    git config --global user.name "$GITHUB_USER"
fi
if [ -n "$GITHUB_EMAIL" ]; then
    git config --global user.email "$GITHUB_EMAIL"
fi

# Create helpful aliases
echo "🔗 Setting up development aliases..."
cat >> ~/.bashrc << 'EOF'

# Lego Loco Cluster development aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'

# Project-specific aliases
alias start-dev='./scripts/dev-start.sh'
alias backend-dev='cd backend && npm run dev'
alias frontend-dev='cd frontend && npm run dev'
alias logs-backend='docker-compose logs -f backend'
alias logs-frontend='docker-compose logs -f frontend'
alias cluster-up='./scripts/start_live_cluster.sh'

# Docker shortcuts
alias dps='docker ps'
alias dls='docker ps -a'
alias di='docker images'

# Kubernetes shortcuts
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get services'
alias kgd='kubectl get deployments'

EOF

# Make scripts executable
echo "🔐 Making scripts executable..."
find ./scripts -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true

# Create workspace settings for VS Code
echo "⚙️  Setting up VS Code workspace..."
mkdir -p .vscode
cat > .vscode/settings.json << 'EOF'
{
    "github.copilot.enable": {
        "*": true,
        "yaml": true,
        "plaintext": true,
        "markdown": true,
        "javascript": true,
        "typescript": true,
        "json": true,
        "dockerfile": true,
        "shellscript": true
    },
    "github.copilot.advanced": {
        "debug.overrideEngine": "codex",
        "inlineSuggestCount": 3
    },
    "editor.inlineSuggest.enabled": true,
    "editor.suggestOnTriggerCharacters": true,
    "editor.acceptSuggestionOnEnter": "smart",
    "editor.quickSuggestions": {
        "other": true,
        "comments": true,
        "strings": true
    },
    "files.associations": {
        "*.js": "javascript",
        "*.ts": "typescript",
        "*.jsx": "javascriptreact",
        "*.tsx": "typescriptreact",
        "Dockerfile*": "dockerfile",
        "*.yml": "yaml",
        "*.yaml": "yaml"
    },
    "emmet.includeLanguages": {
        "javascript": "javascriptreact"
    },
    "typescript.preferences.includePackageJsonAutoImports": "auto",
    "javascript.preferences.includePackageJsonAutoImports": "auto",
    "files.exclude": {
        "**/node_modules": true,
        "**/dist": true,
        "**/build": true,
        "**/.git": true
    },
    "search.exclude": {
        "**/node_modules": true,
        "**/dist": true,
        "**/build": true
    },
    "terminal.integrated.defaultProfile.linux": "bash"
}
EOF

# Create tasks configuration for common development tasks
cat > .vscode/tasks.json << 'EOF'
{
    "version": "2.0.0",
    "tasks": [
        {
            "label": "Start Development Environment",
            "type": "shell",
            "command": "./scripts/dev-start.sh",
            "group": "build",
            "presentation": {
                "echo": true,
                "reveal": "always",
                "focus": false,
                "panel": "shared"
            },
            "problemMatcher": []
        },
        {
            "label": "Backend Development Server",
            "type": "shell",
            "command": "npm run dev",
            "options": {
                "cwd": "${workspaceFolder}/backend"
            },
            "group": "build",
            "presentation": {
                "echo": true,
                "reveal": "always",
                "focus": false,
                "panel": "new"
            },
            "problemMatcher": []
        },
        {
            "label": "Frontend Development Server",
            "type": "shell",
            "command": "npm run dev",
            "options": {
                "cwd": "${workspaceFolder}/frontend"
            },
            "group": "build",
            "presentation": {
                "echo": true,
                "reveal": "always",
                "focus": false,
                "panel": "new"
            },
            "problemMatcher": []
        },
        {
            "label": "Build All",
            "type": "shell",
            "command": "npm run build",
            "options": {
                "cwd": "${workspaceFolder}/frontend"
            },
            "group": "build",
            "dependsOrder": "sequence",
            "presentation": {
                "echo": true,
                "reveal": "always",
                "focus": false,
                "panel": "shared"
            },
            "problemMatcher": []
        }
    ]
}
EOF

# Create launch configuration for debugging
cat > .vscode/launch.json << 'EOF'
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": "Debug Backend",
            "type": "node",
            "request": "launch",
            "program": "${workspaceFolder}/backend/server.js",
            "cwd": "${workspaceFolder}/backend",
            "env": {
                "NODE_ENV": "development"
            },
            "console": "integratedTerminal",
            "internalConsoleOptions": "neverOpen"
        },
        {
            "name": "Attach to Backend",
            "type": "node",
            "request": "attach",
            "port": 9229,
            "restart": true,
            "localRoot": "${workspaceFolder}/backend",
            "remoteRoot": "/app"
        }
    ]
}
EOF

echo "✅ Development environment setup complete!"
echo ""
echo "🎯 Quick Start Commands:"
echo "  • ./scripts/dev-start.sh    - Start full development environment"
echo "  • backend-dev               - Start backend development server"
echo "  • frontend-dev              - Start frontend development server"
echo ""
echo "🤖 AI Coding Features:"
echo "  • GitHub Copilot is enabled for all file types"
echo "  • Use Ctrl+I for inline suggestions"
echo "  • Use Ctrl+Shift+P and search 'Copilot' for chat features"
echo ""
echo "📁 Workspace configured with:"
echo "  • VS Code settings optimized for AI coding"
echo "  • Debug configurations for Node.js"
echo "  • Build tasks for common operations"
echo "  • Helpful aliases in terminal"