#!/bin/sh
set -e

API_BASE="${PIKI_API_BASE_URL:-${VITE_API_BASE_URL:-}}"
BACKEND="${BACKEND_URL:-${API_BASE:-http://localhost:3000}}"
ESCAPED_API_BASE="$(printf '%s' "${API_BASE}" | sed 's/[\\"]/\\&/g')"

printf 'window.PIKI_API_BASE_URL = "%s";\n' "${ESCAPED_API_BASE}" > /usr/share/nginx/html/config.js
sed -i "s|BACKEND_URL_PLACEHOLDER|${BACKEND}|g" /etc/nginx/conf.d/default.conf

echo "Admin panel starting - proxying /api to: ${BACKEND}"

exec nginx -g "daemon off;"
