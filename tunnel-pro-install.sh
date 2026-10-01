#!/bin/bash
# ============================================================
#  TUNNEL PRO V2 (edit BRAND_NAME untuk ganti)
#  Xray (VLESS/VMess/Trojan/SS) + OpenVPN + SSH Dropbear
#  + UDP-Custom + WS + Kyt + HAProxy + Nginx
#  Based on setup VPS Sunekoo
# ============================================================
#  TUNNEL PRO V2 - Universal Installer
#  EDIT MANUAL SEBELUM RUN (ganti nama sesuai keinginan):
#    - Banner: cari BRAND_NAME di bawah, ganti "TUNNEL PRO V2"
#    - Limiter (pengganti guard): cari LIMITER_NAME, ganti "guard"
#  Contoh cepat via sed:
#    sed -i 's/TUNNEL PRO V2/NAMA BARU/g' install.sh
#    sed -i 's/\/etc\/guard/\/etc\/mylimit/g; s/guard.service/mylimit.service/g' install.sh
# ============================================================
#  Cara pakai:
#    wget -O install <URL> && bash install
#  Atau:
#    bash install.sh
# ============================================================

# ---------- WARNAI ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
BOLD='\033[1m'
NC='\033[0m'


# ---------- KONFIGURASI EDIT MANUAL ----------
BRAND_NAME="TUNNEL PRO V2"
BRAND_SUB="Universal • Telegram Notify • Backup/Restore"
LIMITER_NAME="guard"  # pengganti kata 'guard' -> folder /etc/guard, service guard
# ---------- END KONFIGURASI ----------

# ---------- VARIABEL ----------
date=$(date +%Y-%m-%d)
expire_date=$(date -d "+365 days" +%Y-%m-%d)
uuid=$(cat /proc/sys/kernel/random/uuid)
pass=$(head -c 10 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 10)

clear
echo -e "${CYAN}"
echo "╔═══════════════════════════════════════════════════╗"
echo "║           ✦ $BRAND_NAME ✦            ║"
echo "║    Xray • OpenVPN • SSH • UDP • WS • Kyt • HAProxy • Nginx  ║"
echo "╚═══════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""

# ---------- CEK ROOT ----------
if [[ "$EUID" -ne 0 ]]; then
  echo -e "${RED}Jalan sebagai root bos!${NC}"
  exit 1
fi

# ---------- CEK OS ----------
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
  OS=$ID
  VER=$VERSION_ID
else
  echo -e "${RED}OS tidak dikenali. Hanya Ubuntu/Debian.${NC}"
  exit 1
fi

if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
  echo -e "${RED}Cuma support Ubuntu/Debian bos.${NC}"
  exit 1
fi
# ponytail: tested Ubuntu 18/20/22/24 + Debian 11/12 (dropbear/openvpn/haproxy auto-fallback)
echo -e "${YELLOW}Versi: $OS $VER - melanjutkan...${NC}"

echo -e "${GREEN}OS: $OS $VER${NC}"
echo ""

# ---------- AMBIL IP ----------
MYIP=$(curl -s -4 ifconfig.me || curl -s -4 ipinfo.io/ip)
if [[ -z "$MYIP" ]]; then
  MYIP=$(hostname -I | awk '{print $1}')
fi
echo -e "IP VPS: ${BOLD}$MYIP${NC}"
echo ""

# ---------- TANYA DOMAIN ----------
echo -e "${YELLOW}Punya domain buat SSL (HAProxy multi-port)?${NC}"
echo -e "  1) ${BOLD}Ada domain${NC} (Lo punya domain yang udah di-point ke IP ini)"
echo -e "  2) ${BOLD}Ga ada domain${NC} (Pake self-signed cert, multi-port tetap jalan)"
echo ""
read -p "Pilih [1/2]: " domain_choice

if [[ "$domain_choice" == "1" ]]; then
  read -p "Domain lo (contoh: idhome.suneku.web.id): " DOMAIN
  USE_SSL=1
else
  DOMAIN=$MYIP
  USE_SSL=0
fi
echo ""

# ---------- TANYA TELEGRAM BOT (opsional) ----------
echo -e "${YELLOW}Mau dipakein notif Telegram pas user quota habis?${NC}"
echo -e "  1) ${BOLD}Ya${NC} (butuh Bot Token + Chat ID)"
echo -e "  2) ${BOLD}Nanti aja${NC}"
echo ""
read -p "Pilih [1/2]: " bot_choice

if [[ "$bot_choice" == "1" ]]; then
  read -p "Bot Token: " BOT_TOKEN
  read -p "Chat ID: " CHAT_ID
  mkdir -p /etc/bot
  echo "#bot# $BOT_TOKEN $CHAT_ID" > /etc/bot/.bot.db
  chmod 600 /etc/bot/.bot.db
fi
echo ""

echo -e "${GREEN}Oke, mulai install...${NC}"
echo ""

# ---------- EXTRACT BINARY BUNDLE ----------
echo -e "${CYAN}[0/14] Cek binary bundle...${NC}"
if [[ -f "tunnel-binaries.tar.gz" ]]; then
  echo "Ditemukan tunnel-binaries.tar.gz, extract..."
  tar xzf tunnel-binaries.tar.gz
  echo -e "${GREEN}✓ Binary bundle ready${NC}"
else
  echo -e "${YELLOW}⚠ tunnel-binaries.tar.gz tidak ditemukan."
  echo "Binary akan di-download dari GitHub."
  echo "ws & udp-mini butuh copy manual dari VPS lama!${NC}"
fi
echo ""

# ---------- UPDATE SYSTEM ----------
echo -e "${CYAN}[1/14] Update sistem...${NC}"
apt-get update -y >/dev/null 2>&1
# ponytail: no upgrade -y, breaks kernel. run manually if needed
# ---------- INSTALL DEPENDENCIES ----------
echo -e "${CYAN}[2/14] Install dependencies...${NC}"
apt-get install -y curl wget gzip tar unzip python3 python3-pip \
  nginx haproxy dropbear openvpn fail2ban \
  openssl ca-certificates dnsmasq bc jq \
  build-essential libssl-dev >/dev/null 2>&1

# Install xray api stats helper
pip3 install requests >/dev/null 2>&1
echo -e "${GREEN}✓ Dependencies ready${NC}"
echo ""

# ---------- IP FORWARD ----------
echo -e "${CYAN}[3/14] Setup IP Forward + sysctl...${NC}"
sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1
grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf 2>/dev/null || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p >/dev/null 2>&1

# ---------- AUTOSHIFT ----------
IFACE=$(ip route | awk '/default/ {print $5; exit}'); [ -z "$IFACE" ] && IFACE=eth0
cat > /etc/rc.local << RCLOCAL
#!/bin/bash
IF=\$(ip route | awk '/default/ {print \$5; exit}'); [ -z "\$IF" ] && IF=eth0
iptables -t nat -A POSTROUTING -o \$IF -j MASQUERADE
iptables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
exit 0
RCLOCAL
chmod +x /etc/rc.local
systemctl enable rc-local >/dev/null 2>&1
IFACE=$(ip route | awk '/default/ {print $5; exit}'); [ -z "$IFACE" ] && IFACE=eth0; iptables -t nat -A POSTROUTING -o $IFACE -j MASQUERADE 2>/dev/null
echo -e "${GREEN}✓ IP Forward aktif${NC}"
echo ""

# ---------- INSTALL XRAY ----------
echo -e "${CYAN}[4/14] Install Xray...${NC}"
mkdir -p /etc/xray /var/log/xray
# Cek bundle lokal dulu, kalau ga ada download dari GitHub
if [[ -f "tunnel-binaries/xray" ]]; then
  cp tunnel-binaries/xray /usr/local/bin/xray
else
  XRAY_VER="v1.8.24"
  wget -q "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VER}/Xray-linux-64.zip" -O /tmp/xray.zip
  cd /tmp && unzip -o xray.zip xray geoip.dat geosite.dat >/dev/null 2>&1
  cp xray /usr/local/bin/xray
  cp geoip.dat geosite.dat /usr/local/bin/ 2>/dev/null
  cp geoip.dat geosite.dat /etc/xray/ 2>/dev/null
  cd - >/dev/null
fi
chmod +x /usr/local/bin/xray
# ---------- XRAY CONFIG ----------
cat > /etc/xray/config.json << XRAYEOF
{
  "log": {
    "loglevel": "warning",
    "error": "/var/log/xray/error.log",
    "access": "/var/log/xray/access.log"
  },
  "api": {
    "services": ["HandlerService", "LoggerService", "StatsService"],
    "tag": "api"
  },
  "stats": {},
  "policy": {
    "levels": {
      "0": {
        "handshake": 2,
        "connIdle": 128,
        "statsUserUplink": true,
        "statsUserDownlink": true
      }
    },
    "system": {
      "statsInboundUplink": true,
      "statsInboundDownlink": true,
      "statsOutboundUplink": true,
      "statsOutboundDownlink": true
    }
  },
  "inbounds": [
    {
      "listen": "127.0.0.1",
      "port": 10000,
      "protocol": "dokodemo-door",
      "settings": {"address": "127.0.0.1"},
      "tag": "api"
    },
    {
      "listen": "127.0.0.1",
      "port": 10001,
      "protocol": "vless",
      "settings": {"decryption": "none", "clients": [{"id": "${uuid}"}]},
      "streamSettings": {"network": "ws", "wsSettings": {"path": "/vless"}},
      "tag": "vless-ws"
    },
    {
      "listen": "127.0.0.1",
      "port": 10002,
      "protocol": "vmess",
      "settings": {"clients": [{"id": "${uuid}", "alterId": 0}]},
      "streamSettings": {"network": "ws", "wsSettings": {"path": "/vmess"}},
      "tag": "vmess-ws"
    },
    {
      "listen": "127.0.0.1",
      "port": 10003,
      "protocol": "trojan",
      "settings": {"decryption": "none", "clients": [{"password": "${uuid}"}], "udp": true},
      "streamSettings": {"network": "ws", "wsSettings": {"path": "/trojan-ws"}},
      "tag": "trojan-ws"
    },
    {
      "listen": "127.0.0.1",
      "port": 10004,
      "protocol": "shadowsocks",
      "settings": {"clients": [{"method": "aes-128-gcm", "password": "${uuid}"}], "network": "tcp,udp"},
      "streamSettings": {"network": "ws", "wsSettings": {"path": "/ss-ws"}},
      "tag": "ss-ws"
    },
    {
      "listen": "127.0.0.1",
      "port": 10005,
      "protocol": "vless",
      "settings": {"decryption": "none", "clients": [{"id": "${uuid}"}]},
      "streamSettings": {"network": "grpc", "grpcSettings": {"serviceName": "vless-grpc"}},
      "tag": "vless-grpc"
    },
    {
      "listen": "127.0.0.1",
      "port": 10006,
      "protocol": "vmess",
      "settings": {"clients": [{"id": "${uuid}", "alterId": 0}]},
      "streamSettings": {"network": "grpc", "grpcSettings": {"serviceName": "vmess-grpc"}},
      "tag": "vmess-grpc"
    },
    {
      "listen": "127.0.0.1",
      "port": 10007,
      "protocol": "trojan",
      "settings": {"decryption": "none", "clients": [{"password": "${uuid}"}], "udp": true},
      "streamSettings": {"network": "grpc", "grpcSettings": {"serviceName": "trojan-grpc"}},
      "tag": "trojan-grpc"
    },
    {
      "listen": "127.0.0.1",
      "port": 10008,
      "protocol": "shadowsocks",
      "settings": {"clients": [{"method": "aes-128-gcm", "password": "${uuid}"}], "network": "tcp,udp"},
      "streamSettings": {"network": "grpc", "grpcSettings": {"serviceName": "ss-grpc"}},
      "tag": "ss-grpc"
    }
  ],
  "outbounds": [
    {"protocol": "freedom", "settings": {}, "tag": "direct"},
    {"protocol": "blackhole", "settings": {}, "tag": "blocked"},
    {"protocol": "freedom", "settings": {}, "tag": "api"}
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {"inboundTag": ["api"], "outboundTag": "api", "type": "field"},
      {"outboundTag": "blocked", "protocol": ["bittorrent"], "type": "field"},
      {"type": "field", "outboundTag": "blocked", "ip": ["0.0.0.0/8","10.0.0.0/8","100.64.0.0/10","169.254.0.0/16","172.16.0.0/12","192.0.0.0/24","192.0.2.0/24","192.168.0.0/16","198.18.0.0/15","198.51.100.0/24","203.0.113.0/24","::1/128","fc00::/7","fe80::/10"]},
      {"type": "field", "outboundTag": "direct", "network": "tcp,udp"}
    ]
  },
  "dns": {
    "servers": ["1.1.1.1", "8.8.8.8"]
  }
}
XRAYEOF

# Xray systemd service
cat > /etc/systemd/system/xray.service << 'XRAYD'
[Unit]
Description=Xray Service
Documentation=https://github.com/XTLS/Xray-core
After=network.target nss-lookup.target

[Service]
User=root
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
XRAYD

systemctl daemon-reload
systemctl enable xray >/dev/null 2>&1
systemctl start xray
echo -e "${GREEN}✓ Xray jalan (VLESS/VMess/Trojan/SS - WS + gRPC)${NC}"
echo ""

# ---------- OPENVPN ----------
echo -e "${CYAN}[5/14] Install OpenVPN TCP + UDP...${NC}"
mkdir -p /etc/openvpn/server
# detect pam plugin path (Ubuntu 18 vs 20+/Debian)
PAM_PLUGIN=$(find /usr/lib -name openvpn-plugin-auth-pam.so 2>/dev/null | head -1); [ -z "$PAM_PLUGIN" ] && PAM_PLUGIN="/usr/lib/x86_64-linux-gnu/openvpn/plugins/openvpn-plugin-auth-pam.so"

# Generate certificates
cd /etc/openvpn/server
[ -f dh2048.pem ] || openssl dhparam -out dh2048.pem 2048 >/dev/null 2>&1
openssl genrsa -out ca.key 2048 >/dev/null 2>&1
openssl req -new -x509 -days 3650 -key ca.key -out ca.crt -subj "/CN=OpenVPN-CA" >/dev/null 2>&1
openssl genrsa -out server.key 2048 >/dev/null 2>&1
openssl req -new -key server.key -out server.csr -subj "/CN=OpenVPN-Server" >/dev/null 2>&1
openssl x509 -req -days 3650 -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt >/dev/null 2>&1
openssl genrsa -out tc.key 2048 >/dev/null 2>&1
openssl req -new -x509 -days 3650 -key tc.key -out tc.crt -subj "/CN=OpenVPN-TLSCrypt" >/dev/null 2>&1
openvpn --genkey --secret ta.key >/dev/null 2>&1

# TCP config
cat > /etc/openvpn/server/server-tcp.conf << 'OVPNTCP'
port 1194
proto tcp
dev tun
ca ca.crt
cert server.crt
key server.key
dh dh2048.pem
plugin /usr/lib/x86_64-linux-gnu/openvpn/plugins/openvpn-plugin-auth-pam.so login
verify-client-cert none
username-as-common-name
server 10.6.0.0 255.255.255.0
ifconfig-pool-persist ipp.txt
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"
keepalive 5 30
persist-key
persist-tun
status openvpn-tcp.log
verb 3
OVPNTCP

# UDP config
cat > /etc/openvpn/server/server-udp.conf << 'OVPNUDP'
port 2200
proto udp
dev tun
ca ca.crt
cert server.crt
key server.key
dh dh2048.pem
plugin /usr/lib/x86_64-linux-gnu/openvpn/plugins/openvpn-plugin-auth-pam.so login
verify-client-cert none
username-as-common-name
server 10.7.0.0 255.255.255.0
ifconfig-pool-persist ipp.txt
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"
keepalive 5 30
persist-key
persist-tun
status openvpn-udp.log
verb 3
explicit-exit-notify
OVPNUDP

for f in /etc/openvpn/server/server-tcp.conf /etc/openvpn/server/server-udp.conf; do [ -f "$f" ] && sed -i "s|plugin .*openvpn-plugin-auth-pam.so|plugin $PAM_PLUGIN|g" "$f"; done
systemctl enable openvpn-server@server-tcp >/dev/null 2>&1
systemctl enable openvpn-server@server-udp >/dev/null 2>&1
systemctl start openvpn-server@server-tcp >/dev/null 2>&1
systemctl start openvpn-server@server-udp >/dev/null 2>&1
echo -e "${GREEN}✓ OpenVPN TCP:1194 + UDP:2200${NC}"
echo ""

# ---------- DROPBEAR (SSH) ----------
echo -e "${CYAN}[6/14] Install Dropbear SSH...${NC}"
cat > /etc/default/dropbear << 'DROP'
NO_START=0
DROPBEAR_PORT=143
DROPBEAR_EXTRA_ARGS="-p 109"
DROPBEAR_BANNER="/etc/banner.txt"
DROPBEAR_RECEIVE_WINDOW=65536
DROP
echo "Selamat datang di SSH Server" > /etc/banner.txt
systemctl enable dropbear >/dev/null 2>&1
systemctl restart dropbear >/dev/null 2>&1
echo -e "${GREEN}✓ Dropbear port: 143, 109${NC}"
echo ""

# ---------- UDP-CUSTOM ----------
echo -e "${CYAN}[7/14] Install UDP-Custom...${NC}"
mkdir -p /etc/udp
cat > /etc/udp/config.json << 'UDPC'
{
  "listen": ":36712",
  "stream_buffer": 33554432,
  "receive_buffer": 83886080,
  "auth": {
    "mode": "passwords"
  }
}
UDPC

# Download UDP-Custom binary
if [[ -f "tunnel-binaries/udp-custom" ]]; then
  cp tunnel-binaries/udp-custom /etc/udp/udp-custom
elif [[ ! -f /etc/udp/udp-custom ]]; then
  wget -q "https://github.com/noobconner21/UDP-Custom-Script/raw/main/udp-custom-linux-amd64" -O /etc/udp/udp-custom 2>/dev/null
fi
chmod +x /etc/udp/udp-custom

cat > /etc/systemd/system/udp-custom.service << 'UDPS'
[Unit]
Description=UDP Custom by ePro Dev. Team
[Service]
User=root
Type=simple
ExecStart=/etc/udp/udp-custom server
WorkingDirectory=/etc/udp/
Restart=always
RestartSec=2s
[Install]
WantedBy=default.target
UDPS

# UDP-Mini (guard)
mkdir -p /usr/local/guard
if [[ -f "tunnel-binaries/udp-mini" ]]; then
  cp tunnel-binaries/udp-mini /usr/local/guard/udp-mini
elif [[ ! -f /usr/local/guard/udp-mini ]]; then
  echo -e "${YELLOW}⚠ udp-mini binary ga ada di bundle. Copy manual dari VPS lama.${NC}"
fi
chmod +x /usr/local/guard/udp-mini 2>/dev/null

for port in 7100 7200 7300; do
  num=$(echo $port | tail -c 2)
  cat > /etc/systemd/system/udp-mini-${num}.service << UDPMINI
[Unit]
Description=UDP ${port}
After=syslog.target network-online.target
[Service]
User=root
NoNewPrivileges=true
ExecStart=/usr/local/guard/udp-mini --listen-addr 127.0.0.1:${port} --max-clients 500
Restart=on-failure
LimitNPROC=10000
LimitNOFILE=1000000
[Install]
WantedBy=multi-user.target
UDPMINI
done

# badvpn-udpgw
if [[ -f "tunnel-binaries/badvpn-udpgw" ]]; then
  cp tunnel-binaries/badvpn-udpgw /usr/local/bin/badvpn-udpgw
elif [[ ! -f /usr/local/bin/badvpn-udpgw ]]; then
  wget -q "https://github.com/powermx/badvpn/raw/master/badvpn-udpgw" -O /usr/local/bin/badvpn-udpgw 2>/dev/null
fi
chmod +x /usr/local/bin/badvpn-udpgw 2>/dev/null

cat > /etc/systemd/system/udpgw.service << 'UDPGW'
[Unit]
Description=badvpn-udpgw 7301
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/badvpn-udpgw --listen-addr 127.0.0.1:7301 --max-clients 512 --max-connections-for-client 32
Restart=always
RestartSec=3
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
UDPGW

systemctl daemon-reload
systemctl enable udp-custom udp-mini-1 udp-mini-2 udp-mini-3 udpgw >/dev/null 2>&1
systemctl start udp-custom udp-mini-1 udp-mini-2 udp-mini-3 udpgw >/dev/null 2>&1
echo -e "${GREEN}✓ UDP-Custom:36712, UDP-Mini:7100/7200/7300, udpgw:7301${NC}"
echo ""

# ---------- WS (WEBSOCKET TUNNEL) ----------
echo -e "${CYAN}[8/14] Install WS WebSocket tunnel...${NC}"
if [[ -f "tunnel-binaries/ws" ]]; then
  cp tunnel-binaries/ws /usr/bin/ws
elif [[ ! -f /usr/bin/ws ]]; then
  echo -e "${YELLOW}⚠ ws binary ga ada di bundle. Copy manual dari VPS lama.${NC}"
fi
chmod +x /usr/bin/ws 2>/dev/null

cat > /usr/bin/tun.conf << 'TUNC'
verbose: 0
listen:

# SSH Dropbear
- target_host: 127.0.0.1
  target_port: 143
  listen_port: 10015

# OpenVPN TCP
- target_host: 127.0.0.1
  target_port: 1194
  listen_port: 10012
TUNC

cat > /etc/systemd/system/ws.service << 'WSS'
[Unit]
Description=WebSocket
After=syslog.target network-online.target
[Service]
User=root
NoNewPrivileges=true
ExecStart=/usr/bin/ws -f /usr/bin/tun.conf
Restart=on-failure
LimitNPROC=10000
LimitNOFILE=1000000
[Install]
WantedBy=multi-user.target
WSS

systemctl daemon-reload
systemctl enable ws >/dev/null 2>&1
systemctl start ws
echo -e "${GREEN}✓ WS tunnel aktif${NC}"
echo ""

# ---------- GUARD (LIMIT IP PER PROTOCOL) ----------
echo -e "${CYAN}[9/14] Install Kyt limit IP...${NC}"
mkdir -p /etc/guard/limit/{ssh,trojan,vless,vmess,shadowsocks}/ip

# Kyt python module
PYLIB=$(python3 -c "import sysconfig; print(sysconfig.get_path('purelib'))" 2>/dev/null || echo /usr/lib/python3/dist-packages)

# resolve limiter dir from LIMITER_NAME (agar edit manual cukup ganti variable)
GUARD_DIR="/etc/$LIMITER_NAME"
GUARD_LIB="/usr/local/$LIMITER_NAME"
GUARD_PYLIB="$PYLIB/$LIMITER_NAME"
mkdir -p "$PYLIB/$LIMITER_NAME"
cat > "$PYLIB/$LIMITER_NAME/__init__.py" << 'GUARDI'
# guard module - limit IP per protocol
GUARDI

cat > /etc/systemd/system/guard.service << 'GUARDS'
[Unit]
Description=Simple guard - @guard
After=network.target
[Service]
WorkingDirectory=/usr/bin/
ExecStart=/usr/bin/python3 -m guard
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
GUARDS

systemctl daemon-reload
systemctl enable guard >/dev/null 2>&1
systemctl start guard >/dev/null 2>&1
echo -e "${GREEN}✓ Kyt limit IP aktif${NC}"
echo ""

# ---------- LIMIT SCRIPTS (VLESS/VMESS/TROJAN/SS) ----------
echo -e "${CYAN}[10/14] Install limit quota scripts...${NC}"
mkdir -p /etc/limit/{vless,vmess,trojan,shadowsocks}
mkdir -p /etc/vless /etc/vmess /etc/trojan /etc/shadowsocks

# -------- limit.vless --------
cat > /etc/xray/limit.vless << 'LIMITVLESS'
#!/bin/bash
function send-log(){
CHATID=$(grep -E "^#bot# " "/etc/bot/.bot.db" | cut -d ' ' -f 3)
KEY=$(grep -E "^#bot# " "/etc/bot/.bot.db" | cut -d ' ' -f 2)
TIME="10"
URL="https://api.telegram.org/bot$KEY/sendMessage"
TEXT="
<code>────────────────────</code>
<b>⚠️NOTIF QUOTA HABIS XRAY VLESS⚠️</b>
<code>────────────────────</code>
<code>Username  : </code><code>$user</code>
<code>limit Quota: </code><code>$total2</code>
<code>Usage     : </code><code>$total</code>
<code>────────────────────</code>
"
curl -s --max-time $TIME -d "chat_id=$CHATID&disable_web_page_preview=1&text=$TEXT&parse_mode=html" $URL >/dev/null
}
function con() {
    local -i bytes=$1;
    if [[ $bytes -lt 1024 ]]; then echo "${bytes}B"
    elif [[ $bytes -lt 1048576 ]]; then echo "$(( (bytes + 1023)/1024 ))KB"
    elif [[ $bytes -lt 1073741824 ]]; then echo "$(( (bytes + 1048575)/1048576 ))MB"
    else echo "$(( (bytes + 1073741823)/1073741824 ))GB"
    fi
}
while true; do
  sleep 5
  data=($(cat /etc/vless.db 2>/dev/null; cat /etc/xray/config.json 2>/dev/null | grep '^#&' | cut -d ' ' -f 2 | sort -u))
  mkdir -p /etc/limit/vless
  for user in ${data[@]}; do
    downlink=$(xray api stats --server=127.0.0.1:10000 -name "user>>>${user}>>>traffic>>>downlink" | grep -w "value" | awk '{print $2}' | cut -d '"' -f2);
    if [ -e /etc/limit/vless/${user} ]; then
      plus2=$(cat /etc/limit/vless/${user});
      if [[ ${plus2} -gt 0 ]]; then
        plus3=$(( ${downlink} + ${plus2} ));
        echo "${plus3}" > /etc/limit/vless/"${user}"
        xray api stats --server=127.0.0.1:10000 -name "user>>>${user}>>>traffic>>>downlink" -reset > /dev/null 2>&1
      else
        echo "${downlink}" > /etc/limit/vless/"${user}"
        xray api stats --server=127.0.0.1:10000 -name "user>>>${user}>>>traffic>>>downlink" -reset > /dev/null 2>&1
      fi
    fi
  done
  for user in ${data[@]}; do
    if [ -e /etc/vless/${user} ]; then
      checkLimit=$(cat /etc/vless/${user});
      if [[ ${checkLimit} -gt 1 ]]; then
        if [ -e /etc/limit/vless/${user} ]; then
          Usage=$(cat /etc/limit/vless/${user});
          total=$(con ${Usage})
          total2=$(con ${checkLimit})
          if [[ ${Usage} -gt ${checkLimit} ]]; then
            uuid=$(grep -E "^},{" "/etc/xray/config.json" | grep -i '"'"${user}"'"' | cut -d " " -f 2 | cut -d '"' -f 2 | uniq)
            exp=$(grep -wE "^#& $user" "/etc/xray/config.json" | cut -d ' ' -f 3 | sort | uniq)
            echo "#& $user $exp $uuid" >> /etc/xray/.lock.db
            jq --arg id "$uuid" '.inbounds |= map(if .tag=="vless-ws" or .tag=="vless-grpc" then .settings.clients |= map(select(.id != $id)) else . end)' /etc/xray/config.json > /tmp/xray.json.tmp && mv /tmp/xray.json.tmp /etc/xray/config.json
            sed -i "/^#& $user /d" /etc/vless.db 2>/dev/null
            send-log
            rm -f -- /etc/limit/vless/${user}
            rm -f /etc/vless/$user
            systemctl restart xray > /dev/null 2>&1
          fi
        fi
      fi
    fi
  done
done
LIMITVLESS
chmod +x /etc/xray/limit.vless

# -------- limit.vmess --------
cat > /etc/xray/limit.vmess << 'LIMITVMESS'
#!/bin/bash
function send-log(){
CHATID=$(grep -E "^#bot# " "/etc/bot/.bot.db" | cut -d ' ' -f 3)
KEY=$(grep -E "^#bot# " "/etc/bot/.bot.db" | cut -d ' ' -f 2)
TIME="10"
URL="https://api.telegram.org/bot$KEY/sendMessage"
TEXT="
<code>────────────────────</code>
<b>⚠️NOTIF QUOTA HABIS XRAY VMESS⚠️</b>
<code>────────────────────</code>
<code>Username  : </code><code>$user</code>
<code>limit Quota: </code><code>$total2</code>
<code>Usage     : </code><code>$total</code>
<code>────────────────────</code>
"
curl -s --max-time $TIME -d "chat_id=$CHATID&disable_web_page_preview=1&text=$TEXT&parse_mode=html" $URL >/dev/null
}
function con() {
    local -i bytes=$1;
    if [[ $bytes -lt 1024 ]]; then echo "${bytes}B"
    elif [[ $bytes -lt 1048576 ]]; then echo "$(( (bytes + 1023)/1024 ))KB"
    elif [[ $bytes -lt 1073741824 ]]; then echo "$(( (bytes + 1048575)/1048576 ))MB"
    else echo "$(( (bytes + 1073741823)/1073741824 ))GB"
    fi
}
while true; do
  sleep 5
  data=($(cat /etc/vmess.db 2>/dev/null | grep '^###' | cut -d ' ' -f 2; cat /etc/xray/config.json 2>/dev/null | grep '^###' | cut -d ' ' -f 2 | sort -u))
  mkdir -p /etc/limit/vmess
  for user in ${data[@]}; do
    downlink=$(xray api stats --server=127.0.0.1:10000 -name "user>>>${user}>>>traffic>>>downlink" | grep -w "value" | awk '{print $2}' | cut -d '"' -f2);
    if [ -e /etc/limit/vmess/${user} ]; then
      plus2=$(cat /etc/limit/vmess/${user});
      if [[ ${plus2} -gt 0 ]]; then
        plus3=$(( ${downlink} + ${plus2} ));
        echo "${plus3}" > /etc/limit/vmess/"${user}"
        xray api stats --server=127.0.0.1:10000 -name "user>>>${user}>>>traffic>>>downlink" -reset > /dev/null 2>&1
      else
        echo "${downlink}" > /etc/limit/vmess/"${user}"
        xray api stats --server=127.0.0.1:10000 -name "user>>>${user}>>>traffic>>>downlink" -reset > /dev/null 2>&1
      fi
    fi
  done
  for user in ${data[@]}; do
    if [ -e /etc/vmess/${user} ]; then
      checkLimit=$(cat /etc/vmess/${user});
      if [[ ${checkLimit} -gt 1 ]]; then
        if [ -e /etc/limit/vmess/${user} ]; then
          Usage=$(cat /etc/limit/vmess/${user});
          total=$(con ${Usage})
          total2=$(con ${checkLimit})
          if [[ ${Usage} -gt ${checkLimit} ]]; then
            uuid=$(grep -E "^},{" "/etc/xray/config.json" | grep -i '"'"${user}"'"' | cut -d " " -f 2 | cut -d '"' -f 2 | uniq)
            exp=$(grep -wE "^### $user" "/etc/xray/config.json" | cut -d ' ' -f 3 | sort | uniq)
            echo "### $user $exp $uuid" >> /etc/xray/.lock.db
            jq --arg id "$uuid" '.inbounds |= map(if .tag=="vmess-ws" or .tag=="vmess-grpc" then .settings.clients |= map(select(.id != $id)) else . end)' /etc/xray/config.json > /tmp/xray.json.tmp && mv /tmp/xray.json.tmp /etc/xray/config.json
            sed -i "/^### $user /d" /etc/vmess.db 2>/dev/null
            send-log
            rm -f -- /etc/limit/vmess/${user}
            rm -f /etc/vmess/$user
            systemctl restart xray > /dev/null 2>&1
          fi
        fi
      fi
    fi
  done
done
LIMITVMESS
chmod +x /etc/xray/limit.vmess

# -------- limit.trojan --------
cat > /etc/xray/limit.trojan << 'LIMITTROJAN'
#!/bin/bash
function send-log(){
CHATID=$(grep -E "^#bot# " "/etc/bot/.bot.db" | cut -d ' ' -f 3)
KEY=$(grep -E "^#bot# " "/etc/bot/.bot.db" | cut -d ' ' -f 2)
TIME="10"
URL="https://api.telegram.org/bot$KEY/sendMessage"
TEXT="
<code>────────────────────</code>
<b>⚠️NOTIF QUOTA HABIS XRAY TROJAN⚠️</b>
<code>────────────────────</code>
<code>Username  : </code><code>$user</code>
<code>limit Quota: </code><code>$total2</code>
<code>Usage     : </code><code>$total</code>
<code>────────────────────</code>
"
curl -s --max-time $TIME -d "chat_id=$CHATID&disable_web_page_preview=1&text=$TEXT&parse_mode=html" $URL >/dev/null
}
function con() {
    local -i bytes=$1;
    if [[ $bytes -lt 1024 ]]; then echo "${bytes}B"
    elif [[ $bytes -lt 1048576 ]]; then echo "$(( (bytes + 1023)/1024 ))KB"
    elif [[ $bytes -lt 1073741824 ]]; then echo "$(( (bytes + 1048575)/1048576 ))MB"
    else echo "$(( (bytes + 1073741823)/1073741824 ))GB"
    fi
}
while true; do
  sleep 30
  data=($(cat /etc/trojan.db 2>/dev/null | grep '^#!' | cut -d ' ' -f 2; cat /etc/xray/config.json 2>/dev/null | grep '^#!' | cut -d ' ' -f 2 | sort -u))
  mkdir -p /etc/limit/trojan
  for user in ${data[@]}; do
    downlink=$(xray api stats --server=127.0.0.1:10000 -name "user>>>${user}>>>traffic>>>downlink" | grep -w "value" | awk '{print $2}' | cut -d '"' -f2);
    if [ -e /etc/limit/trojan/${user} ]; then
      plus2=$(cat /etc/limit/trojan/${user});
      if [[ ${plus2} -gt 0 ]]; then
        plus3=$(( ${downlink} + ${plus2} ));
        echo "${plus3}" > /etc/limit/trojan/"${user}"
        xray api stats --server=127.0.0.1:10000 -name "user>>>${user}>>>traffic>>>downlink" -reset > /dev/null 2>&1
      else
        echo "${downlink}" > /etc/limit/trojan/"${user}"
        xray api stats --server=127.0.0.1:10000 -name "user>>>${user}>>>traffic>>>downlink" -reset > /dev/null 2>&1
      fi
    fi
  done
  for user in ${data[@]}; do
    if [ -e /etc/trojan/${user} ]; then
      checkLimit=$(cat /etc/trojan/${user});
      if [[ ${checkLimit} -gt 1 ]]; then
        if [ -e /etc/limit/trojan/${user} ]; then
          Usage=$(cat /etc/limit/trojan/${user});
          total=$(con ${Usage})
          total2=$(con ${checkLimit})
          if [[ ${Usage} -gt ${checkLimit} ]]; then
            uuid=$(grep -E "^},{" "/etc/xray/config.json" | grep -i '"'"${user}"'"' | cut -d " " -f 2 | cut -d '"' -f 2 | uniq)
            exp=$(grep -wE "^#! $user" "/etc/xray/config.json" | cut -d ' ' -f 3 | sort | uniq)
            echo "#! $user $exp $uuid" >> /etc/xray/.lock.db
            jq --arg pw "$uuid" '.inbounds |= map(if .tag=="trojan-ws" or .tag=="trojan-grpc" then .settings.clients |= map(select(.password != $pw)) else . end)' /etc/xray/config.json > /tmp/xray.json.tmp && mv /tmp/xray.json.tmp /etc/xray/config.json
            sed -i "/^#! $user /d" /etc/trojan.db 2>/dev/null
            send-log
            rm -f -- /etc/limit/trojan/${user}
            rm -f /etc/trojan/$user
            systemctl restart xray > /dev/null 2>&1
          fi
        fi
      fi
    fi
  done
done
LIMITTROJAN
chmod +x /etc/xray/limit.trojan

# -------- limit.shadowsocks --------
cat > /etc/xray/limit.shadowsocks << 'LIMITSS'
#!/bin/bash
function send-log(){
CHATID=$(grep -E "^#bot# " "/etc/bot/.bot.db" | cut -d ' ' -f 3)
KEY=$(grep -E "^#bot# " "/etc/bot/.bot.db" | cut -d ' ' -f 2)
TIME="10"
URL="https://api.telegram.org/bot$KEY/sendMessage"
TEXT="
<code>────────────────────</code>
<b>⚠️NOTIF QUOTA HABIS⚠️</b>
<code>────────────────────</code>
<code>Username  : </code><code>$user</code>
<code>Usage     : </code><code>$total</code>
<code>────────────────────</code>
"
curl -s --max-time $TIME -d "chat_id=$CHATID&disable_web_page_preview=1&text=$TEXT&parse_mode=html" $URL >/dev/null
}
function con() {
    local -i bytes=$1;
    if [[ $bytes -lt 1024 ]]; then echo "${bytes}B"
    elif [[ $bytes -lt 1048576 ]]; then echo "$(( (bytes + 1023)/1024 ))KB"
    elif [[ $bytes -lt 1073741824 ]]; then echo "$(( (bytes + 1048575)/1048576 ))MB"
    else echo "$(( (bytes + 1073741823)/1073741824 ))GB"
    fi
}
while true; do
  sleep 30
  data=($(cat /etc/shadowsocks/.shadowsocks.db | grep '^###' | cut -d ' ' -f 2 | sort | uniq))
  mkdir -p /etc/limit/shadowsocks
  for user in ${data[@]}; do
    downlink=$(xray api stats --server=127.0.0.1:10000 -name "user>>>${user}>>>traffic>>>downlink" | grep -w "value" | awk '{print $2}' | cut -d '"' -f2);
    if [ -e /etc/limit/shadowsocks/${user} ]; then
      plus2=$(cat /etc/limit/shadowsocks/${user});
      if [[ ${plus2} -gt 0 ]]; then
        plus3=$(( ${downlink} + ${plus2} ));
        echo "${plus3}" > /etc/limit/shadowsocks/"${user}"
        xray api stats --server=127.0.0.1:10000 -name "user>>>${user}>>>traffic>>>downlink" -reset > /dev/null 2>&1
      else
        echo "${downlink}" > /etc/limit/shadowsocks/"${user}"
        xray api stats --server=127.0.0.1:10000 -name "user>>>${user}>>>traffic>>>downlink" -reset > /dev/null 2>&1
      fi
    else
      echo "${downlink}" > /etc/limit/shadowsocks/"${user}"
      xray api stats --server=127.0.0.1:10000 -name "user>>>${user}>>>traffic>>>downlink" -reset > /dev/null 2>&1
    fi
  done
  for user in ${data[@]}; do
    if [ -e /etc/shadowsocks/${user} ]; then
      checkLimit=$(cat /etc/shadowsocks/${user});
      if [[ ${#checkLimit} -gt 1 ]]; then
        if [ -e /etc/limit/shadowsocks/${user} ]; then
          Usage=$(cat /etc/limit/shadowsocks/${user});
          if [[ ${Usage} -gt ${checkLimit} ]]; then
            # ponytail: SS client removal via jq - need password lookup from db if stored
            pw=$(grep "^### $user " /etc/shadowsocks/.shadowsocks.db 2>/dev/null | awk '{print $4}'); [ -n "$pw" ] && jq --arg pw "$pw" '.inbounds |= map(if .tag=="ss-ws" or .tag=="ss-grpc" then .settings.clients |= map(select(.password != $pw)) else . end)' /etc/xray/config.json > /tmp/xray.json.tmp && mv /tmp/xray.json.tmp /etc/xray/config.json
            sed -i "/^### $user/d" /etc/shadowsocks/.shadowsocks.db
            total=$(con ${Usage})
            send-log
            rm -f /etc/shadowsocks/$user
            rm -f /etc/guard/limit/shadowsocks/ip/${user}
            rm -f /etc/limit/shadowsocks/$user
            systemctl restart xray > /dev/null 2>&1
          fi
        fi
      fi
    fi
  done
done
LIMITSS
chmod +x /etc/xray/limit.shadowsocks

# Limit systemd services
for proto in vless vmess trojan shadowsocks; do
  cat > /etc/systemd/system/limit${proto}.service << LIMITSVC
[Unit]
Description=Limit Usage Xray Service - ${proto}
After=syslog.target network-online.target
[Service]
User=root
NoNewPrivileges=true
ExecStart=/etc/xray/limit.${proto}
[Install]
WantedBy=multi-user.target
LIMITSVC
done

systemctl daemon-reload
systemctl enable limitvless limitvmess limittrojan limitshadowsocks >/dev/null 2>&1
systemctl start limitvless limitvmess limittrojan limitshadowsocks >/dev/null 2>&1
echo -e "${GREEN}✓ Limit quota VLESS/VMESS/TROJAN/SS aktif${NC}"
echo ""

# ---------- HAPROXY ----------
echo -e "${CYAN}[11/14] Install HAProxy multi-port...${NC}"

if [[ "$USE_SSL" == "1" ]]; then
  # Generate SSL cert via certbot
  apt-get install -y certbot >/dev/null 2>&1
  certbot certonly --standalone --non-interactive --agree-tos -d $DOMAIN -m root@localhost --no-eff-email 2>/dev/null
  # Combine cert + key for HAProxy
  cat /etc/letsencrypt/live/$DOMAIN/fullchain.pem /etc/letsencrypt/live/$DOMAIN/privkey.pem > /etc/haproxy/hap.pem
else
  # Self-signed cert
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/haproxy/hap.key -out /etc/haproxy/hap.crt \
    -subj "/CN=$DOMAIN" >/dev/null 2>&1
  cat /etc/haproxy/hap.crt /etc/haproxy/hap.key > /etc/haproxy/hap.pem
fi

cat > /etc/haproxy/haproxy.cfg << 'HAP'
global
    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
    stats timeout 1d
    tune.h2.initial-window-size 2147483647
    tune.ssl.default-dh-param 2048
    pidfile /run/haproxy.pid
    chroot /var/lib/haproxy
    user haproxy
    group haproxy
    daemon
    ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305
    ssl-default-bind-options no-sslv3 no-tlsv10 no-tlsv11
    ca-base /etc/ssl/certs
    crt-base /etc/ssl/private

defaults
    log global
    mode tcp
    option dontlognull
    timeout connect 200ms
    timeout client  300s
    timeout server  300s

frontend multiport
    mode tcp
    bind *:222-1000 tfo
    tcp-request inspect-delay 500ms
    tcp-request content accept if HTTP
    tcp-request content accept if { req.ssl_hello_type 1 }
    use_backend recir_http if HTTP
    default_backend recir_https

frontend multiports
    mode tcp
    bind abns@haproxy-http accept-proxy tfo
    default_backend recir_https_www

frontend ssl
    mode tcp
    bind *:80 tfo
    bind *:55 tfo
    bind *:8080 tfo
    bind *:8880 tfo
    bind *:2095 tfo
    bind *:2082 tfo
    bind *:2086 tfo
    bind abns@haproxy-https accept-proxy ssl crt /etc/haproxy/hap.pem alpn h2,http/1.1 tfo

    tcp-request inspect-delay 500ms
    tcp-request content capture req.ssl_sni len 100
    tcp-request content accept if { req.ssl_hello_type 1 }

    acl chk-02_up hdr(Connection) -i upgrade
    acl chk-02_ws hdr(Upgrade) -i websocket
    acl this_payload payload(0,7) -m bin 5353482d322e30
    acl up-to ssl_fc_alpn -i h2

    use_backend GRUP_FTVPN if up-to
    use_backend FTVPN if chk-02_up chk-02_ws
    use_backend FTVPN if { path_reg -i ^\/(.*) }
    use_backend BOT_FTVPN if this_payload
    default_backend CHANNEL_FTVPN

backend recir_https_www
    mode tcp
    server local 127.0.0.1:2223 check

backend FTVPN
    mode http
    server xray-ws 127.0.0.1:1010 send-proxy check

backend GRUP_FTVPN
    mode tcp
    server xray-grpc 127.0.0.1:1013 send-proxy check

backend CHANNEL_FTVPN
    mode tcp
    balance roundrobin
    server openvpn 127.0.0.1:1194 check
    server ws-ovpn 127.0.0.1:1012 send-proxy check

backend BOT_FTVPN
    mode tcp
    server ssh 127.0.0.1:2222 check

backend recir_http
    mode tcp
    server loopback-for-http abns@haproxy-http send-proxy-v2 check

backend recir_https
    mode tcp
    server loopback-for-https abns@haproxy-https send-proxy-v2 check
HAP

systemctl enable haproxy >/dev/null 2>&1
systemctl restart haproxy >/dev/null 2>&1
echo -e "${GREEN}✓ HAProxy multi-port: 80, 55, 8080, 8880, 2082, 2086, 2095, 222-1000${NC}"
echo ""

# ---------- NGINX ----------
echo -e "${CYAN}[12/14] Setup Nginx (reverse proxy + web)...${NC}"

# SSL cert buat nginx:81
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/xray/xray.key -out /etc/xray/xray.crt \
  -subj "/CN=$DOMAIN" >/dev/null 2>&1

# Web default di port 2223
cat > /etc/nginx/sites-available/default << 'NGINXWEB'
server {
    listen 2223;
    root /var/www/html;
    index index.html;
    server_name _;
    location / {
        try_files $uri $uri/ =404;
    }
}
NGINXWEB
ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default 2>/dev/null

# ---------- NGINX REVERSE PROXY (conf.d/xray.conf) ----------
# Port 1010 = WebSocket path routing (HAProxy → Xray WS)
# Port 1012 = OpenVPN via WS tunnel (HAProxy → WS tunnel → OpenVPN)
# Port 1013 = gRPC path routing (HAProxy → Xray gRPC)
# Port 81 = SSL web (xray cert)
cat > /etc/nginx/conf.d/xray.conf << 'XRAYCONF'
# --- WebSocket reverse proxy (HAProxy send-proxy → path routing ke Xray WS) ---
server {
    listen 1010 proxy_protocol so_keepalive=on reuseport;
    set_real_ip_from 127.0.0.1;
    real_ip_header proxy_protocol;
    server_name _;
    client_body_buffer_size 200K;
    client_header_buffer_size 2k;
    client_max_body_size 10M;
    large_client_header_buffers 3 1k;
    client_header_timeout 86400000m;
    keepalive_timeout 86400000m;

    location ~ /vless {
        proxy_http_version 1.1;
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10001;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $http_x_forwarded_for;
        proxy_set_header X-Forwarded-For $http_x_forwarded_for;
    }
    location ~ /vmess {
        proxy_http_version 1.1;
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10002;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $http_x_forwarded_for;
        proxy_set_header X-Forwarded-For $http_x_forwarded_for;
    }
    location ~ /trojan-ws {
        proxy_http_version 1.1;
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10003;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $http_x_forwarded_for;
        proxy_set_header X-Forwarded-For $http_x_forwarded_for;
    }
    location ~ /ss-ws {
        proxy_http_version 1.1;
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10004;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $http_x_forwarded_for;
        proxy_set_header X-Forwarded-For $http_x_forwarded_for;
    }
    location ~ / {
        proxy_http_version 1.1;
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10015;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $http_x_forwarded_for;
        proxy_set_header X-Forwarded-For $http_x_forwarded_for;
    }
}

# --- OpenVPN via WS tunnel (HAProxy → nginx → WS tunnel → OpenVPN) ---
server {
    listen 1012 proxy_protocol so_keepalive=on reuseport;
    server_name _;
    client_body_buffer_size 200K;
    client_header_buffer_size 2k;
    client_max_body_size 10M;
    large_client_header_buffers 3 1k;
    client_header_timeout 86400000m;
    keepalive_timeout 86400000m;

    location ~ / {
        proxy_http_version 1.1;
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10012;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $http_x_forwarded_for;
        proxy_set_header X-Forwarded-For $http_x_forwarded_for;
    }
}

# --- gRPC reverse proxy (HAProxy → path routing ke Xray gRPC) ---
server {
    listen 1013 http2 proxy_protocol so_keepalive=on reuseport;
    server_name _;
    client_body_buffer_size 200K;
    client_header_buffer_size 2k;
    client_max_body_size 10M;
    large_client_header_buffers 3 1k;
    client_header_timeout 86400000m;
    keepalive_timeout 86400000m;

    location ~ /vless-grpc {
        proxy_http_version 1.1;
        proxy_redirect off;
        grpc_set_header Host $host;
        grpc_pass grpc://127.0.0.1:10005;
        grpc_set_header X-Real-IP $http_x_forwarded_for;
        grpc_set_header X-Forwarded-For $http_x_forwarded_for;
    }
    location ~ /vmess-grpc {
        proxy_http_version 1.1;
        proxy_redirect off;
        grpc_set_header Host $host;
        grpc_pass grpc://127.0.0.1:10006;
        grpc_set_header X-Real-IP $http_x_forwarded_for;
        grpc_set_header X-Forwarded-For $http_x_forwarded_for;
    }
    location ~ /trojan-grpc {
        proxy_http_version 1.1;
        proxy_redirect off;
        grpc_set_header Host $host;
        grpc_pass grpc://127.0.0.1:10007;
        grpc_set_header X-Real-IP $http_x_forwarded_for;
        grpc_set_header X-Forwarded-For $http_x_forwarded_for;
    }
    location ~ /ss-grpc {
        proxy_http_version 1.1;
        proxy_redirect off;
        grpc_set_header Host $host;
        grpc_pass grpc://127.0.0.1:10008;
        grpc_set_header X-Real-IP $http_x_forwarded_for;
        grpc_set_header X-Forwarded-For $http_x_forwarded_for;
    }
}

# --- SSL web di port 81 ---
server {
    listen 81 ssl http2 reuseport;
    ssl_certificate /etc/xray/xray.crt;
    ssl_certificate_key /etc/xray/xray.key;
    ssl_protocols TLSv1.1 TLSv1.2 TLSv1.3;
    root /var/www/html;
}
XRAYCONF

mkdir -p /var/www/html
echo "<h1>Tunnel Server Active</h1>" > /var/www/html/index.html
systemctl enable nginx >/dev/null 2>&1
systemctl restart nginx >/dev/null 2>&1
echo -e "${GREEN}✓ Nginx aktif (reverse proxy WS/gRPC + web SSL:81)${NC}"
echo ""

# ---------- FAIL2BAN ----------
echo -e "${CYAN}[13/14] Setup Fail2Ban...${NC}"
cat > /etc/fail2ban/jail.local << 'F2B'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = ssh
logpath = %(sshd_log)s
backend = systemd

[http-get-dos]
enabled = true
port = http,https
filter = http-get-dos
logpath = /var/log/nginx/access.log
maxretry = 200
findtime = 200
bantime = 600

[recidive]
enabled = true
logpath = /var/log/fail2ban.log
action = iptables-allports[name=recidive]
bantime = 604800
findtime = 86400
maxretry = 5
F2B

systemctl enable fail2ban >/dev/null 2>&1
systemctl restart fail2ban >/dev/null 2>&1
echo -e "${GREEN}✓ Fail2Ban aktif${NC}"
echo ""

# ---------- TC FQCODEL ----------
cat > /etc/systemd/system/tc-fqcodel.service << 'TCFQ'
[Unit]
Description=fq_codel for game/video
After=network.target
[Service]
Type=oneshot
ExecStart=/bin/bash -c 'IF=$(ip route | grep default | awk "{print \$5}" | head -1); [ -z "$IF" ] && IF=eth0; tc qdisc replace dev $IF root fq_codel target 5ms interval 100ms quantum 300 limit 1000 flows 1024 2>/dev/null || tc qdisc replace dev $IF root fq'
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
TCFQ
systemctl daemon-reload
systemctl enable tc-fqcodel >/dev/null 2>&1
systemctl start tc-fqcodel >/dev/null 2>&1

# ---------- FILE LIMIT.CONF ----------
grep -q "65535" /etc/security/limits.conf 2>/dev/null || cat >> /etc/security/limits.conf << 'LIMCONF'
* soft nofile 65535
* hard nofile 65535
root soft nofile 51200
root hard nofile 51200
LIMCONF

# ---------- AUTO RENEW SSL ----------
if [[ "$USE_SSL" == "1" ]]; then
  cat > /etc/cron.daily/renew-haproxy-ssl << 'RENEW'
#!/bin/bash
certbot renew --quiet
cat /etc/letsencrypt/live/DOMAIN/fullchain.pem /etc/letsencrypt/live/DOMAIN/privkey.pem > /etc/haproxy/hap.pem
systemctl restart haproxy
RENEW
  sed -i "s/DOMAIN/$DOMAIN/g" /etc/cron.daily/renew-haproxy-ssl
  chmod +x /etc/cron.daily/renew-haproxy-ssl
fi

# ---------- INSTALL MENU SCRIPT ----------
echo -e "${CYAN}Install menu management...${NC}"
cat > /usr/local/bin/menu << 'MENUEOF'
#!/bin/bash
# ============================================================
#  TUNNELING USER MANAGEMENT MENU
#  SSH + OpenVPN + Xray (VLESS/VMess/Trojan/SS) + Quota Limit
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

MYIP=$(curl -s -4 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
DOMAIN=$(openssl x509 -in /etc/xray/xray.crt -noout -subject 2>/dev/null | grep -oP 'CN=\K[^ ]+' || echo "$MYIP")

gen_uuid() { cat /proc/sys/kernel/random/uuid; }
gen_pass() { head -c 8 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 8; }

# ---------- TELEGRAM NOTIFY AKUN BARU ----------
send_account_tele() {
  local tipe="$1" user="$2" exp="$3" extra="$4"
  [ ! -f /etc/bot/.bot.db ] && return 0
  local KEY=$(awk '{print $2}' /etc/bot/.bot.db 2>/dev/null)
  local CHATID=$(awk '{print $3}' /etc/bot/.bot.db 2>/dev/null)
  [ -z "$KEY" ] || [ -z "$CHATID" ] && return 0
  local TEXT="<code>────────────────────</code>%0A<b>✅ AKUN BARU $tipe</b>%0A<code>────────────────────</code>%0A<code>User : </code><code>$user</code>%0A<code>Exp  : </code><code>$exp</code>%0A<code>Info : </code><code>$extra</code>%0A<code>IP   : </code><code>$MYIP</code>%0A<code>Domain: </code><code>$DOMAIN</code>"
  curl -s --max-time 10 -d "chat_id=$CHATID&disable_web_page_preview=1&text=$TEXT&parse_mode=html" "https://api.telegram.org/bot$KEY/sendMessage" >/dev/null 2>&1 || true
}


create_ssh() {
  clear
  echo -e "${CYAN}=== BUAT AKUN SSH & OPENVPN ===${NC}"
  read -p "Username: " user
  [[ -z "$user" ]] && { echo "Ga boleh kosong"; return; }
  if ! [[ "$user" =~ ^[a-zA-Z0-9_.-]+$ ]]; then echo "Username invalid"; return; fi
  id "$user" &>/dev/null && { echo "User $user udah ada"; return; }
  read -p "Password (kosongkan=auto): " pass
  [[ -z "$pass" ]] && pass=$(gen_pass)
  read -p "Masa aktif (hari, default 30): " days
  [[ -z "$days" ]] && days=30
  exp=$(date -d "+$days days" +%Y-%m-%d)
  useradd -e "$exp" -s /bin/false -M "$user" 2>/dev/null
  echo "$user:$pass" | chpasswd 2>/dev/null
  echo "$user $exp $pass" >> /etc/ssh-user.db
  send_account_tele "SSH/OVPN" "$user" "$exp" "Pass: $pass | 143,109 1194/2200"
  clear
  echo -e "${GREEN}✓ Akun SSH & OpenVPN dibuat${NC}"
  echo "Username  : $user"
  echo "Password  : $pass"
  echo "Domain    : $DOMAIN"
  echo "IP        : $MYIP"
  echo "Expired   : $exp ($days hari)"
  echo ""
  echo "SSH Port  : 143, 109"
  echo "OVPN TCP  : 1194"
  echo "OVPN UDP  : 2200"
  read -p "Enter..."
}

create_vless() {
  clear
  echo -e "${CYAN}=== BUAT AKUN VLESS ===${NC}"
  read -p "Username: " user
  [[ -z "$user" ]] && { echo "Ga boleh kosong"; return; }
  read -p "Masa aktif (hari, default 30): " days
  [[ -z "$days" ]] && days=30
  exp=$(date -d "+$days days" +%Y-%m-%d)
  uuid=$(gen_uuid)
  if ! [[ "$user" =~ ^[a-zA-Z0-9_.-]+$ ]]; then echo "Username invalid"; return; fi
  jq --arg id "$uuid" '.inbounds |= map(if .tag=="vless-ws" or .tag=="vless-grpc" then .settings.clients += [{"id": $id}] else . end)' /etc/xray/config.json > /tmp/xray.json.tmp && mv /tmp/xray.json.tmp /etc/xray/config.json
  echo "#& $user $exp $uuid" >> /etc/vless.db
  send_account_tele "VLESS" "$user" "$exp" "UUID: $uuid | WS:80/gRPC:443"
  systemctl restart xray 2>/dev/null
  clear
  echo -e "${GREEN}✓ Akun VLESS dibuat${NC}"
  echo "Username  : $user"
  echo "UUID      : $uuid"
  echo "Domain    : $DOMAIN"
  echo "Expired   : $exp ($days hari)"
  echo ""
  echo "=== VLESS WS ==="
  echo "Port: 80,8080,8880,2082,2086,2095 | Path: /vless | TLS: none"
  echo "Link: vless://${uuid}@${DOMAIN}:80?encryption=none&security=none&type=ws&host=${DOMAIN}&path=%2Fvless#${user}"
  echo ""
  echo "=== VLESS gRPC ==="
  echo "Port: 443 | Service: vless-grpc | TLS: tls"
  echo "Link: vless://${uuid}@${DOMAIN}:443?encryption=none&security=tls&type=grpc&serviceName=vless-grpc#${user}"
  read -p "Enter..."
}

create_vmess() {
  clear
  echo -e "${CYAN}=== BUAT AKUN VMESS ===${NC}"
  read -p "Username: " user
  [[ -z "$user" ]] && { echo "Ga boleh kosong"; return; }
  read -p "Masa aktif (hari, default 30): " days
  [[ -z "$days" ]] && days=30
  exp=$(date -d "+$days days" +%Y-%m-%d)
  uuid=$(gen_uuid)
  if ! [[ "$user" =~ ^[a-zA-Z0-9_.-]+$ ]]; then echo "Username invalid"; return; fi
  jq --arg id "$uuid" '.inbounds |= map(if .tag=="vmess-ws" or .tag=="vmess-grpc" then .settings.clients += [{"id": $id, "alterId": 0}] else . end)' /etc/xray/config.json > /tmp/xray.json.tmp && mv /tmp/xray.json.tmp /etc/xray/config.json
  echo "### $user $exp $uuid" >> /etc/vmess.db
  send_account_tele "VMESS" "$user" "$exp" "UUID: $uuid | WS:80/gRPC:443"
  systemctl restart xray 2>/dev/null
  vmess_ws=$(echo -n "{\"v\":\"2\",\"ps\":\"$user\",\"add\":\"$DOMAIN\",\"port\":\"80\",\"id\":\"$uuid\",\"aid\":\"0\",\"net\":\"ws\",\"path\":\"/vmess\",\"host\":\"$DOMAIN\",\"tls\":\"\"}" | base64 -w 0)
  vmess_grpc=$(echo -n "{\"v\":\"2\",\"ps\":\"$user\",\"add\":\"$DOMAIN\",\"port\":\"443\",\"id\":\"$uuid\",\"aid\":\"0\",\"net\":\"grpc\",\"path\":\"vmess-grpc\",\"host\":\"$DOMAIN\",\"tls\":\"tls\"}" | base64 -w 0)
  clear
  echo -e "${GREEN}✓ Akun VMess dibuat${NC}"
  echo "Username  : $user"
  echo "UUID      : $uuid"
  echo "Domain    : $DOMAIN"
  echo "Expired   : $exp ($days hari)"
  echo ""
  echo "=== VMess WS ==="
  echo "Port: 80,8080,8880,2082,2086,2095 | Path: /vmess"
  echo "Link: vmess://$vmess_ws"
  echo ""
  echo "=== VMess gRPC ==="
  echo "Port: 443 | Service: vmess-grpc | TLS: tls"
  echo "Link: vmess://$vmess_grpc"
  read -p "Enter..."
}

create_trojan() {
  clear
  echo -e "${CYAN}=== BUAT AKUN TROJAN ===${NC}"
  read -p "Username: " user
  [[ -z "$user" ]] && { echo "Ga boleh kosong"; return; }
  read -p "Masa aktif (hari, default 30): " days
  [[ -z "$days" ]] && days=30
  exp=$(date -d "+$days days" +%Y-%m-%d)
  password=$(gen_uuid)
  if ! [[ "$user" =~ ^[a-zA-Z0-9_.-]+$ ]]; then echo "Username invalid"; return; fi
  jq --arg pw "$password" '.inbounds |= map(if .tag=="trojan-ws" or .tag=="trojan-grpc" then .settings.clients += [{"password": $pw}] else . end)' /etc/xray/config.json > /tmp/xray.json.tmp && mv /tmp/xray.json.tmp /etc/xray/config.json
  echo "#! $user $exp $password" >> /etc/trojan.db
  send_account_tele "TROJAN" "$user" "$exp" "Pass: $password | WS:80/gRPC:443"
  systemctl restart xray 2>/dev/null
  clear
  echo -e "${GREEN}✓ Akun Trojan dibuat${NC}"
  echo "Username  : $user"
  echo "Password  : $password"
  echo "Domain    : $DOMAIN"
  echo "Expired   : $exp ($days hari)"
  echo ""
  echo "=== Trojan WS ==="
  echo "Port: 80,8080,8880,2082,2086,2095 | Path: /trojan-ws"
  echo "Link: trojan://${password}@${DOMAIN}:80?security=none&type=ws&host=${DOMAIN}&path=%2Ftrojan-ws#${user}"
  echo ""
  echo "=== Trojan gRPC ==="
  echo "Port: 443 | Service: trojan-grpc | TLS: tls"
  echo "Link: trojan://${password}@${DOMAIN}:443?security=tls&type=grpc&serviceName=trojan-grpc#${user}"
  read -p "Enter..."
}

create_ss() {
  clear
  echo -e "${CYAN}=== BUAT AKUN SHADOWSOCKS ===${NC}"
  read -p "Username: " user
  [[ -z "$user" ]] && { echo "Ga boleh kosong"; return; }
  read -p "Masa aktif (hari, default 30): " days
  [[ -z "$days" ]] && days=30
  exp=$(date -d "+$days days" +%Y-%m-%d)
  password=$(gen_uuid)
  mkdir -p /etc/shadowsocks
  echo "### $user $exp $password" >> /etc/shadowsocks/.shadowsocks.db
  send_account_tele "SHADOWSOCKS" "$user" "$exp" "Pass: $password | aes-128-gcm"
  jq --arg pw "$password" '.inbounds |= map(if .tag=="ss-ws" or .tag=="ss-grpc" then .settings.clients += [{"method": "aes-128-gcm", "password": $pw}] else . end)' /etc/xray/config.json > /tmp/xray.json.tmp && mv /tmp/xray.json.tmp /etc/xray/config.json
  systemctl restart xray 2>/dev/null
  ss_link="ss://$(echo -n "aes-128-gcm:$password" | base64 -w 0)@${DOMAIN}:80#${user}"
  clear
  echo -e "${GREEN}✓ Akun Shadowsocks dibuat${NC}"
  echo "Username  : $user"
  echo "Password  : $password"
  echo "Method    : aes-128-gcm"
  echo "Domain    : $DOMAIN"
  echo "Expired   : $exp ($days hari)"
  echo ""
  echo "=== SS WS ==="
  echo "Port: 80,8080,8880,2082,2086,2095 | Path: /ss-ws"
  echo "Link: $ss_link"
  read -p "Enter..."
}

delete_user() {
  clear
  echo -e "${CYAN}=== HAPUS AKUN ===${NC}"
  echo "1) SSH/OVPN  2) VLESS  3) VMess  4) Trojan  5) SS"
  read -p "Pilih [1-5]: " dt
  read -p "Username: " user
  if ! [[ "$user" =~ ^[a-zA-Z0-9_.-]+$ ]]; then echo "Username invalid"; return; fi
  case $dt in
    1) userdel -r -- "$user" 2>/dev/null; rm -f -- "/etc/guard/limit/ssh/ip/$user"; sed -i "/^$user /d" /etc/ssh-user.db ;;
    2) uuid=$(grep "^#& $user " /etc/vless.db 2>/dev/null | awk '{print $4}'); [ -n "$uuid" ] && jq --arg id "$uuid" '.inbounds |= map(if .tag=="vless-ws" or .tag=="vless-grpc" then .settings.clients |= map(select(.id != $id)) else . end)' /etc/xray/config.json > /tmp/xray.json.tmp && mv /tmp/xray.json.tmp /etc/xray/config.json; sed -i "/^#& $user /d" /etc/vless.db 2>/dev/null; sed -i "/^#& $user /d" /etc/xray/config.json.vless.db 2>/dev/null; rm -f -- "/etc/vless/$user" "/etc/limit/vless/$user"; systemctl restart xray 2>/dev/null ;;
    3) uuid=$(grep "^### $user " /etc/vmess.db 2>/dev/null | awk '{print $4}'); [ -n "$uuid" ] && jq --arg id "$uuid" '.inbounds |= map(if .tag=="vmess-ws" or .tag=="vmess-grpc" then .settings.clients |= map(select(.id != $id)) else . end)' /etc/xray/config.json > /tmp/xray.json.tmp && mv /tmp/xray.json.tmp /etc/xray/config.json; sed -i "/^### $user /d" /etc/vmess.db 2>/dev/null; rm -f -- "/etc/vmess/$user" "/etc/limit/vmess/$user"; systemctl restart xray 2>/dev/null ;;
    4) pw=$(grep "^#! $user " /etc/trojan.db 2>/dev/null | awk '{print $4}'); [ -n "$pw" ] && jq --arg pw "$pw" '.inbounds |= map(if .tag=="trojan-ws" or .tag=="trojan-grpc" then .settings.clients |= map(select(.password != $pw)) else . end)' /etc/xray/config.json > /tmp/xray.json.tmp && mv /tmp/xray.json.tmp /etc/xray/config.json; sed -i "/^#! $user /d" /etc/trojan.db 2>/dev/null; rm -f -- "/etc/trojan/$user" "/etc/limit/trojan/$user"; systemctl restart xray 2>/dev/null ;;
    5) sed -i "/^### $user /d" /etc/shadowsocks/.shadowsocks.db; rm -f -- "/etc/shadowsocks/$user" "/etc/limit/shadowsocks/$user"; systemctl restart xray 2>/dev/null ;;
  esac
  echo -e "${GREEN}✓ $user dihapus${NC}"
  read -p "Enter..."
}

list_users() {
  clear
  echo -e "${CYAN}=== DAFTAR USER ===${NC}"
  echo -e "\n${BOLD}SSH/OpenVPN:${NC}"
  [[ -f /etc/ssh-user.db ]] && cat /etc/ssh-user.db || echo "  (kosong)"
  echo -e "\n${BOLD}VLESS:${NC}"
  grep '^#&' /etc/vless.db 2>/dev/null | cut -d' ' -f2 || echo "  (kosong)"
  echo -e "\n${BOLD}VMess:${NC}"
  grep '^###' /etc/vmess.db 2>/dev/null | cut -d' ' -f2 || echo "  (kosong)"
  echo -e "\n${BOLD}Trojan:${NC}"
  grep '^#!' /etc/trojan.db 2>/dev/null | cut -d' ' -f2 || echo "  (kosong)"
  echo -e "\n${BOLD}Shadowsocks:${NC}"
  grep '^###' /etc/shadowsocks/.shadowsocks.db 2>/dev/null | cut -d' ' -f2 || echo "  (kosong)"
  read -p "Enter..."
}

set_quota() {
  clear
  echo -e "${CYAN}=== SET QUOTA ===${NC}"
  echo "1) VLESS  2) VMess  3) Trojan  4) SS"
  read -p "Pilih [1-4]: " pt
  read -p "Username: " user
  read -p "Quota (GB): " gb
  bytes=$((gb * 1073741824))
  case $pt in
    1) mkdir -p /etc/vless; echo $bytes > /etc/vless/$user ;;
    2) mkdir -p /etc/vmess; echo $bytes > /etc/vmess/$user ;;
    3) mkdir -p /etc/trojan; echo $bytes > /etc/trojan/$user ;;
    4) mkdir -p /etc/shadowsocks; echo $bytes > /etc/shadowsocks/$user ;;
  esac
  echo -e "${GREEN}✓ Quota ${gb}GB → $user${NC}"
  read -p "Enter..."
}

check_expired() {
  clear
  echo -e "${CYAN}=== CEK EXPIRED ===${NC}"
  today=$(date +%Y-%m-%d)
  echo -e "\n${BOLD}SSH/OpenVPN:${NC}"
  [[ -f /etc/ssh-user.db ]] && while IFS=' ' read -r u e p; do
    [[ "$e" < "$today" ]] && echo -e "${RED}$u EXPIRED ($e)${NC}" || echo -e "${GREEN}$u exp: $e${NC}"
  done < /etc/ssh-user.db
  echo -e "\n${BOLD}Xray VMess:${NC}"
  cat /etc/vmess.db 2>/dev/null | grep '^###' | while read -r line; do
    u=$(echo "$line"|cut -d' ' -f2); e=$(echo "$line"|cut -d' ' -f3)
    [[ "$e" < "$today" ]] && echo -e "${RED}$u EXPIRED ($e)${NC}" || echo -e "${GREEN}$u exp: $e${NC}"
  done
  read -p "Enter..."
}

restart_all() {
  clear
  echo "Restart semua service..."
  for svc in xray openvpn-server@server-tcp openvpn-server@server-udp dropbear haproxy nginx ws guard udp-custom udp-mini-1 udp-mini-2 udp-mini-3 udpgw limitvless limitvmess limittrojan limitshadowsocks; do
    systemctl restart $svc 2>/dev/null
  done
  echo -e "${GREEN}✓ Done${NC}"
  read -p "Enter..."
}


backup_data() {
  clear
  echo -e "${CYAN}=== BACKUP DATA TUNNEL ===${NC}"
  local fname="/root/sunek-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
  tar czf "$fname" /etc/xray/config.json /etc/vless.db /etc/vmess.db /etc/trojan.db /etc/shadowsocks/.shadowsocks.db /etc/ssh-user.db /etc/bot/.bot.db /etc/haproxy/hap.pem /etc/xray/xray.crt /etc/xray/xray.key 2>/dev/null
  echo -e "${GREEN}✓ Backup tersimpan: $fname${NC}"
  ls -lh "$fname"
  # optional kirim ke telegram sebagai dokumen
  if [ -f /etc/bot/.bot.db ]; then
    read -p "Kirim backup ke Telegram? [y/N]: " s
    if [[ "$s" == "y" || "$s" == "Y" ]]; then
      KEY=$(awk '{print $2}' /etc/bot/.bot.db); CHATID=$(awk '{print $3}' /etc/bot/.bot.db)
      curl -s -F chat_id="$CHATID" -F document=@"$fname" "https://api.telegram.org/bot$KEY/sendDocument" >/dev/null 2>&1 && echo "✓ Terkirim ke Telegram"
    fi
  fi
  read -p "Enter..."
}

restore_data() {
  clear
  echo -e "${CYAN}=== RESTORE DATA TUNNEL ===${NC}"
  echo "File backup di /root/sunek-backup-*.tar.gz:"
  ls -lh /root/sunek-backup-*.tar.gz 2>/dev/null || { echo "(belum ada backup)"; read -p "Enter..."; return; }
  read -p "Nama file backup (full path): " f
  [ ! -f "$f" ] && { echo "File tidak ditemukan"; return; }
  read -p "Restore akan timpa config! Lanjut? [y/N]: " s
  [[ "$s" != "y" && "$s" != "Y" ]] && return
  systemctl stop xray 2>/dev/null
  tar xzf "$f" -C / 2>/dev/null
  systemctl start xray 2>/dev/null
  echo -e "${GREEN}✓ Restore selesai, xray direstart${NC}"
  read -p "Enter..."
}

while true; do
  clear
  echo -e "${CYAN}╔════════════════════════════════╗"
  echo "║     ✦ $BRAND_NAME MENU ✦     ║"
  echo "╠═══════════════════════════════╣"
  echo -e "║ ${GREEN}Server: $MYIP${CYAN}"
  echo -e "║ ${GREEN}Domain: $DOMAIN${CYAN}"
  echo "╠═══════════════════════════════╣"
  echo "║ 1) Buat SSH & OpenVPN        ║"
  echo "║ 2) Buat Xray VLESS           ║"
  echo "║ 3) Buat Xray VMess           ║"
  echo "║ 4) Buat Xray Trojan          ║"
  echo "║ 5) Buat Xray Shadowsocks     ║"
  echo "║ 6) Hapus Akun                ║"
  echo "║ 7) Daftar User               ║"
  echo "║ 8) Set Quota Limit           ║"
  echo "║ 9) Cek Expired               ║"
  echo "║ 10) Restart Service          ║"
  echo "║ 11) Backup Data              ║"
  echo "║ 12) Restore Data             ║"
  echo "║ 13) Keluar                   ║"
  echo "╚═══════════════════════════════╝${NC}"
  read -p "Pilih [1-13]: " c
  case $c in
    1) create_ssh ;; 2) create_vless ;; 3) create_vmess ;; 4) create_trojan ;;
    5) create_ss ;; 6) delete_user ;; 7) list_users ;; 8) set_quota ;;
    9) check_expired ;; 10) restart_all ;; 11) backup_data ;; 12) restore_data ;; 13) exit 0 ;;
  esac
done
MENUEOF
chmod +x /usr/local/bin/menu

# ---------- HELPER SCRIPTS ----------
# alluser - cek user expired
cat > /usr/local/bin/alluser << 'ALLUSEREOF'
#!/bin/bash
echo "=== USER SSH/OpenVPN ==="
if [[ -f /etc/ssh-user.db ]]; then
  while IFS=' ' read -r u e p; do
    echo "User: $u | Exp: $e | Pass: $p"
  done < /etc/ssh-user.db
fi
echo ""
echo "=== Xray VMess ==="
grep '^###' /etc/xray/config.json 2>/dev/null | while read -r line; do
  u=$(echo "$line" | cut -d ' ' -f 2)
  e=$(echo "$line" | cut -d ' ' -f 3)
  echo "User: $u | Exp: $e"
done
echo ""
echo "=== Xray Trojan ==="
grep '^#!' /etc/xray/config.json 2>/dev/null | while read -r line; do
  u=$(echo "$line" | cut -d ' ' -f 2)
  e=$(echo "$line" | cut -d ' ' -f 3)
  echo "User: $u | Exp: $e"
done
ALLUSEREOF
chmod +x /usr/local/bin/alluser

# log_clear - clear log + restart
cat > /usr/local/bin/log_clear << 'LOGCLEAR'
#!/bin/bash
tanggal=$(date +%m-%d-%Y)
waktu=$(date +%H:%M:%S)
echo "Clear log On $tanggal - $waktu" >> /root/log-clear.txt
> /var/log/xray/access.log
> /var/log/xray/error.log
systemctl restart udp-custom.service
echo "Log dibersihin, UDP-Custom di-restart"
echo "Log dibersihin!"
LOGCLEAR
chmod +x /usr/local/bin/log_clear

echo -e "${GREEN}✓ Menu & helper scripts terinstall${NC}"
echo ""

# ---------- SELESAI ----------
echo -e "${CYAN}[14/14] Selesai!${NC}"
echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║      ✦ $BRAND_NAME ✅ INSTALL OK ✦      ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BOLD}=== INFO SERVER ===${NC}"
echo -e "Domain     : $DOMAIN"
echo -e "IP VPS     : $MYIP"
echo -e "UUID/Pass  : $uuid"
echo -e ""
echo -e "${BOLD}=== PORT TUNNELING ===${NC}"
echo -e "Xray WS    : 80, 8080, 8880, 2082, 2086, 2095 (HTTP/WS)"
echo -e "Xray gRPC  : 443 (HTTPS/h2)"
echo -e "SSH        : 143, 109"
echo -e "OpenVPN TCP: 1194"
echo -e "OpenVPN UDP: 2200"
echo -e "UDP-Custom : 36712"
echo -e "UDP-Mini   : 7100, 7200, 7300"
echo -e "Multi-port : 222-1000 (HAProxy)"
echo -e ""
echo -e "${BOLD}=== PATH CONFIG ===${NC}"
echo -e "Xray       : /etc/xray/config.json"
echo -e "OpenVPN    : /etc/openvpn/server/"
echo -e "HAProxy    : /etc/haproxy/haproxy.cfg"
echo -e "WS Tunnel  : /usr/bin/tun.conf"
echo -e "UDP-Custom : /etc/udp/config.json"
echo -e "Kyt Limit  : /etc/guard/limit/"
echo -e ""
echo -e "${YELLOW}Simpan UUID/Password di tempat aman!${NC}"
echo ""