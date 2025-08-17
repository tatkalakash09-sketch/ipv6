#!/bin/bash
# ===============================
# IPv6 Proxy Installer (3proxy)
# ===============================

set -e

echo "[*] Updating system..."
apt update -y

echo "[*] Installing dependencies..."
apt install -y curl wget git build-essential make gcc net-tools unzip iproute2

echo "[*] Installing 3proxy..."
mkdir -p /etc/3proxy
cd /etc/3proxy
wget -qO- https://github.com/z3APA3A/3proxy/archive/refs/tags/0.9.4.tar.gz | tar -xz
cd 3proxy-0.9.4
make -f Makefile.Linux
cp bin/3proxy /usr/local/bin/

echo "[*] Creating 3proxy config..."
cat > /usr/local/etc/3proxy/3proxy.cfg <<EOF
daemon
maxconn 200
nserver 1.1.1.1
nserver 8.8.8.8
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
users user1:CL:pass1
auth strong
proxy -n -a -p8080 -i0.0.0.0 -e::1
EOF

echo "[*] Setting up systemd service..."
cat > /etc/systemd/system/3proxy.service <<EOF
[Unit]
Description=3proxy Proxy Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl enable 3proxy
systemctl restart 3proxy

echo "[*] Installation complete!"
