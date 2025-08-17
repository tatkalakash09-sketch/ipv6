#!/bin/bash
# ===============================
# IPv6 Proxy Uninstaller
# ===============================

set -e

wait_for_apt_lock() {
  echo "[*] Checking apt/dpkg lock..."
  while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
        fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || \
        fuser /var/cache/apt/archives/lock >/dev/null 2>&1; do
    echo "   [!] Apt is locked, waiting 5s..."
    sleep 5
  done
}

echo "[*] Stopping 3proxy service..."
systemctl stop 3proxy || true
systemctl disable 3proxy || true
rm -f /etc/systemd/system/3proxy.service
systemctl daemon-reexec

echo "[*] Removing 3proxy files..."
rm -rf /usr/local/etc/3proxy
rm -rf /usr/local/src/3proxy

echo "[*] Removing dependencies..."
wait_for_apt_lock
apt remove -y build-essential make gcc git unzip curl wget net-tools iproute2
apt autoremove -y

echo "[*] Uninstall complete!"
