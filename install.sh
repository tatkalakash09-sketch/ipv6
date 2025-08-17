#!/bin/bash
set -e

echo "[*] Installing dependencies..."
apt-get update -y
apt-get install -y build-essential gcc make git wget curl unzip net-tools iproute2

echo "[*] Installing 3proxy..."
cd /usr/local/src
rm -rf 3proxy
git clone https://github.com/z3APA3A/3proxy.git
cd 3proxy
make -f Makefile.Linux
mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
cp src/3proxy /usr/local/etc/3proxy/bin/

# Detect main interface
IFACE=$(ip route get 1 | awk '{print $5;exit}')
IPV4=$(ip -4 addr show dev $IFACE | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
IPV6_BASE=$(ip -6 addr show dev $IFACE | grep -oP '(?<=inet6\s)[0-9a-f:]+(?=/)' | head -n 1)

if [[ -z "$IPV6_BASE" ]]; then
    echo "No IPv6 address detected on $IFACE. Exiting."
    exit 1
fi

echo "[*] Preparing IPv6 proxies..."
mkdir -p /usr/local/etc/3proxy
PROXY_CFG="/usr/local/etc/3proxy/3proxy.cfg"
USERS="/usr/local/etc/3proxy/users.lst"
OUTPUT="/root/proxy.txt"

rm -f $PROXY_CFG $USERS $OUTPUT

cat > $PROXY_CFG <<EOF
daemon
maxconn 200
nserver 1.1.1.1
nserver 8.8.8.8
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
auth strong
users $(for i in $(seq 1 100); do echo -n "user$i:CL:pass$i "; done)
EOF

# Generate 100 random IPv6 addresses
for i in $(seq 1 100); do
    USER="user$i"
    PASS="pass$i"
    PORT=$((8000 + i))
    IPV6="${IPV6_BASE}$(openssl rand -hex 4):$(openssl rand -hex 4)"

    # Add proxy entry to config
    echo "proxy -n -a -p$PORT -i$IPV4 -e$IPV6" >> $PROXY_CFG

    # Assign IPv6 to interface
    ip -6 addr add $IPV6/64 dev $IFACE || true

    # Save login info
    echo "$IPV4:$PORT:$USER:$PASS" >> $OUTPUT
done

echo "[*] Setting up systemd service..."
cat > /etc/systemd/system/3proxy.service <<EOF
[Unit]
Description=3proxy Proxy Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl enable 3proxy
systemctl restart 3proxy

echo "[*] Installation complete!"
echo "Your proxies are saved in /root/proxy.txt"
