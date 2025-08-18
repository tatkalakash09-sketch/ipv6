#!/bin/bash
# ========================================================
# 🛡️ IPv6 Proxy Server with HTTP + SOCKS5 + Rotation
# Author: Temporalitas (Improved & Secured)
# License: MIT
# Features:
#   - HE.net IPv6 tunnel setup
#   - 3proxy with HTTP + SOCKS5 on unique IPv6s
#   - Authentication
#   - Systemd service
#   - Dynamic proxy rotation script
#   - Logging & security
# ⚠️ Use only with authorized IPv6 subnets (VPS or business HE.net)
# ========================================================

set -euo pipefail

# ============= 🔧 USER CONFIGURATION =============
# 📌 Edit these values!
TUNNEL_SERVER="203.0.113.1"           # HE.net Tunnel Server IPv4
YOUR_PUBLIC_IP="198.51.100.1"         # Your server's public IPv4
IPV6_SUBNET="2001:db8::/64"           # Your /64 (e.g., from HE.net)

USERNAME="scraper"
PASSWORD="ChangeThisPassword123!"      # Use strong password

NUM_PROXIES=10                         # Number of proxies to create
HTTP_START_PORT=3128                   # HTTP proxies: 3128, 3129, ...
SOCKS_START_PORT=4128                  # SOCKS5 proxies: 4128, 4129, ...

PROXY_CONF="/etc/3proxy/3proxy.cfg"
PROXY_SERVICE="/etc/systemd/system/3proxy.service"
LOG_DIR="/var/log/3proxy"
RUN_DIR="/var/run/3proxy"

# ============= 🔍 VALIDATION =============
if [[ -z "$TUNNEL_SERVER" || "$TUNNEL_SERVER" == "203.0.113.1" ]]; then
    echo "❌ ERROR: Please set TUNNEL_SERVER to your HE.net server IP."
    exit 1
fi

if [[ -z "$YOUR_PUBLIC_IP" || "$YOUR_PUBLIC_IP" == "198.51.100.1" ]]; then
    echo "❌ ERROR: Please set YOUR_PUBLIC_IP to your server's public IPv4."
    exit 1
fi

if [[ "$EUID" -ne 0 ]]; then
    echo "❌ This script must be run as root (sudo)."
    exit 1
fi

# ============= 📦 INSTALL 3PROXY =============
echo "📦 Installing 3proxy and dependencies..."
apt-get update -qq
apt-get install -y 3proxy openssl iproute2 procps wget

# ============= 📁 CREATE DIRECTORIES =============
echo "📁 Creating log and runtime directories..."
mkdir -p "$LOG_DIR" "$RUN_DIR"
chown -R nobody:nogroup "$LOG_DIR" "$RUN_DIR"
chmod 755 "$LOG_DIR" "$RUN_DIR"

# ============= 🌐 SETUP IPv6 TUNNEL (HE.net) =============
echo "🌐 Configuring IPv6 tunnel via HE.net..."
ip tunnel add he-ipv6 mode sit remote "$TUNNEL_SERVER" local "$YOUR_PUBLIC_IP"
ip link set he-ipv6 up

# Base client IPv6 (first in /64)
BASE_IPV6="${IPV6_SUBNET%/64}"
CLIENT_IPV6="$BASE_IPV6::1"

ip addr add "$CLIENT_IPV6/64" dev he-ipv6
ip route add ::/0 dev he-ipv6

# ============= 🧩 ASSIGN MULTIPLE IPv6 ADDRESSES TO LOOPBACK =============
echo "🔁 Assigning $NUM_PROXIES IPv6 addresses to lo interface..."
for i in $(seq 1 "$NUM_PROXIES"); do
    addr="$BASE_IPV6::$((i + 1))"
    ip addr add "$addr/128" dev lo
done

# ============= ⚙️ GENERATE 3PROXY CONFIG =============
echo "⚙️ Generating 3proxy configuration: $PROXY_CONF"
cat > "$PROXY_CONF" << EOF
#!/bin/3proxy

# Global settings
daemon
maxconn 1000
nserver 8.8.8.8
nserver 8.8.4.4
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
log $LOG_DIR/3proxy.log
logformat "- +_Y+m+d:H:M:S.%z %N %E %U %C %R %O %I %h %u"
pidfile /var/run/3proxy/3proxy.pid

# Authentication
auth strong
users $USERNAME:CL:\$(echo -n "$PASSWORD" | openssl passwd -1 -stdin)
allow $USERNAME

# Proxy services
EOF

# Add HTTP + SOCKS5 proxies
for i in $(seq 0 $((NUM_PROXIES - 1))); do
    http_port=$((HTTP_START_PORT + i))
    socks_port=$((SOCKS_START_PORT + i))
    ipv6_addr="$BASE_IPV6::$((i + 2))"

    cat >> "$PROXY_CONF" << EOF
# HTTP Proxy $i
proxy -6 -n -a -p$http_port -i::$http_port -e$ipv6_addr

# SOCKS5 Proxy $i
socks -6 -n -a -p$socks_port -i::$socks_port -e$ipv6_addr
EOF
done

chmod 644 "$PROXY_CONF"

# ============= 🔄 CREATE SYSTEMD SERVICE =============
echo "🔄 Installing systemd service..."
cat > "$PROXY_SERVICE" << EOF
[Unit]
Description=3Proxy IPv6 Proxy Server (HTTP + SOCKS5)
After=network.target

[Service]
Type=forking
PIDFile=/var/run/3proxy/3proxy.pid
ExecStart=/usr/bin/3proxy /etc/3proxy/3proxy.cfg
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
User=nobody
Group=nogroup
WorkingDirectory=/etc/3proxy
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

# ============= 🧪 TEST CONFIG =============
echo "🧪 Testing 3proxy config..."
if ! /usr/bin/3proxy --dump-config /etc/3proxy/3proxy.cfg > /dev/null 2>&1; then
    echo "❌ 3proxy config test FAILED. Check /etc/3proxy/3proxy.cfg"
    exit 1
fi

# ============= ▶️ START SERVICE =============
systemctl enable 3proxy
systemctl restart 3proxy

# ============= 📜 DYNAMIC ROTATION SCRIPT =============
ROTATE_SCRIPT="/usr/local/bin/get-random-proxy.sh"
cat > "$ROTATE_SCRIPT" << 'EOF'
#!/bin/bash
# get-random-proxy.sh - Returns random HTTP or SOCKS5 proxy
PROXY_TYPE="${1:-http}"
BASE_HTTP=3128
BASE_SOCKS=4128
NUM_PROXIES=10
IPV6_BASE="2001:db8::"
USERNAME="scraper"
PASSWORD="ChangeThisPassword123!"

index=$((RANDOM % NUM_PROXIES))
ipv6="$IPV6_BASE:$((index + 2))"
http_port=$((BASE_HTTP + index))
socks_port=$((BASE_SOCKS + index))

if [[ "$PROXY_TYPE" == "socks5" ]]; then
    echo "socks5://$USERNAME:$PASSWORD@[$ipv6]:$socks_port"
else
    echo "http://$USERNAME:$PASSWORD@[$ipv6]:$http_port"
fi
EOF

# Replace placeholders with real values
sed -i "s|IPV6_BASE=.*|IPV6_BASE=\"${BASE_IPV6}\"|g" "$ROTATE_SCRIPT"
sed -i "s|NUM_PROXIES=.*|NUM_PROXIES=$NUM_PROXIES|g" "$ROTATE_SCRIPT"
sed -i "s|BASE_HTTP=.*|BASE_HTTP=$HTTP_START_PORT|g" "$ROTATE_SCRIPT"
sed -i "s|BASE_SOCKS=.*|BASE_SOCKS=$SOCKS_START_PORT|g" "$ROTATE_SCRIPT"
sed -i "s|USERNAME=.*|USERNAME=\"$USERNAME\"|g" "$ROTATE_SCRIPT"
sed -i "s|PASSWORD=.*|PASSWORD=\"$PASSWORD\"|g" "$ROTATE_SCRIPT"

chmod +x "$ROTATE_SCRIPT"

# ============= 🎉 FINAL MESSAGE =============
echo ""
echo "✅ SUCCESS! IPv6 Proxy Server is LIVE."
echo ""
echo "🔢 $NUM_PROXIES proxies running:"
echo "   HTTP:  ports $HTTP_START_PORT to $((HTTP_START_PORT + NUM_PROXIES - 1))"
echo "   SOCKS5: ports $SOCKS_START_PORT to $((SOCKS_START_PORT + NUM_PROXIES - 1))"
echo ""
echo "🔐 Authentication:"
echo "   User: $USERNAME"
echo "   Pass: $PASSWORD"
echo ""
echo "🔄 Get random proxy:"
echo "   get-random-proxy.sh http     # HTTP proxy"
echo "   get-random-proxy.sh socks5   # SOCKS5 proxy"
echo ""
echo "📁 Logs: tail -f $LOG_DIR/3proxy.log"
echo "📊 Test: curl --proxy \"\$(get-random-proxy.sh http)\" https://api.ipify.org"
echo ""
echo "💡 Tip: Use in Python, Scrapy, Selenium, or bash loops for scraping."
echo "⚠️  Reminder: Only use with authorized IPv6 subnets."
