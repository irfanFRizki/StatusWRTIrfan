# StatusWRT Irfan — luci-app-informasi-wrt

> Paket LuCI untuk monitoring & informasi sistem OpenWrt di Raspberry Pi 4B

[![StatusWRT CI/CD](https://github.com/irfanFRizki/StatusWRTIrfan/actions/workflows/build.yml/badge.svg)](https://github.com/irfanFRizki/StatusWRTIrfan/actions)
[![Latest Release](https://img.shields.io/github/v/release/irfanFRizki/StatusWRTIrfan)](https://github.com/irfanFRizki/StatusWRTIrfan/releases/latest)

---

## 📋 Fitur

- ✅ **Menu Services > Informasi** di LuCI
- ✅ **Dashboard real-time** — CPU, Memory, Suhu, Uptime
- ✅ **Network Monitor** — Status interface, IP, RX/TX
- ✅ **Storage Monitor** — Disk usage dengan grafik
- ✅ **System Log Viewer** — Live log
- ✅ **Auto-install dependencies** via `postinst`
- ✅ **Build otomatis** via GitHub Actions setiap push ke `main`

---

## 📦 Struktur Direktori

```
StatusWRTIrfan/
├── .github/
│   └── workflows/
│       └── build.yml              # GitHub Actions CI/CD
├── etc/
│   └── uci-defaults/
│       └── 99-luci-app-informasi-wrt  # Post-install init
├── usr/
│   ├── lib/lua/luci/
│   │   ├── controller/
│   │   │   └── informasi.lua      # LuCI Controller (menu)
│   │   └── view/informasi/
│   │       ├── index.htm          # Halaman utama
│   │       └── dashboard.htm     # Dashboard monitoring
│   └── share/rpcd/acl.d/
│       └── luci-app-informasi-wrt.json  # ACL permissions
├── www/                           # File web statis
├── scripts/
│   ├── version.sh                 # Auto-versioning
│   └── changelog.sh              # Auto-changelog
├── ipk_build/
│   ├── control                    # Package metadata
│   ├── postinst                   # Auto-install deps
│   └── prerm                     # Pre-remove cleanup
├── VERSION                        # File versi saat ini
└── CHANGELOG.md                   # Auto-generated
```

---

## 🚀 Cara Install di OpenWrt

### Metode 1: Download dari GitHub Releases
```bash
# Di OpenWrt terminal (SSH)
cd /tmp
wget https://github.com/irfanFRizki/StatusWRTIrfan/releases/latest/download/luci-app-informasi-wrt_VERSION_all.ipk
opkg install luci-app-informasi-wrt_VERSION_all.ipk
```

### Metode 2: Via Termux (dari HP ke Router)
```bash
# Di Termux HP
pkg install openssh

# Download IPK terbaru
curl -sL https://github.com/irfanFRizki/StatusWRTIrfan/releases/latest/download/luci-app-informasi-wrt_$(cat VERSION)_all.ipk \
  -o /tmp/informasi.ipk

# Kirim ke router via SCP
scp /tmp/informasi.ipk root@192.168.1.1:/tmp/

# Install via SSH
ssh root@192.168.1.1 'opkg install /tmp/informasi.ipk'
```

### Metode 3: Remote dari PC via Termux
```bash
# Di Termux — remote ke PC untuk build & deploy
ssh user@PC_IP "cd StatusWRTIrfan && git pull && scp *.ipk root@192.168.1.1:/tmp/"
ssh root@192.168.1.1 "opkg install /tmp/luci-app-informasi-wrt_*_all.ipk"
```

---

## 🔄 Upload ke GitHub via Termux

```bash
# Setup di Termux (sekali saja)
pkg update && pkg install git openssh
git config --global user.name "irfanFRizki"
git config --global user.email "email@example.com"

# Clone repo
git clone https://github.com/irfanFRizki/StatusWRTIrfan.git
cd StatusWRTIrfan

# Edit file, lalu push
git add .
git commit -m "feat: perubahan baru"
git push origin main

# GitHub Actions akan otomatis:
# 1. Increment versi
# 2. Generate changelog
# 3. Build IPK
# 4. Upload ke GitHub Releases
```

---

## 📦 Dependencies yang Diinstall Otomatis

Setelah `opkg install`, script `postinst` akan otomatis install:

| Kategori | Paket |
|----------|-------|
| LuCI | `luci-base`, `luci-compat`, `luci-lib-ip` |
| Lua | `lua`, `liblua5.1`, `libuci-lua` |
| System | `rpcd`, `uhttpd`, `ubus`, `uci` |
| Python | `python3`, `python3-pip`, `python3-light` |
| Tools | `curl`, `wget`, `htop`, `procps-ng` |
| Optional | `vnstat`, `luci-app-vnstat` |

---

## 🛠️ Development

```bash
# Build manual (tanpa GitHub Actions)
chmod +x scripts/*.sh
VERSION=$(bash scripts/version.sh)
bash scripts/changelog.sh $VERSION

# Build IPK
echo "2.0" > debian-binary
mkdir -p control
cp ipk_build/control control/control
sed -i "s/^Version:.*/Version: $VERSION/" control/control
cp ipk_build/postinst control/
cp ipk_build/prerm control/
chmod +x control/postinst control/prerm
tar -czf control.tar.gz control/
tar -czf data.tar.gz usr/ etc/ www/
tar -czf "luci-app-informasi-wrt_${VERSION}_all.ipk" debian-binary control.tar.gz data.tar.gz
echo "✅ Build: luci-app-informasi-wrt_${VERSION}_all.ipk"
```

---

## 👤 Maintainer

**irfanFRizki** — [GitHub](https://github.com/irfanFRizki/StatusWRTIrfan)

Dibuat untuk OpenWrt di Raspberry Pi 4B 🍓
