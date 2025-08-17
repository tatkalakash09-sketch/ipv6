#!/bin/bash
# ===============================
# IPv6 Proxy Uninstaller (3proxy)
# ===============================

echo "[*] Stopping 3proxy service..."
systemctl stop 3proxy || true
systemctl disable 3proxy || true
rm -f /etc/systemd/system/3proxy.service
systemctl daemon-reexec

echo "[*] Removing 3proxy files..."
rm -rf /usr/local/bin/3proxy
rm -rf /usr/local/etc/3proxy
rm -rf /etc/3proxy

echo "[*] Uninstall complete!"
