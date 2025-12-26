#!/usr/bin/env bash
set -euo pipefail

MDNS_NAME="${MDNS_NAME:-nostalgia}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo $0"
  exit 1
fi

echo "==> Install Avahi (mDNS)"
apt-get update -y
apt-get install -y --no-install-recommends avahi-daemon

echo "==> Set hostname to ${MDNS_NAME}"
hostnamectl set-hostname "${MDNS_NAME}"

# Ensure /etc/hosts has a localhost mapping for the hostname (nice hygiene)
if ! grep -qE "127\.0\.1\.1\s+${MDNS_NAME}" /etc/hosts; then
  # Replace existing 127.0.1.1 line if present, else append
  if grep -qE "^127\.0\.1\.1" /etc/hosts; then
    sed -i "s/^127\.0\.1\.1.*/127.0.1.1\t${MDNS_NAME}/" /etc/hosts
  else
    echo -e "127.0.1.1\t${MDNS_NAME}" >> /etc/hosts
  fi
fi

echo "==> Enable and start Avahi"
systemctl enable --now avahi-daemon

echo ""
echo "Done."
echo "You should now be able to access:"
echo "  http://${MDNS_NAME}.local"
echo ""
echo "Note: some clients may need Wi-Fi/LAN mDNS enabled; try reconnecting if it doesn’t resolve."
