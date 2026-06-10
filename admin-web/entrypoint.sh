#!/bin/sh
set -e

# Replace the backend URL placeholder in nginx config
BACKEND="${BACKEND_URL:-http://localhost:3000}"
sed -i "s|BACKEND_URL_PLACEHOLDER|${BACKEND}|g" /etc/nginx/conf.d/default.conf

echo "Admin panel starting — proxying /api to: ${BACKEND}"

exec nginx -g "daemon off;"
