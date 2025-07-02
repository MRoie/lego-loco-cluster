#!/usr/bin/env bash
# Measure average FPS of an emulator stream

set -euo pipefail

LOG_DIR=${LOG_DIR:-benchmark_logs}
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/ffmpeg_benchmark.log"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <stream-url> [duration]" >&2
  exit 1
fi

STREAM_URL="$1"
DURATION="${2:-10}"
TMPFILE="/tmp/vr_benchmark.mp4"

if ffmpeg -y -loglevel error -i "$STREAM_URL" -t "$DURATION" -an -c copy "$TMPFILE" >"$LOG_FILE" 2>&1; then
  FPS=$(ffprobe -v error -select_streams v:0 -show_entries stream=avg_frame_rate -of default=noprint_wrappers=1:nokey=1 "$TMPFILE" | awk -F'/' '{ if ($2==0) print 0; else printf "%.2f", $1/$2 }')
else
  echo "Failed to record stream" >>"$LOG_FILE"
  FPS=0
fi
rm -f "$TMPFILE"

echo "Average FPS: $FPS"
echo "Log written to $LOG_FILE"
