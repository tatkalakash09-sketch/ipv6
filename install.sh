#!/bin/bash
set -e

PORT=8080
PROXY_DIR="/usr/local/etc/3proxy"
CONFIG_FILE="$PROXY_DIR/3proxy.cfg"
PROXY_LIST="/root/proxy_list.txt"
ALL_IPV6="/root/all_ipv6.txt"

echo "[*] Installing dependencies..."
apt update -y
apt install -y build-essential gcc make git curl wget unzip net-tools iproute2

echo "[*] Downloading and building 3proxy..."
rm -rf /tmp/3proxy
cd /tmp
git clone https://github.com/z3APA3A/3proxy.git
cd 3proxy
make -f Makefile.Linux
mkdir -p $PROXY_DIR
cp bin/3proxy $PROXY_DIR/

echo "[*] Creating 3proxy config..."
mkdir -p $PROXY_DIR/logs
cat > $CONFIG_FILE <<EOF
daemon
maxconn 1000
nserver 8.8.8.8
nserver 1.1.1.1
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
auth none
proxy -p$PORT
EOF

echo "[*] Setting up systemd service..."
cat > /etc/systemd/system/3proxy.service <<EOF
[Unit]
Description=3proxy Proxy Server
After=network.target

[Service]
Type=simple
ExecStart=$PROXY_DIR/3proxy $CONFIG_FILE
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl enable 3proxy
systemctl restart 3proxy

echo "[*] Collecting IP addresses..."

# Reset lists
rm -f $PROXY_LIST $ALL_IPV6

# Save IPv4 addresses (excluding localhost, docker)
for ip in $(ip -4 addr show | grep "inet " | awk '{print $2}' | cut -d/ -f1 | grep -v "^127\." | grep -v "^172\.17"); do
    echo "$ip:$PORT" >> $PROXY_LIST
done

# Save IPv6 addresses (excluding local + link-local)
for ip in $(ip -6 addr show | grep "inet6" | awk '{print $2}' | cut -d/ -f1 | grep -v "^::1" | grep -v "^fe80"); do
    echo "[$ip]:$PORT" >> $PROXY_LIST
    echo "$ip" >> $ALL_IPV6
done

echo "✅ Installation complete!"
echo "✅ All active proxies saved at: $PROXY_LIST"
echo "✅ All IPv6 saved at: $ALL_IPV6"
