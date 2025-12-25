#!/usr/bin/env bash
set -euo pipefail

# Raspberry Pi OS Lite (Trixie) bootstrap:
# - Node.js from NodeSource (curl | bash) (not apt's node)
# - mpv + tooling to control it (IPC)
# - deps for scanning audio files and running a Node/TS backend

NODE_MAJOR="${NODE_MAJOR:-20}"   # set NODE_MAJOR=22 if you want newer Node
INSTALL_PM2="${INSTALL_PM2:-1}"  # set INSTALL_PM2=0 to skip pm2

if [[ "${EUID}" -ne 0 ]]; then
  echo "Please run as root: sudo $0"
  exit 1
fi

echo "==> Updating apt index..."
apt-get update -y

echo "==> Installing base utilities..."
apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  apt-transport-https \
  sudo \
  git \
  nano \
  unzip \
  xz-utils \
  jq \
  socat

echo "==> Installing build tools (for native npm modules if needed)..."
apt-get install -y --no-install-recommends \
  build-essential \
  python3 \
  make \
  g++ \
  pkg-config

echo "==> Installing SQLite tooling..."
apt-get install -y --no-install-recommends \
  sqlite3

echo "==> Installing audio + playback stack..."
# - mpv: player
# - ffmpeg: useful companion; some mpv features require ffmpeg in PATH
# - alsa-utils: alsamixer/aplay etc (Pi HAT testing)
# - libasound2-plugins: ALSA plugins (dmix/softvol/etc) helpful on headless setups
apt-get install -y --no-install-recommends \
  mpv \
  ffmpeg \
  alsa-utils \
  libasound2-plugins

echo "==> Installing Node.js (NodeSource) v${NODE_MAJOR}.x ..."
# NodeSource setup script adds the repo and installs nodejs via apt afterwards.
# This avoids Debian's (often older) node packages.
curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash -
apt-get install -y nodejs

echo "==> Verifying versions..."
echo "Node:   $(node -v)"
echo "NPM:    $(npm -v)"
echo "mpv:    $(mpv --version | head -n 1)"
echo "sqlite: $(sqlite3 --version | head -n 1)"

if [[ "${INSTALL_PM2}" == "1" ]]; then
  echo "==> Installing PM2 globally (optional but recommended for running the API as a service)..."
  npm install -g pm2
  echo "PM2:    $(pm2 -v)"
fi

echo "==> Enabling useful groups (audio) for the invoking user, if available..."
# If script run with sudo, add the original user to audio group for device access.
if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
  usermod -aG audio "${SUDO_USER}" || true
  echo "Added ${SUDO_USER} to 'audio' group (log out/in or reboot to apply)."
fi

echo "==> Done."
echo ""
echo "Next suggested checks:"
echo "  1) aplay -l        # list ALSA devices"
echo "  2) speaker-test -c2 -t wav"
echo "  3) mpv --no-video /path/to/test.flac"
