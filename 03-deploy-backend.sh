#!/usr/bin/env bash
set -euo pipefail

APP_USER="${APP_USER:-nostalgia}"
APP_GROUP="${APP_GROUP:-nostalgia}"

BACKEND_DIR="${BACKEND_DIR:-/opt/nostalgia/backend}"

# Your repo (defaulted)
REPO_URL="${REPO_URL:-https://github.com/cksjava/nostalgia-backend.git}"
REPO_BRANCH="${REPO_BRANCH:-main}"

# Use SKIP_GIT=1 if you already copied the backend into BACKEND_DIR
SKIP_GIT="${SKIP_GIT:-0}"

NODE_ENV="${NODE_ENV:-production}"
RUN_NPM_CI="${RUN_NPM_CI:-1}"      # 1 => npm ci, 0 => npm install
BUILD_CMD="${BUILD_CMD:-build}"    # npm run build
API_SERVICE="${API_SERVICE:-nostalgia-api.service}"

# Must match /etc/systemd/system/nostalgia-api.service
EXPECTED_ENTRY="${EXPECTED_ENTRY:-/opt/nostalgia/backend/dist/app.js}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Please run as root: sudo $0"
  exit 1
fi

echo "==> Ensuring backend dir exists"
mkdir -p "$(dirname "${BACKEND_DIR}")"
chown -R "${APP_USER}:${APP_GROUP}" "$(dirname "${BACKEND_DIR}")"

if [[ "${SKIP_GIT}" != "1" ]]; then
  if [[ ! -d "${BACKEND_DIR}/.git" ]]; then
    echo "==> Cloning backend repo into ${BACKEND_DIR}"
    rm -rf "${BACKEND_DIR}"
    sudo -u "${APP_USER}" -H git clone --branch "${REPO_BRANCH}" --depth 1 "${REPO_URL}" "${BACKEND_DIR}"
  else
    echo "==> Updating backend repo in ${BACKEND_DIR}"
    sudo -u "${APP_USER}" -H bash -lc "cd '${BACKEND_DIR}' && git fetch --all --prune"
    sudo -u "${APP_USER}" -H bash -lc "cd '${BACKEND_DIR}' && git checkout '${REPO_BRANCH}'"
    sudo -u "${APP_USER}" -H bash -lc "cd '${BACKEND_DIR}' && git pull --ff-only"
  fi
else
  echo "==> SKIP_GIT=1, using existing code at ${BACKEND_DIR}"
  if [[ ! -d "${BACKEND_DIR}" ]]; then
    echo "ERROR: ${BACKEND_DIR} not found."
    exit 1
  fi
fi

echo "==> Ownership"
chown -R "${APP_USER}:${APP_GROUP}" "${BACKEND_DIR}"

echo "==> Install deps"
if [[ "${RUN_NPM_CI}" == "1" ]]; then
  sudo -u "${APP_USER}" -H bash -lc "cd '${BACKEND_DIR}' && npm ci"
else
  sudo -u "${APP_USER}" -H bash -lc "cd '${BACKEND_DIR}' && npm install"
fi

echo "==> Build (npm run ${BUILD_CMD})"
sudo -u "${APP_USER}" -H bash -lc "cd '${BACKEND_DIR}' && NODE_ENV='${NODE_ENV}' npm run '${BUILD_CMD}'"

echo "==> Verify entry: ${EXPECTED_ENTRY}"
if [[ ! -f "${EXPECTED_ENTRY}" ]]; then
  echo "ERROR: expected entry not found: ${EXPECTED_ENTRY}"
  echo "Fix by either:"
  echo "  1) Changing EXPECTED_ENTRY when running this script, OR"
  echo "  2) Updating API_ENTRY in /etc/systemd/system/nostalgia-api.service"
  echo "Then:"
  echo "  sudo systemctl daemon-reload && sudo systemctl restart ${API_SERVICE}"
  exit 1
fi

echo "==> Restart API"
systemctl restart "${API_SERVICE}"

echo "==> Status"
systemctl --no-pager --full status "${API_SERVICE}" || true

echo ""
echo "Logs:"
echo "  sudo journalctl -u ${API_SERVICE} -f"
echo ""
echo "Health check (if /health exists):"
echo "  curl -s http://127.0.0.1:\$(grep '^PORT=' /etc/nostalgia/api.env | cut -d= -f2)/health"
