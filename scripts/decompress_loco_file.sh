#!/bin/bash
# Decompress a LEGO Loco asset from a network source
# Usage: decompress_loco_file.sh <source> <output>

set -e

if [ $# -lt 2 ]; then
  echo "Usage: $0 <source> <output>" >&2
  exit 1
fi

SRC="$1"
OUT="$2"

TMPDIR=$(mktemp -d)
TMPFILE="$TMPDIR/input.bin"

if [[ "$SRC" =~ ^https?:// ]]; then
  curl -L "$SRC" -o "$TMPFILE"
else
  cp "$SRC" "$TMPFILE"
fi

# Compile Java tool if classes not built
if [ ! -f "$TMPDIR/Main.class" ]; then
  javac -d "$TMPDIR" tools/decompressor/*.java
fi

java -cp "$TMPDIR" Main "$TMPFILE" "$OUT"

rm -rf "$TMPDIR"
