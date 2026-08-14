#!/bin/sh
set -e

# Export the default so envsubst never blanks the TLS listen port when the
# variable is unset (a bare assignment would not reach envsubst's environment)
export TLS_PORT="${TLS_PORT:-3443}"

# If environment variables are set, use the template
if [ -n "$BACKEND_HOST" ] || [ -n "$BACKEND_PORT" ] || [ -n "$FRONTEND_PORT" ]; then
    echo "Using nginx template with environment variables..."
    echo "BACKEND_HOST=${BACKEND_HOST:-backend}"
    echo "BACKEND_PORT=${BACKEND_PORT:-3001}"
    echo "FRONTEND_PORT=${FRONTEND_PORT:-3000}"
    echo "TLS_PORT=${TLS_PORT}"

    # Process template with environment variables
    envsubst '${BACKEND_HOST} ${BACKEND_PORT} ${FRONTEND_PORT} ${TLS_PORT}' < /etc/nginx/templates/default.conf.template > /etc/nginx/conf.d/default.conf
else
    echo "Using static nginx configuration..."
fi

# Self-signed fallback for the HTTPS listener (WebXR needs a secure context).
# A mounted kubernetes.io/tls Secret wins: generate only when tls.crt/tls.key
# are absent or empty. The key stays inside the container filesystem — it must
# never land anywhere that could end up in git.
CERT_DIR=/etc/nginx/certs
mkdir -p "$CERT_DIR"
if [ ! -s "$CERT_DIR/tls.crt" ] || [ ! -s "$CERT_DIR/tls.key" ]; then
    echo "No TLS certificate mounted; generating a self-signed one..."
    openssl req -x509 -newkey rsa:2048 -sha256 -days 825 -nodes \
        -keyout "$CERT_DIR/tls.key" -out "$CERT_DIR/tls.crt" \
        -subj "/CN=lego-loco-local" \
        -addext "subjectAltName=DNS:localhost,IP:127.0.0.1,IP:${TLS_SAN_IP:-192.168.1.18}"
fi

# Print the nginx config being used (for debugging)
echo "=== Nginx Configuration ==="
cat /etc/nginx/conf.d/default.conf
echo "=========================="

# Start nginx
exec "$@"
