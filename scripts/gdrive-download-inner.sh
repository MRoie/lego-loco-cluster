#!/bin/sh
set -e
apk add --no-cache curl >/tmp/apk.log 2>&1
GDRIVE_ID="1U_IfHPHLxaQH8lT4BpY1qOAr-ytIFLSl"
cookie=/tmp/cookie
html=/tmp/page.html
base="https://drive.google.com/uc?export=download&id=${GDRIVE_ID}"
echo "==> fetching confirm token"
curl -L -c "$cookie" -s "$base" -o "$html"
confirm=$(grep -o 'confirm=[^&"]*' "$html" | head -n1 | cut -d= -f2)
uuid=$(grep -o 'name="uuid" value="[^"]*"' "$html" | head -n1 | sed 's/.*value="//;s/"//')
echo "confirm=$confirm uuid=$uuid"
url="https://drive.usercontent.google.com/download?id=${GDRIVE_ID}&export=download&confirm=${confirm}"
if [ -n "$uuid" ]; then
  url="${url}&uuid=${uuid}"
fi
echo "==> downloading from: $url"
curl -L -b "$cookie" "$url" -o /out/win98-gdrive.qcow2 --progress-bar
echo "==> done"
ls -la /out/win98-gdrive.qcow2
file /out/win98-gdrive.qcow2 2>/dev/null || true
