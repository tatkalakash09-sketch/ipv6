#!/bin/bash
# ===============================
# IPv6 Proxy Uninstaller
# ===============================

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

echo "[*] Removing 3proxy and configs..."
rm -rf /usr/local/etc/3proxy
rm -f /etc/systemd/system/3proxy.service
rm -rf /var/log/3proxy
rm -rf /root/proxy_users.*

wait_for_apt_lock
apt remove -y 3proxy || true
apt autoremove -y

echo "[*] Uninstallation complete!"
