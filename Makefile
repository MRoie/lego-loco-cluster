# Lego Loco Cluster - Makefile for Development

.PHONY: help setup up down logs status restart clean build health test cleanup-ports
.DEFAULT_GOAL := help

# Variables
COMPOSE_FILES := -f compose/docker-compose.yml -f compose/docker-compose.override.yml
COMPOSE_PROD := -f compose/docker-compose.yml -f compose/docker-compose.prod.yml
COMPOSE_MINIMAL := -f compose/docker-compose.minimal.yml

help: ## Show this help message
	@echo "Lego Loco Cluster - Development Commands"
	@echo "========================================"
	@echo ""
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo ""
	@echo "Examples:"
	@echo "  make up          # Start development environment"
	@echo "  make up-full     # Start with all 9 emulators"
	@echo "  make up-prod     # Start production environment"
	@echo "  make logs        # Show all logs"
	@echo "  make logs-backend # Show backend logs only"

setup: ## Setup prerequisites and TAP bridge
	@echo "🔧 Setting up prerequisites..."
	@./docker-compose.sh setup

up: ## Start development environment (3 emulators)
	@echo "🚀 Starting development environment..."
	@./docker-compose.sh cleanup-ports
	@./docker-compose.sh up dev

up-full: ## Start development environment with all 9 emulators
	@echo "🚀 Starting development environment (full)..."
	@./docker-compose.sh cleanup-ports
	@./docker-compose.sh up dev --full

up-prod: ## Start production environment
	@echo "🚀 Starting production environment..."
	@./docker-compose.sh cleanup-ports
	@./docker-compose.sh up prod

up-minimal: ## Start minimal environment (1 emulator)
	@echo "🚀 Starting minimal environment..."
	@docker-compose $(COMPOSE_MINIMAL) up -d

down: ## Stop and remove all containers
	@echo "🛑 Stopping all services..."
	@./docker-compose.sh down

build: ## Build all container images
	@echo "🏗️  Building container images..."
	@docker-compose $(COMPOSE_FILES) build

rebuild: ## Rebuild images without cache
	@echo "🏗️  Rebuilding container images..."
	@docker-compose $(COMPOSE_FILES) build --no-cache

logs: ## Show logs for all services
	@docker-compose $(COMPOSE_FILES) logs -f

logs-frontend: ## Show frontend logs
	@docker-compose $(COMPOSE_FILES) logs -f frontend

logs-backend: ## Show backend logs
	@docker-compose $(COMPOSE_FILES) logs -f backend

logs-emulator: ## Show emulator logs (first instance)
	@docker-compose $(COMPOSE_FILES) logs -f emulator-0

status: ## Show status of all services
	@./docker-compose.sh status

health: ## Run health checks
	@./health-check.sh

restart: ## Restart all services
	@echo "🔄 Restarting all services..."
	@docker-compose $(COMPOSE_FILES) restart

restart-frontend: ## Restart frontend service
	@echo "🔄 Restarting frontend..."
	@docker-compose $(COMPOSE_FILES) restart frontend

restart-backend: ## Restart backend service
	@echo "🔄 Restarting backend..."
	@docker-compose $(COMPOSE_FILES) restart backend

restart-emulator: ## Restart first emulator
	@echo "🔄 Restarting emulator-0..."
	@docker-compose $(COMPOSE_FILES) restart emulator-0

clean: ## Clean up everything (containers, images, volumes)
	@./docker-compose.sh clean

cleanup-ports: ## Clean up port conflicts and stop loco containers
	@echo "🧹 Cleaning up port conflicts..."
	@./docker-compose.sh cleanup-ports

test: ## Run basic connectivity tests
	@echo "🧪 Running basic tests..."
	@sleep 2
	@echo "Testing frontend..."
	@curl -s -o /dev/null -w "Frontend: %{http_code}\n" http://localhost:3000 || echo "Frontend: FAIL"
	@echo "Testing backend..."
	@curl -s -o /dev/null -w "Backend: %{http_code}\n" http://localhost:3001/health || echo "Backend: FAIL"
	@echo "Testing registry..."
	@curl -s -o /dev/null -w "Registry: %{http_code}\n" http://localhost:5000/v2/ || echo "Registry: FAIL"

shell-frontend: ## Open shell in frontend container
	@docker-compose $(COMPOSE_FILES) exec frontend sh

shell-backend: ## Open shell in backend container
	@docker-compose $(COMPOSE_FILES) exec backend sh

shell-emulator: ## Open shell in emulator container
	@docker-compose $(COMPOSE_FILES) exec emulator-0 bash

# Development helpers
dev-install: ## Install dependencies for development
	@echo "📦 Installing dependencies..."
	@cd frontend && npm install
	@cd backend && npm install

dev-build-frontend: ## Build frontend for production
	@echo "🏗️  Building frontend..."
	@cd frontend && npm run build

dev-lint: ## Run linting
	@echo "🔍 Running linters..."
	@cd frontend && npm run lint || true
	@cd backend && npm run lint || true

# Image management
pull: ## Pull latest images
	@echo "⬇️  Pulling latest images..."
	@docker-compose $(COMPOSE_FILES) pull

push: ## Push images to registry
	@echo "⬆️  Pushing images to registry..."
	@docker-compose $(COMPOSE_FILES) push

tag-latest: ## Tag images as latest
	@echo "🏷️  Tagging images as latest..."
	@docker tag lego-loco-cluster_frontend:latest localhost:5000/lego-loco-frontend:latest
	@docker tag lego-loco-cluster_backend:latest localhost:5000/lego-loco-backend:latest
	@docker tag lego-loco-cluster_emulator-0:latest localhost:5000/lego-loco-qemu:latest

# Monitoring and debugging
ps: ## Show running containers
	@docker-compose $(COMPOSE_FILES) ps

top: ## Show running processes in containers
	@docker-compose $(COMPOSE_FILES) top

stats: ## Show container resource usage
	@docker stats --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}"

inspect-network: ## Inspect Docker network
	@docker network inspect lego-loco-cluster_loco-network 2>/dev/null || echo "Network not found"

inspect-bridge: ## Inspect TAP bridge
	@ip addr show loco-br 2>/dev/null || echo "TAP bridge not found"

# Quick commands for common tasks
quick-start: setup up health ## Quick start: setup + up + health check

quick-restart: down up health ## Quick restart: down + up + health check

quick-test: up-minimal test down ## Quick test: minimal setup + test + cleanup

# Environment specific
env-dev: ## Set development environment
	@cp .env.example .env
	@echo "NODE_ENV=development" >> .env
	@echo "✅ Development environment configured"

env-prod: ## Set production environment
	@cp .env.example .env
	@echo "NODE_ENV=production" >> .env
	@echo "✅ Production environment configured"

# Documentation
docs: ## Show important URLs and info
	@echo "📋 Lego Loco Cluster - Service URLs"
	@echo "==================================="
	@echo ""
	@echo "🌐 Web Services:"
	@echo "  Frontend:    http://localhost:3000"
	@echo "  Backend:     http://localhost:3001"
	@echo "  Registry:    http://localhost:5000"
	@echo ""
	@echo "🖥️  VNC Access:"
	@echo "  Emulator 0:  vnc://localhost:5901"
	@echo "  Emulator 1:  vnc://localhost:5902"
	@echo "  Emulator 2:  vnc://localhost:5903"
	@echo ""
	@echo "🌐 Web VNC:"
	@echo "  Emulator 0:  http://localhost:6080"
	@echo "  Emulator 1:  http://localhost:6081"
	@echo "  Emulator 2:  http://localhost:6082"
	@echo ""
	@echo "📚 Documentation:"
	@echo "  Docker Compose: docs/legacy/DOCKER_COMPOSE.md"
	@echo "  Main README:    README.md"
	@echo "  Private Registry: docs/PRIVATE_REGISTRY_GUIDE.md"
