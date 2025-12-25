#!/usr/bin/env bash
set -euo pipefail

APP_USER="${APP_USER:-nostalgia}"
APP_GROUP="${APP_GROUP:-nostalgia}"

BASE_DIR="${BASE_DIR:-/opt/nostalgia}"
BACKEND_DIR="${BACKEND_DIR:-/opt/nostalgia/backend}"

DATA_DIR="${DATA_DIR:-/var/lib/nostalgia}"
LOG_DIR="${LOG_DIR:-/var/log/nostalgia}"
RUN_DIR_NAME="${RUN_DIR_NAME:-nostalgia}"

API_PORT="${API_PORT:-3001}"
SQLITE_FILE="${SQLITE_FILE:-/var/lib/nostalgia/player.sqlite}"
MPV_SOCKET="${MPV_SOCKET:-/run/nostalgia/mpv.sock}"

NODE_BIN="${NODE_BIN:-/usr/bin/node}"
# This must match your backend build output (we’ll verify in script 03)
API_ENTRY="${API_ENTRY:-/opt/nostalgia/backend/dist/app.js}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Please run as root: sudo $0"
  exit 1
fi

echo "==> Creating user/group (if missing): ${APP_USER}:${APP_GROUP}"
if ! getent group "${APP_GROUP}" >/dev/null; then
  groupadd --system "${APP_GROUP}"
fi
if ! id -u "${APP_USER}" >/dev/null 2>&1; then
  useradd --system \
    --gid "${APP_GROUP}" \
    --home-dir "${BASE_DIR}" \
    --shell /usr/sbin/nologin \
    --comment "Nostalgia Music Player Service User" \
    "${APP_USER}"
fi

echo "==> Adding ${APP_USER} to audio group"
usermod -aG audio "${APP_USER}" || true

echo "==> Creating directories"
mkdir -p "${BASE_DIR}" "${BACKEND_DIR}" "${DATA_DIR}" "${LOG_DIR}"
chown -R "${APP_USER}:${APP_GROUP}" "${BASE_DIR}" "${DATA_DIR}" "${LOG_DIR}"
chmod 755 "${BASE_DIR}" "${DATA_DIR}" "${LOG_DIR}"

echo "==> Writing environment file: /etc/nostalgia/api.env"
mkdir -p /etc/nostalgia
cat >/etc/nostalgia/api.env <<EOF
PORT=${API_PORT}
SQLITE_FILE=${SQLITE_FILE}
MPV_SOCKET=${MPV_SOCKET}
NODE_ENV=production
# SQL_LOG=1
EOF
chmod 640 /etc/nostalgia/api.env
chown root:"${APP_GROUP}" /etc/nostalgia/api.env || true

echo "==> Creating MPV systemd service: /etc/systemd/system/nostalgia-mpv.service"
cat >/etc/systemd/system/nostalgia-mpv.service <<EOF
[Unit]
Description=Nostalgia MPV background service (IPC enabled)
After=sound.target
Wants=sound.target

[Service]
Type=simple
User=${APP_USER}
Group=${APP_GROUP}

RuntimeDirectory=${RUN_DIR_NAME}
RuntimeDirectoryMode=0755

ExecStart=/usr/bin/mpv --idle=yes --no-video --audio-display=no \\
  --input-ipc-server=${MPV_SOCKET} \\
  --volume=70

Restart=always
RestartSec=1

NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=${DATA_DIR} ${LOG_DIR} /run/${RUN_DIR_NAME}

[Install]
WantedBy=multi-user.target
EOF

echo "==> Creating API systemd service: /etc/systemd/system/nostalgia-api.service"
cat >/etc/systemd/system/nostalgia-api.service <<EOF
[Unit]
Description=Nostalgia Node API
After=network.target nostalgia-mpv.service
Wants=nostalgia-mpv.service

[Service]
Type=simple
User=${APP_USER}
Group=${APP_GROUP}
WorkingDirectory=${BACKEND_DIR}

EnvironmentFile=/etc/nostalgia/api.env

ExecStart=${NODE_BIN} ${API_ENTRY}

Restart=always
RestartSec=2

StandardOutput=journal
StandardError=journal

NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=${BASE_DIR} ${DATA_DIR} ${LOG_DIR} /run/${RUN_DIR_NAME}

[Install]
WantedBy=multi-user.target
EOF

echo "==> systemd reload"
systemctl daemon-reload

echo "==> Enabling MPV service now"
systemctl enable --now nostalgia-mpv.service

echo "==> Enabling API service (will run after script 03 deploy/build)"
systemctl enable nostalgia-api.service || true

echo ""
echo "==> Status:"
systemctl --no-pager --full status nostalgia-mpv.service || true

echo ""
echo "Quick IPC test:"
echo "  echo '{\"command\":[\"get_property\",\"volume\"]}' | socat - ${MPV_SOCKET}"
