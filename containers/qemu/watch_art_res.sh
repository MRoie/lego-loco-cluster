#!/usr/bin/env bash
set -euo pipefail

ART_RES_ROOT="${ART_RES_ROOT:-/nfs}"
POD_NAME="${POD_NAME:-$(hostname)}"
WATCH_DIR="${ART_RES_ROOT}/${POD_NAME}/art/res"

mkdir -p "$WATCH_DIR"
cd "$WATCH_DIR"

# Initialize git repo if not existing
if [ ! -d .git ]; then
  git init >/dev/null 2>&1
fi

git config user.name "${GIT_USER_NAME:-loco-watcher}"
git config user.email "${GIT_USER_EMAIL:-watcher@example.com}"

echo "📂 Watching $WATCH_DIR for changes..."

while inotifywait -r -e modify,create,delete,move .; do
  git add -A
  if ! git diff --cached --quiet; then
    git commit -m "Update art resources" >/dev/null 2>&1 || true
  fi
  rsync -a . "${ART_RES_ROOT}/${POD_NAME}"/
done

