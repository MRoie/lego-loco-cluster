#!/usr/bin/env bash
#
# scripts/deploy_ev3.sh  –  Find the EV3 brick, push all client resources,
#                           and enable an autostart systemd service.
# Usage: ./deploy_ev3.sh [HOST] [USER] [PASS]
# If HOST is omitted we auto-scan (USB, mDNS, or LAN).
set -euo pipefail

## ---- configurable defaults -------------------------------------------------
BRICK_USER=${2:-robot}
BRICK_PASS=${3:-maker}          # default ev3dev/Pybricks password :contentReference[oaicite:0]{index=0}
LOCAL_ROOT="$(git rev-parse --show-toplevel)/client/ev3"
REMOTE_ROOT="/home/${BRICK_USER}/ev3"
SERVICE_FILE="scripts/ev3-p2p.service"

## ---- 1. locate the brick ---------------------------------------------------
HOST=${1:-}

if [[ -z "$HOST" ]]; then
  echo "🔍  Searching for EV3 brick..."
  # 1a. USB/RNDIS (hard-coded address)
  if ping -c1 -W1 192.168.0.1 &>/dev/null; then
    HOST=192.168.0.1
  else
    # 1b. mDNS
    if command -v avahi-browse &>/dev/null; then
      HOST=$(avahi-browse -rt _workstation._tcp | awk -F';' '/ev3dev/ {print $8; exit}')
    fi
    # 1c. fallback: scan LAN for SSH banner “ev3dev”
    if [[ -z "$HOST" ]]; then
      SUBNET=$(ip route | awk '/kernel/ {print $1; exit}')
      HOST=$(nmap -p22 --open "$SUBNET" -oG - | awk '/ev3dev/ {print $2; exit}')
    fi
  fi
fi

[[ -n "$HOST" ]] || { echo "❌  Could not locate EV3 brick."; exit 1; }
echo "✅  EV3 found at $HOST"

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

## ---- 2. copy files ---------------------------------------------------------
echo "📦  Copying client resources → $HOST ..."
sshpass -p "$BRICK_PASS" rsync -az --delete -e "ssh $SSH_OPTS" \
       "$LOCAL_ROOT/"  "$BRICK_USER@$HOST:$REMOTE_ROOT/"

## ---- 3. install & enable systemd service -----------------------------------
echo "🛠   Installing systemd unit ..."
sshpass -p "$BRICK_PASS" scp $SSH_OPTS "$SERVICE_FILE" \
       "$BRICK_USER@$HOST:/tmp/ev3-p2p.service"

sshpass -p "$BRICK_PASS" ssh $SSH_OPTS "$BRICK_USER@$HOST" <<EOF
  echo "$BRICK_PASS" | sudo -S mv /tmp/ev3-p2p.service /etc/systemd/system/
  echo "$BRICK_PASS" | sudo -S systemctl daemon-reload
  echo "$BRICK_PASS" | sudo -S systemctl enable --now ev3-p2p.service
EOF

echo "🚂  Deployment complete!  Press a button on the brick – the target pod should respond."
