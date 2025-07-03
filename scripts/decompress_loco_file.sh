#!/bin/bash
# Decompress a LEGO Loco asset from a network source
# Usage: decompress_loco_file.sh <source> [output]

set -e

if [ $# -lt 1 ]; then
  echo "Usage: $0 <source> [output]" >&2
  exit 1
fi

SRC="$1"
NET_SHARE_DIR="${NET_SHARE_DIR:-$(dirname "$0")/../net-shares}"
mkdir -p "$NET_SHARE_DIR"

if [ $# -ge 2 ]; then
  OUT="$2"
else
  OUT="$NET_SHARE_DIR/$(basename "$SRC" .dat).decoded"
fi

TMPDIR=$(mktemp -d)
TMPFILE="$TMPDIR/input.bin"

if [[ "$SRC" =~ ^https?:// ]]; then
  curl -L "$SRC" -o "$TMPFILE"
else
  cp "$SRC" "$TMPFILE"
fi

# Compile Java tool if classes not built
if [ ! -f "$TMPDIR/Main.class" ]; then
  javac -d "$TMPDIR" -classpath "tools/decompressor" tools/decompressor/*.java
fi

java -cp "$TMPDIR" Main "$TMPFILE" "$OUT"

# Copy result to network share if it's outside NET_SHARE_DIR
DEST="$NET_SHARE_DIR/$(basename "$OUT")"
if [ "$OUT" != "$DEST" ]; then
  cp "$OUT" "$DEST"
fi

rm -rf "$TMPDIR"
