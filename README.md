# ✦ Tunnel PRO V2

Universal — Ubuntu 18/20/22/24 + Debian 11/12 + Telegram Notify + Backup/Restore.

**Edit manual gampang** (tanpa edit banyak file):
```bash
# Ganti banner
sed -i 's/TUNNEL PRO V2/NAMA KAMU/g' install.sh
# Ganti limiter (pengganti kyt -> guard)
sed -i 's|/etc/guard|/etc/mylimit|g; s/guard\.service/mylimit.service/g; s|/usr/local/guard|/usr/local/mylimit|g' install.sh
# Atau edit variable di atas file:
# BRAND_NAME="NAMA KAMU"
# LIMITER_NAME="mylimit"
```

Install:
```bash
wget -O install.sh https://raw.githubusercontent.com/Emans27/sunek-tunnel-pro/main/install.sh && chmod +x install.sh && sudo bash install.sh
```
Menu: 1 SSH/OVPN 2 VLESS 3 VMess 4 Trojan 5 SS 6 Hapus 7 Daftar 8 Quota 9 Expired 10 Restart 11 Backup 12 Restore 13 Keluar

Limiter default `guard` (pengganti `kyt`), banner `TUNNEL PRO V2` — keduanya bisa diubah manual via 1 baris sed.
