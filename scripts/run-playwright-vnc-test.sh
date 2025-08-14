#!/bin/bash

# Playwright VNC Capture Test Wrapper Script
# 
# This script executes the comprehensive Playwright VNC capture test
# for real QEMU VNC usage via the Lego Loco web application
#
# Usage: ./scripts/run-playwright-vnc-test.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "🚀 Starting Playwright VNC Capture Test"
echo "📍 Project root: $PROJECT_ROOT"
echo "⏰ Test duration: 4 minutes with screenshots every 10 seconds"
echo ""

# Ensure we're in the right directory
cd "$PROJECT_ROOT"

# Check if Playwright is installed
if ! command -v npx &> /dev/null; then
    echo "❌ Error: npx not found. Please install Node.js and npm"
    exit 1
fi

if [ ! -d "node_modules/@playwright" ]; then
    echo "❌ Error: Playwright not installed. Run 'npm install' first"
    exit 1
fi

# Check if required services are available
echo "🔍 Checking prerequisites..."

if [ ! -f "backend/package.json" ]; then
    echo "❌ Error: Backend not found at backend/package.json"
    exit 1
fi

if [ ! -f "frontend/package.json" ]; then
    echo "❌ Error: Frontend not found at frontend/package.json"
    exit 1
fi

# Check Docker
if ! command -v docker &> /dev/null; then
    echo "❌ Error: Docker not found. Please install Docker"
    exit 1
fi

# Check if backend and frontend dependencies are installed
echo "📦 Checking backend dependencies..."
if [ ! -d "backend/node_modules" ]; then
    echo "⬇️  Installing backend dependencies..."
    cd backend && npm install && cd ..
fi

echo "📦 Checking frontend dependencies..."
if [ ! -d "frontend/node_modules" ]; then
    echo "⬇️  Installing frontend dependencies..."
    cd frontend && npm install && cd ..
fi

echo "✅ Prerequisites check completed"
echo ""

# Clean up any existing results
echo "🧹 Cleaning up previous test results..."
rm -rf PLAYWRIGHT_VNC_CAPTURE_RESULTS
rm -f PLAYWRIGHT_VNC_CAPTURE_SUMMARY.md

# Execute the test
echo "🎬 Starting Playwright VNC capture test..."
echo "📋 This will:"
echo "   - Start backend service on port 3001"
echo "   - Start frontend service on port 3000"  
echo "   - Start QEMU SoftGPU container with VNC"
echo "   - Open browser and navigate to web application"
echo "   - Capture screenshots every 10 seconds for 4 minutes"
echo "   - Test VNC interactions through web interface"
echo "   - Generate comprehensive report with all screenshots"
echo ""

node scripts/playwright-vnc-capture-test.js

# Check if test was successful
if [ $? -eq 0 ]; then
    echo ""
    echo "🎉 Test completed successfully!"
    echo ""
    echo "📊 Results Summary:"
    echo "   📁 Screenshots: PLAYWRIGHT_VNC_CAPTURE_RESULTS/screenshots/"
    echo "   📄 Full Report: PLAYWRIGHT_VNC_CAPTURE_RESULTS/PLAYWRIGHT_VNC_CAPTURE_REPORT.md"
    echo "   📋 Summary: PLAYWRIGHT_VNC_CAPTURE_SUMMARY.md"
    echo ""
    
    # Show summary if available
    if [ -f "PLAYWRIGHT_VNC_CAPTURE_SUMMARY.md" ]; then
        echo "📖 Test Summary:"
        echo "================================"
        head -20 PLAYWRIGHT_VNC_CAPTURE_SUMMARY.md
        echo "================================"
        echo ""
        echo "📂 View full results in PLAYWRIGHT_VNC_CAPTURE_RESULTS/ directory"
    fi
else
    echo ""
    echo "❌ Test failed with exit code $?"
    echo "📋 Check logs above for error details"
    exit 1
fi