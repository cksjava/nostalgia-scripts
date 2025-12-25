#!/usr/bin/env bash
set -euo pipefail

APP_USER="${APP_USER:-nostalgia}"
APP_GROUP="${APP_GROUP:-nostalgia}"

FRONTEND_DIR="${FRONTEND_DIR:-/opt/nostalgia/frontend}"

REPO_URL="${REPO_URL:-https://github.com/cksjava/nostalgia.git}"
REPO_BRANCH="${REPO_BRANCH:-main}"
SKIP_GIT="${SKIP_GIT:-0}"

RUN_NPM_CI="${RUN_NPM_CI:-1}"       # 1 => npm ci, 0 => npm install
BUILD_CMD="${BUILD_CMD:-build}"     # npm run build

NGINX_SITE_NAME="${NGINX_SITE_NAME:-nostalgia}"
WEB_ROOT="${WEB_ROOT:-/var/www/nostalgia}"

API_UPSTREAM="${API_UPSTREAM:-http://127.0.0.1:3001}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Please run as root: sudo $0"
  exit 1
fi

echo "==> Installing nginx if needed"
if ! command -v nginx >/dev/null 2>&1; then
  apt-get update -y
  apt-get install -y --no-install-recommends nginx
fi

echo "==> Ensuring parent dir exists"
mkdir -p "$(dirname "${FRONTEND_DIR}")"
chown -R "${APP_USER}:${APP_GROUP}" "$(dirname "${FRONTEND_DIR}")"

if [[ "${SKIP_GIT}" != "1" ]]; then
  if [[ ! -d "${FRONTEND_DIR}/.git" ]]; then
    echo "==> Cloning frontend repo into ${FRONTEND_DIR}"
    rm -rf "${FRONTEND_DIR}"
    sudo -u "${APP_USER}" -H git clone --branch "${REPO_BRANCH}" --depth 1 "${REPO_URL}" "${FRONTEND_DIR}"
  else
    echo "==> Updating frontend repo in ${FRONTEND_DIR}"
    sudo -u "${APP_USER}" -H bash -lc "cd '${FRONTEND_DIR}' && git fetch --all --prune"
    sudo -u "${APP_USER}" -H bash -lc "cd '${FRONTEND_DIR}' && git checkout '${REPO_BRANCH}'"
    sudo -u "${APP_USER}" -H bash -lc "cd '${FRONTEND_DIR}' && git pull --ff-only"
  fi
else
  echo "==> SKIP_GIT=1, using existing code at ${FRONTEND_DIR}"
  if [[ ! -d "${FRONTEND_DIR}" ]]; then
    echo "ERROR: ${FRONTEND_DIR} not found."
    exit 1
  fi
fi

echo "==> Ownership"
chown -R "${APP_USER}:${APP_GROUP}" "${FRONTEND_DIR}"

echo "==> Install deps"
if [[ "${RUN_NPM_CI}" == "1" ]]; then
  sudo -u "${APP_USER}" -H bash -lc "cd '${FRONTEND_DIR}' && npm ci"
else
  sudo -u "${APP_USER}" -H bash -lc "cd '${FRONTEND_DIR}' && npm install"
fi

echo "==> Build (npm run ${BUILD_CMD})"
sudo -u "${APP_USER}" -H bash -lc "cd '${FRONTEND_DIR}' && npm run '${BUILD_CMD}'"

echo "==> Detect build output folder"
OUT_DIR=""
if [[ -d "${FRONTEND_DIR}/dist" ]]; then
  OUT_DIR="${FRONTEND_DIR}/dist"
elif [[ -d "${FRONTEND_DIR}/build" ]]; then
  OUT_DIR="${FRONTEND_DIR}/build"
else
  echo "ERROR: Could not find dist/ or build/ in ${FRONTEND_DIR}."
  echo "If your build output differs, update this script accordingly."
  exit 1
fi
echo "Using output: ${OUT_DIR}"

echo "==> Deploy to web root: ${WEB_ROOT}"
mkdir -p "${WEB_ROOT}"
rm -rf "${WEB_ROOT:?}/"*
cp -a "${OUT_DIR}/." "${WEB_ROOT}/"
chown -R www-data:www-data "${WEB_ROOT}"
chmod -R 755 "${WEB_ROOT}"

echo "==> Writing nginx site: /etc/nginx/sites-available/${NGINX_SITE_NAME}"
cat >"/etc/nginx/sites-available/${NGINX_SITE_NAME}" <<EOF
server {
  listen 80 default_server;
  listen [::]:80 default_server;

  server_name nostalgia.local;

  root ${WEB_ROOT};
  index index.html;

  # React SPA routing
  location / {
    try_files \$uri \$uri/ /index.html;
  }

  # API reverse proxy (same-origin => no CORS needed)
  location /api/ {
    proxy_pass ${API_UPSTREAM}/;
    proxy_http_version 1.1;

    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;

    # If you later use SSE/websockets, keep these:
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
  }

  # Reasonable caching for static assets
  location ~* \.(?:js|css|png|jpg|jpeg|gif|svg|ico|webp|woff|woff2|ttf|map)$ {
    expires 7d;
    add_header Cache-Control "public, max-age=604800, immutable";
    try_files \$uri =404;
  }
}
EOF

echo "==> Enabling site"
rm -f /etc/nginx/sites-enabled/default || true
ln -sf "/etc/nginx/sites-available/${NGINX_SITE_NAME}" "/etc/nginx/sites-enabled/${NGINX_SITE_NAME}"

echo "==> Test nginx config"
nginx -t

echo "==> Reload nginx"
systemctl enable nginx
systemctl reload nginx

echo ""
echo "Done."
echo "Frontend: http://<pi-ip>/"
echo "API proxied: http://<pi-ip>/api/"
echo ""
echo "Tip: If your backend listens on /api already, keep it. If it listens on /, this proxy still works because it forwards /api/* -> /* upstream."
