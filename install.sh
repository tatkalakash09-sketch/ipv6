#!/bin/bash
# =========================================
# IPv4/IPv6 HTTP + SOCKS5 Proxy Installer
# Works on Ubuntu 20.04 - 24.04
# =========================================

set -e

echo "[*] Updating system..."
apt update -y && apt upgrade -y

echo "[*] Installing dependencies..."
apt install -y build-essential wget curl git unzip make gcc net-tools

# ===============================
# Install 3proxy
# ===============================
echo "[*] Installing 3proxy..."
cd /usr/local/src
rm -rf 3proxy
git clone https://github.com/z3APA3A/3proxy.git
cd 3proxy
make -f Makefile.Linux

mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
cp src/3proxy /usr/local/etc/3proxy/bin/

# ===============================
# Generate Users
# ===============================
USERS_FILE="/usr/local/etc/3proxy/users.lst"
echo "[*] Generating users..."
rm -f $USERS_FILE

for i in $(seq 1 100); do
    USER="user$i"
    PASS=$(openssl rand -hex 4)
    echo "$USER:$PASS" >> $USERS_FILE
done

# ===============================
# Generate 3proxy Config
# ===============================
CONFIG_FILE="/usr/local/etc/3proxy/3proxy.cfg"
echo "[*] Generating 3proxy config..."
rm -f $CONFIG_FILE

cat <<EOL >> $CONFIG_FILE
daemon
maxconn 200
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535
flush
auth strong
users $(awk -F: '{print $1 " CL " $2}' $USERS_FILE | paste -sd ' ')
EOL

COUNTER=0
while read -r USER_LINE; do
    USER=$(echo "$USER_LINE" | cut -d: -f1)
    PASS=$(echo "$USER_LINE" | cut -d: -f2)
    HTTP_PORT=$((8081 + COUNTER))
    SOCKS_PORT=$((1081 + COUNTER))

    cat <<EOL >> $CONFIG_FILE
allow $USER
proxy -n -a -p$HTTP_PORT -i0.0.0.0 -e::0
socks -p$SOCKS_PORT -i0.0.0.0 -e::0
flush
EOL

    COUNTER=$((COUNTER + 1))
done < $USERS_FILE

# ===============================
# Systemd Service
# ===============================
SERVICE_FILE="/etc/systemd/system/3proxy.service"
echo "[*] Creating systemd service..."
cat <<EOL > $SERVICE_FILE
[Unit]
Description=3proxy Proxy Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg
Restart=always

[Install]
WantedBy=multi-user.target
EOL

systemctl daemon-reload
systemctl enable 3proxy
systemctl restart 3proxy

# ===============================
# Export Proxy List
# ===============================
PROXY_TXT="/root/proxy_list.txt"
PROXY_CSV="/root/proxy_list.csv"
PROXY_JSON="/root/proxy_list.json"

echo "[*] Exporting proxy list..."
> "$PROXY_TXT"
echo "protocol,ip,port,username,password" > "$PROXY_CSV"
echo "[" > "$PROXY_JSON"

SERVER_IPv4=$(hostname -I | awk '{print $1}')
SERVER_IPv6=$(ip -6 addr show scope global | grep inet6 | awk '{print $2}' | cut -d/ -f1 | head -n 1)

COUNTER=0
while read -r USER_LINE; do
    USER=$(echo "$USER_LINE" | cut -d: -f1)
    PASS=$(echo "$USER_LINE" | cut -d: -f2)
    HTTP_PORT=$((8081 + COUNTER))
    SOCKS_PORT=$((1081 + COUNTER))

    # IPv4
    echo "http://$SERVER_IPv4:$HTTP_PORT:$USER:$PASS" >> "$PROXY_TXT"
    echo "socks5://$SERVER_IPv4:$SOCKS_PORT:$USER:$PASS" >> "$PROXY_TXT"

    echo "http,$SERVER_IPv4,$HTTP_PORT,$USER,$PASS" >> "$PROXY_CSV"
    echo "socks5,$SERVER_IPv4,$SOCKS_PORT,$USER,$PASS" >> "$PROXY_CSV"

    echo "  {\"protocol\":\"http\",\"ip\":\"$SERVER_IPv4\",\"port\":\"$HTTP_PORT\",\"user\":\"$USER\",\"pass\":\"$PASS\"}," >> "$PROXY_JSON"
    echo "  {\"protocol\":\"socks5\",\"ip\":\"$SERVER_IPv4\",\"port\":\"$SOCKS_PORT\",\"user\":\"$USER\",\"pass\":\"$PASS\"}," >> "$PROXY_JSON"

    # IPv6
    if [ -n "$SERVER_IPv6" ]; then
        echo "http://[$SERVER_IPv6]:$HTTP_PORT:$USER:$PASS" >> "$PROXY_TXT"
        echo "socks5://[$SERVER_IPv6]:$SOCKS_PORT:$USER:$PASS" >> "$PROXY_TXT"

        echo "http,[$SERVER_IPv6],$HTTP_PORT,$USER,$PASS" >> "$PROXY_CSV"
        echo "socks5,[$SERVER_IPv6],$SOCKS_PORT,$USER,$PASS" >> "$PROXY_CSV"

        echo "  {\"protocol\":\"http\",\"ip\":\"$SERVER_IPv6\",\"port\":\"$HTTP_PORT\",\"user\":\"$USER\",\"pass\":\"$PASS\"}," >> "$PROXY_JSON"
        echo "  {\"protocol\":\"socks5\",\"ip\":\"$SERVER_IPv6\",\"port\":\"$SOCKS_PORT\",\"user\":\"$USER\",\"pass\":\"$PASS\"}," >> "$PROXY_JSON"
    fi

    COUNTER=$((COUNTER + 1))
done < $USERS_FILE

# Clean JSON
sed -i '$ s/},/}/' "$PROXY_JSON"
echo "]" >> "$PROXY_JSON"

echo "[*] Installation complete!"
echo "Proxies saved to:"
echo "  $PROXY_TXT"
echo "  $PROXY_CSV"
echo "  $PROXY_JSON"
