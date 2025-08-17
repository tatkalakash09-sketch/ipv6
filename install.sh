#!/bin/bash
set -e

echo "[*] Checking and installing dependencies..."
apt update -y
apt install -y curl wget unzip make gcc git build-essential net-tools iproute2

# Install 3proxy
echo "[*] Installing 3proxy..."
mkdir -p /usr/local/etc/3proxy
cd /tmp
rm -rf 3proxy
git clone https://github.com/z3APA3A/3proxy.git
cd 3proxy
make -f Makefile.Linux

echo "[*] Build finished, checking for binary..."
ls -lh src/ || true
ls -lh bin/ || true

# Copy compiled binary (different versions place it differently)
mkdir -p /usr/local/3proxy/bin
if [ -f src/3proxy ]; then
    echo "[*] Found binary in src/, copying..."
    cp src/3proxy /usr/local/3proxy/bin/
elif [ -f bin/3proxy ]; then
    echo "[*] Found binary in bin/, copying..."
    cp bin/3proxy /usr/local/3proxy/bin/
else
    echo "[!] 3proxy binary not found after build!"
    exit 1
fi

# Copy configs if available
cp -r ./cfg/* /usr/local/etc/3proxy/ || true

# Create users file if missing
echo "[*] Setting up users..."
if [ ! -f /usr/local/etc/3proxy/users.lst ]; then
    echo "user:CL:pass" > /usr/local/etc/3proxy/users.lst
fi

# Create proxy rules file if missing
echo "[*] Setting up proxy rules..."
if [ ! -f /usr/local/etc/3proxy/proxy.cfg ]; then
    cat > /usr/local/etc/3proxy/proxy.cfg <<EOF
proxy -p8080
EOF
fi

# Create main 3proxy config
echo "[*] Creating 3proxy config..."
mkdir -p /usr/local/etc/3proxy

cat > /usr/local/etc/3proxy/3proxy.cfg <<EOF
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
daemon

auth strong
users $(cat /usr/local/etc/3proxy/users.lst)

$(cat /usr/local/etc/3proxy/proxy.cfg)
EOF

# Create systemd service
echo "[*] Setting up systemd service..."
cat > /etc/systemd/system/3proxy.service <<EOF
[Unit]
Description=3proxy Proxy Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Enable and start service
systemctl daemon-reload
systemctl enable 3proxy
systemctl restart 3proxy

echo "[*] Installation complete!"
echo "You can edit users in: /usr/local/etc/3proxy/users.lst"
echo "Proxy rules in: /usr/local/etc/3proxy/proxy.cfg"
echo "Main config in: /usr/local/etc/3proxy/3proxy.cfg"
