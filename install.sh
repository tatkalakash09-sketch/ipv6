#!/bin/bash
# ===============================
# IPv6 Proxy Installer with Auto-Rotation
# Compatible: Ubuntu 20-24
# ===============================

set -e

PROXY_COUNT=500
BASE_HTTP_PORT=10000
BASE_SOCKS_PORT=20000
ROTATE_INTERVAL=10  # minutes
THREEPROXY_DIR="/opt/3proxy"
CONFIG_DIR="/usr/local/etc/3proxy"
LOG_FILE="/var/log/3proxy.log"
PROXY_LIST="$CONFIG_DIR/proxy_list.txt"

# Detect network interface
ETH_INTERFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | head -n1)
IPv4_ADDR=$(ip -4 addr show $ETH_INTERFACE | grep inet | awk '{print $2}' | cut -d/ -f1)
IPv6_LIST=($(ip -6 addr show $ETH_INTERFACE | grep inet6 | awk '{print $2}' | cut -d/ -f1 | grep -v ^::1))

if [ ${#IPv6_LIST[@]} -eq 0 ]; then
    echo "[!] No IPv6 addresses detected on $ETH_INTERFACE"
    exit 1
fi

apt update
apt install -y git build-essential psmisc net-tools curl cron

# Install 3proxy
mkdir -p $THREEPROXY_DIR
git clone https://github.com/z3APA3A/3proxy.git $THREEPROXY_DIR
cd $THREEPROXY_DIR
make -f Makefile.Linux
mkdir -p $CONFIG_DIR

# Function to generate proxies
generate_proxies() {
    > $CONFIG_DIR/3proxy.cfg
    cat <<EOL > $CONFIG_DIR/3proxy.cfg
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
log $LOG_FILE D
EOL
    > $PROXY_LIST

    for ((i=0;i<$PROXY_COUNT;i++)); do
        RAND_IP=${IPv6_LIST[$RANDOM % ${#IPv6_LIST[@]}]}
        USER=$(head /dev/urandom | tr -dc a-z0-9 | head -c6)
        PASS=$(head /dev/urandom | tr -dc a-z0-9 | head -c8)
        echo "users $USER:CL:$PASS" >> $CONFIG_DIR/3proxy.cfg

        HTTP_PORT=$((BASE_HTTP_PORT+i))
        SOCKS_PORT=$((BASE_SOCKS_PORT+i))

        # HTTP proxy
        echo "proxy -6 -n -a -i$IPv4_ADDR -e$RAND_IP -p$HTTP_PORT" >> $CONFIG_DIR/3proxy.cfg
        echo "$RAND_IP:$HTTP_PORT:$USER:$PASS" >> $PROXY_LIST

        # SOCKS5 proxy
        echo "socks -6 -n -a -i$IPv4_ADDR -e$RAND_IP -p$SOCKS_PORT" >> $CONFIG_DIR/3proxy.cfg
        echo "$RAND_IP:$SOCKS_PORT:$USER:$PASS" >> $PROXY_LIST
    done
}

# Initial generation
generate_proxies

# Systemd service
cat <<EOL > /etc/systemd/system/3proxy.service
[Unit]
Description=3proxy Proxy Server
After=network.target

[Service]
Type=simple
ExecStart=$THREEPROXY_DIR/src/3proxy $CONFIG_DIR/3proxy.cfg
Restart=on-failure
LimitNOFILE=100000

[Install]
WantedBy=multi-user.target
EOL

systemctl daemon-reload
systemctl enable 3proxy
systemctl start 3proxy

# Rotation script
ROTATE_SCRIPT="$CONFIG_DIR/rotate_proxies.sh"
cat <<'EOF' > $ROTATE_SCRIPT
#!/bin/bash
# Rotate proxy IPs and users without downtime
PROXY_COUNT=500
BASE_HTTP_PORT=10000
BASE_SOCKS_PORT=20000
CONFIG_DIR="/usr/local/etc/3proxy"
THREEPROXY_DIR="/opt/3proxy"
ETH_INTERFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | head -n1)
IPv4_ADDR=$(ip -4 addr show $ETH_INTERFACE | grep inet | awk '{print $2}' | cut -d/ -f1)
IPv6_LIST=($(ip -6 addr show $ETH_INTERFACE | grep inet6 | awk '{print $2}' | cut -d/ -f1 | grep -v ^::1))
PROXY_LIST="$CONFIG_DIR/proxy_list.txt"
LOG_FILE="/var/log/3proxy.log"

> $CONFIG_DIR/3proxy.cfg
cat <<EOL > $CONFIG_DIR/3proxy.cfg
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
log $LOG_FILE D
EOL
> $PROXY_LIST

for ((i=0;i<$PROXY_COUNT;i++)); do
    RAND_IP=${IPv6_LIST[$RANDOM % ${#IPv6_LIST[@]}]}
    USER=$(head /dev/urandom | tr -dc a-z0-9 | head -c6)
    PASS=$(head /dev/urandom | tr -dc a-z0-9 | head -c8)
    echo "users $USER:CL:$PASS" >> $CONFIG_DIR/3proxy.cfg

    HTTP_PORT=$((BASE_HTTP_PORT+i))
    SOCKS_PORT=$((BASE_SOCKS_PORT+i))

    echo "proxy -6 -n -a -i$IPv4_ADDR -e$RAND_IP -p$HTTP_PORT" >> $CONFIG_DIR/3proxy.cfg
    echo "$RAND_IP:$HTTP_PORT:$USER:$PASS" >> $PROXY_LIST

    echo "socks -6 -n -a -i$IPv4_ADDR -e$RAND_IP -p$SOCKS_PORT" >> $CONFIG_DIR/3proxy.cfg
    echo "$RAND_IP:$SOCKS_PORT:$USER:$PASS" >> $PROXY_LIST
done

kill -HUP $(pidof 3proxy)
EOF

chmod +x $ROTATE_SCRIPT

# Cron setup
(crontab -l 2>/dev/null; echo "*/$ROTATE_INTERVAL * * * * $ROTATE_SCRIPT") | crontab -

echo "[*] Setup complete! Proxies will rotate every $ROTATE_INTERVAL minutes."
echo "[*] Proxy list: $PROXY_LIST"
