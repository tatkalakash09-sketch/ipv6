#!/bin/bash
# ===============================
# IPv6 Proxy Installer for Ubuntu 20–24
# ===============================

# Root check
if [ "$EUID" -ne 0 ]; then
  echo "[!] Please run as root (use: sudo su)"
  exit 1
fi

# Ensure curl or wget is installed
if command -v curl &>/dev/null; then
  DOWNLOADER="curl -sL"
elif command -v wget &>/dev/null; then
  DOWNLOADER="wget -qO-"
else
  echo "[*] Installing curl..."
  apt update -y
  apt install -y curl
  DOWNLOADER="curl -sL"
fi

echo "[*] Updating system..."
apt update -y && apt upgrade -y

echo "[*] Installing dependencies..."
apt install -y build-essential wget curl nano iproute2 net-tools unzip

echo "[*] Installing 3proxy..."
mkdir -p /etc/3proxy
cd /etc/3proxy || exit

# Download & build 3proxy
$DOWNLOADER https://github.com/z3APA3A/3proxy/archive/refs/tags/0.9.4.zip -o 3proxy.zip
unzip -o 3proxy.zip
cd 3proxy-0.9.4
make -f Makefile.Linux
make install

# Create config folder
mkdir -p /usr/local/etc/3proxy
mkdir -p /var/log/3proxy

# Generate random users
echo "[*] Creating proxy users..."
USER_FILE="/usr/local/etc/3proxy/users.lst"
> $USER_FILE
for i in $(seq 1 100); do
  user="user$i"
  pass=$(openssl rand -hex 4)
  echo "$user:CL:$pass" >> $USER_FILE
done

# Detect network interface
IFACE=$(ip route get 8.8.8.8 | awk '{print $5; exit}')
IPV4=$(ip -4 addr show dev $IFACE | grep -oP '(?<=inet\s)\d+(\.\d+){3}')

echo "[*] Using interface: $IFACE"
echo "[*] Detected IPv4: $IPV4"

# Create main 3proxy config
cat <<EOF > /usr/local/etc/3proxy/3proxy.cfg
daemon
maxconn 200
nserver 1.1.1.1
nserver 8.8.8.8
timeouts 1 5 30 60 180 1800 15 60
log /var/log/3proxy/3proxy.log D
auth strong
users $(awk -F: '{print $1":CL:"$3}' $USER_FILE | paste -sd " " -)
allow * * * *
proxy -n -a -p8080 -i$IPV4 -e$IPV4
socks -p1080 -i$IPV4 -e$IPV4
EOF

# Create systemd service
cat <<EOF > /etc/systemd/system/3proxy.service
[Unit]
Description=3proxy Proxy Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Reload and enable
systemctl daemon-reload
systemctl enable 3proxy
systemctl restart 3proxy

echo "[*] Installation complete!"
echo "[*] Proxy users are stored in: $USER_FILE"
echo "[*] HTTP Proxy running on: $IPV4:8080"
echo "[*] SOCKS5 Proxy running on: $IPV4:1080"

# Save uninstall script
cat <<EOF > /usr/local/bin/uninstall_proxy.sh
#!/bin/bash
systemctl stop 3proxy
systemctl disable 3proxy
rm -rf /etc/3proxy /usr/local/etc/3proxy /usr/local/bin/3proxy /var/log/3proxy
rm -f /etc/systemd/system/3proxy.service
systemctl daemon-reload
echo "[*] Proxy uninstalled successfully!"
EOF
chmod +x /usr/local/bin/uninstall_proxy.sh
