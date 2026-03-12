# 📡 StatusWRT Irfan — `luci-app-informasi-wrt`

> Paket monitoring & informasi sistem lengkap untuk OpenWrt di **Raspberry Pi 4B**
> Menambahkan menu **Services → Informasi** di LuCI dengan dashboard realtime.

[![CI/CD Build IPK](https://github.com/irfanFRizki/StatusWRTIrfan/actions/workflows/build.yml/badge.svg)](https://github.com/irfanFRizki/StatusWRTIrfan/actions)
[![Latest Release](https://img.shields.io/github/v/release/irfanFRizki/StatusWRTIrfan?label=IPK%20Release)](https://github.com/irfanFRizki/StatusWRTIrfan/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

---

## ✨ Fitur

| Fitur | Keterangan |
|-------|-----------|
| 🖥️ **Dashboard** | CPU load, Memory, Uptime, Suhu Raspberry Pi — realtime |
| 👥 **Klien Online** | Tabel user terhubung dari `dhcp.leases` + `ip neigh`, auto-refresh 15 detik |
| 🌐 **Network** | Status semua interface, IP, RX/TX traffic |
| 💾 **Storage** | Disk usage dengan progress bar per partisi |
| 📊 **System Info** | Hostname, uptime, RAM detail, load average |
| 📋 **System Log** | Live log viewer (`logread`) |
| 🔧 **Auto-install deps** | Script `postinst` otomatis install semua dependency |
| 🔄 **Auto-build IPK** | GitHub Actions build & release IPK setiap `git push` |

---

## 🗂️ Struktur Repo

```
StatusWRTIrfan/
│
├── .github/workflows/
│   └── build.yml                    # GitHub Actions CI/CD — auto build IPK
│
├── etc/
│   ├── config/                      # UCI config (dhcp, mwan3, data-monitor, dll)
│   ├── crontabs/root                # Cron jobs
│   ├── init.d/                      # Service scripts (aria2, telegram-bot, dll)
│   ├── cloudflared/                 # Cloudflare Tunnel config
│   ├── nlbwmon/                     # Database traffic nlbwmon
│   ├── vnstat/                      # Database vnstat
│   └── uci-defaults/
│       └── 99-luci-app-informasi-wrt   # Init script post-install
│
├── usr/
│   ├── bin/
│   │   ├── online.sh                # ⭐ Monitor klien DHCP realtime
│   │   ├── sysinfo.sh               # Info sistem (CPU, RAM, Uptime)
│   │   ├── checkIP.py               # Cek status IP
│   │   ├── mwan3_check.py           # Monitor MWAN3 failover
│   │   ├── send_telegram.py         # Kirim notifikasi Telegram
│   │   ├── vnstat-backup.py/.sh     # Backup data vnstat
│   │   └── vpn.py                   # Monitor status VPN
│   │
│   ├── lib/lua/luci/
│   │   ├── controller/
│   │   │   └── informasi.lua        # LuCI Controller — daftarkan semua menu
│   │   └── view/informasi/
│   │       ├── index.htm            # Halaman utama + stat cards
│   │       ├── dashboard.htm        # Dashboard lengkap realtime
│   │       ├── clients.htm          # ⭐ Tabel klien online
│   │       ├── network.htm          # Interface & traffic
│   │       ├── storage.htm          # Disk usage
│   │       ├── system.htm           # System info
│   │       ├── info.htm             # Info tambahan
│   │       ├── log.htm              # System log viewer
│   │       ├── allowed.htm          # Manajemen IP allowed
│   │       ├── notallowed.htm       # IP blocked
│   │       ├── telegram.htm         # Konfigurasi Telegram bot
│   │       └── settings.htm         # Pengaturan
│   │
│   └── share/rpcd/acl.d/
│       └── luci-app-informasi-wrt.json  # ACL permissions rpcd
│
├── www/
│   ├── cgi-bin/
│   │   ├── online                   # CGI: data klien online (JSON)
│   │   ├── status                   # CGI: status sistem
│   │   ├── traffic                  # CGI: data traffic
│   │   ├── vnstat-json.cgi          # CGI: data vnstat JSON
│   │   ├── get_ips / save_ips       # CGI: manajemen IP
│   │   ├── load_biaya / save_biaya  # CGI: data biaya
│   │   ├── pemakaian / minggu*      # CGI: statistik pemakaian
│   │   ├── pwm-fan-status           # CGI: status fan RPi
│   │   └── install_action.sh        # CGI: aksi instalasi
│   ├── active.html / display.html   # Halaman monitoring web
│   ├── hitung.html                  # Kalkulator biaya
│   ├── install.html                 # Panduan instalasi web
│   ├── list.html                    # Daftar perangkat
│   └── vpn.html / vpnM.html         # Monitor VPN
│
├── ipk_build/
│   ├── control                      # Package metadata & dependencies
│   ├── postinst                     # Auto-install semua dependency
│   └── prerm                        # Cleanup saat uninstall
│
├── scripts/
│   ├── version.sh                   # Auto-increment versi tiap push
│   └── changelog.sh                 # Auto-generate CHANGELOG dari git log
│
├── VERSION                          # Versi paket saat ini
├── CHANGELOG.md                     # Auto-generated changelog
└── README.md                        # Dokumentasi ini
```

---

## 📦 Dependency yang Diinstall Otomatis

Script `postinst` akan otomatis menginstall semua dependency setelah `opkg install`:

| Kategori | Paket |
|----------|-------|
| **LuCI** | `luci-base`, `luci-compat`, `luci-lib-ip`, `luci-lib-base` |
| **Lua** | `lua`, `liblua5.1`, `libuci-lua` |
| **System** | `rpcd`, `rpcd-mod-rpcsys`, `uhttpd`, `ubus`, `uci` |
| **Python3** | `python3`, `python3-pip`, `python3-light`, `python3-base` |
| **Tools** | `curl`, `wget`, `htop`, `bash`, `procps-ng` |
| **Opsional** | `vnstat`, `luci-app-vnstat`, `luci-app-vnstat2` |

---

## 🚀 Instalasi di OpenWrt

### Metode 1 — Download dari GitHub Releases (Paling Mudah)
```bash
# SSH ke router
ssh root@192.168.1.1

# Download IPK terbaru
cd /tmp
wget https://github.com/irfanFRizki/StatusWRTIrfan/releases/latest/download/luci-app-informasi-wrt_$(curl -s https://raw.githubusercontent.com/irfanFRizki/StatusWRTIrfan/main/VERSION | tr -d '\n')_all.ipk

# Install
opkg install luci-app-informasi-wrt_*_all.ipk
```

### Metode 2 — Via Termux (dari HP)
```bash
# Di Termux
# Download IPK
curl -sL $(curl -s https://api.github.com/repos/irfanFRizki/StatusWRTIrfan/releases/latest \
  | grep browser_download_url | cut -d'"' -f4) -o /tmp/informasi.ipk

# Kirim ke router & install
scp /tmp/informasi.ipk root@192.168.1.1:/tmp/
ssh root@192.168.1.1 "opkg install /tmp/informasi.ipk"
```

### Metode 3 — Manual Build dari Source
```bash
git clone https://github.com/irfanFRizki/StatusWRTIrfan.git
cd StatusWRTIrfan

chmod +x scripts/*.sh ipk_build/postinst ipk_build/prerm
VERSION=$(bash scripts/version.sh)

echo "2.0" > debian-binary
mkdir -p control
sed "s/^Version:.*/Version: $VERSION/" ipk_build/control > control/control
cp ipk_build/postinst ipk_build/prerm control/
chmod +x control/postinst control/prerm

tar -czf control.tar.gz control/
tar -czf data.tar.gz usr/ etc/ www/
tar -czf "luci-app-informasi-wrt_${VERSION}_all.ipk" debian-binary control.tar.gz data.tar.gz

echo "✅ Build: luci-app-informasi-wrt_${VERSION}_all.ipk"
```

---

## 🔄 Workflow Upload via Termux → GitHub → OpenWrt

```
Termux (HP)  ──git push──►  GitHub  ──Actions──►  IPK Release
                                                       │
OpenWrt (RPi4) ◄──opkg install──────────────────────── ┘
```

```bash
# Di Termux — edit file lalu push
cd ~/StatusWRTIrfan
# ... edit file ...
git add .
git commit -m "feat: perubahan baru"
git push origin main

# GitHub Actions otomatis:
# ✅ Increment versi
# ✅ Generate CHANGELOG
# ✅ Build IPK
# ✅ Upload ke GitHub Releases

# Download & install ke router
ssh root@192.168.1.1 "cd /tmp && \
  wget https://github.com/irfanFRizki/StatusWRTIrfan/releases/latest/download/luci-app-informasi-wrt_*_all.ipk && \
  opkg install luci-app-informasi-wrt_*_all.ipk"
```

---

## 🖥️ Cara Kerja `online.sh`

Script utama untuk monitoring klien realtime:

```
/tmp/dhcp.leases ──┐
                    ├──► online.sh ──► JSON ──► LuCI API ──► clients.htm
ip neigh show    ──┘                                          (auto-refresh 15 detik)
```

```bash
# Jalankan manual di OpenWrt
/usr/bin/online.sh          # Output teks
/usr/bin/online.sh json     # Output JSON (untuk API)
```

**Status klien:**
| Status | Artinya |
|--------|---------|
| 🟢 **TERHUBUNG** | `ip neigh` = REACHABLE |
| 🟡 **TERHUBUNG TIDAK AKTIF** | `ip neigh` = STALE |
| 🔵 **TIDAK DIKETAHUI** | State tidak dikenali |
| 🔴 **TIDAK TERHUBUNG** | Tidak ada di `ip neigh` / FAILED |

---

## 🤖 GitHub Actions CI/CD

Setiap `git push` ke branch `main` akan otomatis:

1. Checkout repo
2. Increment versi (`scripts/version.sh`)
3. Generate CHANGELOG (`scripts/changelog.sh`)
4. Commit `VERSION` + `CHANGELOG.md`
5. Build IPK package
6. Upload IPK ke **GitHub Releases**

File yang di-**ignore** (tidak ikut ke IPK):
```
*.ipk, *.tar.gz, debian-binary, control/, ipk_work/, StatusWRTIrfan/
```

---

## 🛠️ Tips Termux

```bash
# Setup awal (sekali saja)
pkg update && pkg install git openssh
git config --global user.name "irfanFRizki"
git config --global user.email "email@example.com"

# Ekstrak ZIP update dengan benar (hindari embedded repo)
mkdir -p ~/tmp_patch
unzip -o ~/namafile.zip -d ~/tmp_patch
cp -r ~/tmp_patch/patch/usr ~/StatusWRTIrfan/
cp -r ~/tmp_patch/patch/etc ~/StatusWRTIrfan/
rm -rf ~/tmp_patch
```

---

## 👤 Maintainer

**irfanFRizki** — [github.com/irfanFRizki/StatusWRTIrfan](https://github.com/irfanFRizki/StatusWRTIrfan)

Dibuat untuk OpenWrt di **Raspberry Pi 4B** 🍓
