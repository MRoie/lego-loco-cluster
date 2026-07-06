#!/bin/sh
set -e

# If environment variables are set, use the template
if [ -n "$BACKEND_HOST" ] || [ -n "$BACKEND_PORT" ] || [ -n "$FRONTEND_PORT" ]; then
    echo "Using nginx template with environment variables..."
    echo "BACKEND_HOST=${BACKEND_HOST:-backend}"
    echo "BACKEND_PORT=${BACKEND_PORT:-3001}"
    echo "FRONTEND_PORT=${FRONTEND_PORT:-3000}"
    
    # Process template with environment variables
    envsubst '${BACKEND_HOST} ${BACKEND_PORT} ${FRONTEND_PORT}' < /etc/nginx/templates/default.conf.template > /etc/nginx/conf.d/default.conf
else
    echo "Using static nginx configuration..."
fi

# Print the nginx config being used (for debugging)
echo "=== Nginx Configuration ==="
cat /etc/nginx/conf.d/default.conf
echo "=========================="

# Start nginx
exec "$@"
