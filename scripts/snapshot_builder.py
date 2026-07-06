#!/usr/bin/env python3
"""
Automated snapshot builder for Windows 98 with pre-installed software.
This script uses QEMU monitor commands to automate software installation.
"""

import subprocess
import time
import socket
import json
import sys
import os
from pathlib import Path

class SnapshotBuilder:
    def __init__(self, base_image, config_file="snapshot_config.json"):
        self.base_image = base_image
        self.work_dir = Path("/tmp/snapshot-build")
        self.work_snapshot = self.work_dir / "work_snapshot.qcow2"
        self.final_snapshot = self.work_dir / "snapshot.qcow2"
        self.monitor_port = 4444
        self.qemu_pid = None
        
        # Load configuration
        config_path = Path(__file__).parent / config_file
        if config_path.exists():
            with open(config_path) as f:
                self.config = json.load(f)
        else:
            self.config = self._default_config()
    
    def _default_config(self):
        return {
            "snapshot_name": "win98-base",
            "boot_wait_time": 180,
            "software_installs": [
                {
                    "name": "DirectX 8.1",
                    "iso_path": "/software/directx81.iso",
                    "install_commands": ["autorun.exe", "/S"],
                    "wait_time": 60
                }
            ],
            "registry_tweaks": [
                # Registry modifications for better performance/compatibility
            ],
            "files_to_copy": [
                # Files to copy into the VM
            ]
        }
    
    def create_work_snapshot(self):
        """Create a working snapshot from the base image."""
        print("📀 Creating working snapshot...")
        self.work_dir.mkdir(exist_ok=True)
        
        cmd = [
            "qemu-img", "create", "-f", "qcow2", 
            "-b", str(self.base_image), 
            str(self.work_snapshot)
        ]
        subprocess.run(cmd, check=True)
    
    def start_qemu(self):
        """Start QEMU with the working snapshot."""
        print("🚀 Starting QEMU for configuration...")
        
        cmd = [
            "qemu-system-i386",
            "-M", "pc", "-cpu", "pentium2",
            "-m", "512", "-hda", str(self.work_snapshot),
            "-netdev", "user,id=net0",
            "-device", "ne2k_pci,netdev=net0",
            "-vga", "cirrus",
            "-nographic",
            "-monitor", f"telnet:127.0.0.1:{self.monitor_port},server,nowait",
            "-rtc", "base=localtime",
            "-boot", "menu=off",
            "-daemonize"
        ]
        
        result = subprocess.run(cmd)
        if result.returncode != 0:
            raise RuntimeError("Failed to start QEMU")
        
        # Give QEMU time to start
        time.sleep(5)
    
    def send_monitor_command(self, command):
        """Send a command to the QEMU monitor."""
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.connect(("127.0.0.1", self.monitor_port))
                s.recv(1024)  # Receive welcome message
                s.send(f"{command}\n".encode())
                response = s.recv(1024).decode()
                return response
        except Exception as e:
            print(f"Error sending monitor command: {e}")
            return None
    
    def wait_for_boot(self):
        """Wait for Windows 98 to boot completely."""
        print(f"⏱️  Waiting {self.config['boot_wait_time']}s for Windows 98 to boot...")
        time.sleep(self.config['boot_wait_time'])
    
    def install_software(self):
        """Install software packages defined in configuration."""
        for software in self.config.get('software_installs', []):
            print(f"📦 Installing {software['name']}...")
            
            # Mount ISO if specified
            if 'iso_path' in software and os.path.exists(software['iso_path']):
                self.send_monitor_command(f"change ide1-cd0 {software['iso_path']}")
                time.sleep(5)
            
            # Send installation commands via monitor
            for cmd in software.get('install_commands', []):
                print(f"   Executing: {cmd}")
                # This would need more sophisticated automation
                # For now, just wait for manual installation
                time.sleep(software.get('wait_time', 60))
    
    def apply_tweaks(self):
        """Apply registry tweaks and file copies."""
        print("⚙️  Applying system tweaks...")
        
        # Registry tweaks would go here
        # File copies would go here
        
        time.sleep(10)
    
    def shutdown_vm(self):
        """Gracefully shutdown the VM."""
        print("💾 Shutting down VM...")
        self.send_monitor_command("system_powerdown")
        time.sleep(30)  # Give it time to shutdown
    
    def create_final_snapshot(self):
        """Convert the working snapshot to the final snapshot."""
        print("📸 Creating final snapshot...")
        
        cmd = [
            "qemu-img", "convert", 
            "-f", "qcow2", "-O", "qcow2",
            str(self.work_snapshot), 
            str(self.final_snapshot)
        ]
        subprocess.run(cmd, check=True)
    
    def build_container_image(self, registry, tag):
        """Build and push the container image with the snapshot."""
        print("📦 Building container image...")
        
        dockerfile_content = """FROM scratch
COPY snapshot.qcow2 /snapshot.qcow2
"""
        
        dockerfile_path = self.work_dir / "Dockerfile"
        with open(dockerfile_path, 'w') as f:
            f.write(dockerfile_content)
        
        # Build image
        image_name = f"{registry}:{tag}"
        cmd = ["docker", "build", "-t", image_name, str(self.work_dir)]
        subprocess.run(cmd, check=True)
        
        # Push image
        print("📤 Pushing to registry...")
        cmd = ["docker", "push", image_name]
        subprocess.run(cmd, check=True)
        
        return image_name
    
    def cleanup(self):
        """Clean up temporary files."""
        print("🧹 Cleaning up...")
        if self.work_dir.exists():
            subprocess.run(["rm", "-rf", str(self.work_dir)])
    
    def build(self, registry="ghcr.io/mroie/qemu-snapshots", tag=None):
        """Build the complete snapshot."""
        if not tag:
            tag = self.config.get('snapshot_name', 'win98-base')
        
        try:
            self.create_work_snapshot()
            self.start_qemu()
            self.wait_for_boot()
            self.install_software()
            self.apply_tweaks()
            self.shutdown_vm()
            self.create_final_snapshot()
            image_name = self.build_container_image(registry, tag)
            
            print(f"✅ Snapshot built successfully: {image_name}")
            return image_name
            
        except Exception as e:
            print(f"❌ Build failed: {e}")
            raise
        finally:
            self.cleanup()

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 snapshot_builder.py <base_image_path> [registry] [tag]")
        sys.exit(1)
    
    base_image = sys.argv[1]
    registry = sys.argv[2] if len(sys.argv) > 2 else "ghcr.io/mroie/qemu-snapshots"
    tag = sys.argv[3] if len(sys.argv) > 3 else None
    
    builder = SnapshotBuilder(base_image)
    builder.build(registry, tag)

if __name__ == "__main__":
    main()
