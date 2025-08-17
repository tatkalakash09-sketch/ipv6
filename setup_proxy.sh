#!/bin/bash
# ===============================
# Bootstrap Installer for IPv6 Proxy
# ===============================

# Correct raw GitHub URL of install.sh
GITHUB_RAW_URL="https://raw.githubusercontent.com/tatkalakash09-sketch/ipv6/main/install.sh"

echo "[*] Downloading IPv6 proxy installer from GitHub..."
curl -s -O $GITHUB_RAW_URL

# Make it executable
chmod +x install.sh

echo "[*] Running installer..."
sudo ./install.sh

echo "[*] Installation complete!"
