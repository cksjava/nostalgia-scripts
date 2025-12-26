#!/usr/bin/env bash
set -euo pipefail

# Interactive Wi-Fi setup for Raspberry Pi OS Lite (Trixie/Bookworm+)
# Uses NetworkManager TUI: nmtui

if [[ "${EUID}" -ne 0 ]]; then
  echo "Please run as root: sudo $0"
  exit 1
fi

echo "==> Installing NetworkManager + TUI (nmtui) if needed..."
apt-get update -y
apt-get install -y --no-install-recommends \
  network-manager \
  network-manager-tui \
  rfkill

echo "==> Enabling and starting NetworkManager..."
systemctl enable --now NetworkManager

echo "==> Unblocking Wi-Fi (rfkill), if blocked..."
rfkill unblock wifi || true

echo ""
echo "==> Launching nmtui..."
echo "Tip: Choose 'Activate a connection' (or 'Edit a connection') and select your Wi-Fi SSID."
echo "After connecting, exit nmtui and this script will show status."
echo ""

nmtui || true

echo ""
echo "==> Network status:"
nmcli device status || true
echo ""
echo "==> Active connections:"
nmcli -t -f NAME,TYPE,DEVICE connection show --active || true

echo ""
echo "Done."
echo "If Wi-Fi still doesn’t connect, check:"
echo "  1) Country code / regulatory domain"
echo "  2) rfkill list"
echo "  3) journalctl -u NetworkManager -n 200 --no-pager"
