# ✦ Suneko Tunnel PRO v2

Universal installer — support **Ubuntu 18/20/22/24** + **Debian 11/12** (auto PAM plugin detect, pylib sysconfig, IF dynamic).

- Xray (VLESS/VMess/Trojan/SS WS+gRPC) + OpenVPN TCP 1194 UDP 2200 + SSH Dropbear 143,109 + UDP-Custom 36712 + WS + HAProxy multi-port 80/443 + Nginx 1010/1012/1013
- **Telegram notify**: setiap generate akun (SSH/VLESS/VMess/Trojan/SS) auto kirim ke bot (jika `/etc/bot/.bot.db` ada) + quota habis tetap notif
- **Backup/Restore**: menu 11/12 → `tar.gz` `/root/sunek-backup-*.tar.gz`, opsi kirim dokumen ke Telegram

## Install
```bash
wget -O install.sh https://raw.githubusercontent.com/Emans27/sunek-tunnel-pro/main/install.sh && chmod +x install.sh && sudo bash install.sh
```

## Menu
```
╔════════════════════════════════╗
║     ✦ SUNEKO TUNNEL PRO MENU ✦     ║
║ 1) SSH & OpenVPN  2) VLESS  3) VMess  4) Trojan  5) Shadowsocks
║ 6) Hapus Akun  7) Daftar User  8) Set Quota  9) Cek Expired  10) Restart
║ 11) Backup Data  12) Restore Data  13) Keluar
╚════════════════════════════════╝
```

File: `install.sh` 60K sha `8136998a`
