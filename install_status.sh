#!/bin/bash
# ========================
# Variabel Warna (ANSI Escape Sequences)
# ========================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ========================
# Fungsi Loading Progress
# ========================
loading_progress() {
  label="$1"
  # Array warna untuk efek bergantian
  colors=( "$RED" "$YELLOW" "$GREEN" "$CYAN" "$BLUE" "$PURPLE" )
  num_colors=${#colors[@]}
  for i in $(seq 1 100); do
    color=${colors[$(( (i-1) % num_colors ))]}
    printf "\r${color}%s: %d%%${NC}" "$label" "$i"
    sleep 0.03
  done
  printf "\n"
}

echo -e "${CYAN}Mulai proses instalasi...${NC}"

# ------------------------
# 1. Perbarui Paket dan Instalasi Awal
# ------------------------
opkg update > /dev/null 2>&1
loading_progress "Updating paket"
echo -e "${GREEN}Update paket selesai.${NC}"

OPKG_BC=$(opkg install bc 2>&1)
loading_progress "Menginstal bc"
echo -e "${GREEN}${OPKG_BC}${NC}"

OPKG_GIT=$(opkg install git 2>&1)
loading_progress "Menginstal git"
echo -e "${GREEN}${OPKG_GIT}${NC}"

OPKG_GIT_HTTP=$(opkg install git-http 2>&1)
loading_progress "Menginstal git-http"
echo -e "${GREEN}${OPKG_GIT_HTTP}${NC}"

# ------------------------
# 2. Clone Repository StatusWRTIrfan
# ------------------------
cd /root
git clone https://github.com/irfanFRizki/StatusWRTIrfan.git > /dev/null 2>&1
loading_progress "Meng-clone repository"
echo -e "${GREEN}Clone repository selesai.${NC}"

SRC_DIR="/root/StatusWRTIrfan"

# ------------------------
# 3. Pindahkan File ke Direktori Tujuan
# ------------------------
LUA_CONTROLLER_DIR="/usr/lib/lua/luci/controller/"
LUA_VIEW_DIR="/usr/lib/lua/luci/view/"
CGI_BIN_DIR="/www/cgi-bin/"
WWW_DIR="/www/"

mkdir -p $LUA_CONTROLLER_DIR $LUA_VIEW_DIR $CGI_BIN_DIR $WWW_DIR > /dev/null 2>&1
loading_progress "Membuat direktori tujuan"
echo -e "${GREEN}Direktori tujuan dibuat.${NC}"

# Pindahkan file status_monitor
mv $SRC_DIR/usr/lib/lua/luci/controller/status_monitor.lua $LUA_CONTROLLER_DIR > /dev/null 2>&1
loading_progress "Memindahkan file status_monitor.lua"
echo -e "${GREEN}File status_monitor.lua dipindahkan.${NC}"

mv $SRC_DIR/usr/lib/lua/luci/view/status_monitor.htm $LUA_VIEW_DIR > /dev/null 2>&1
loading_progress "Memindahkan file status_monitor.htm"
echo -e "${GREEN}File status_monitor.htm dipindahkan.${NC}"

# Pindahkan file online
mv $SRC_DIR/usr/bin/online.sh /usr/bin/online.sh > /dev/null 2>&1
loading_progress "Memindahkan file online.sh"
echo -e "${GREEN}File online.sh dipindahkan ke /usr/bin.${NC}"

mv $SRC_DIR/usr/lib/lua/luci/controller/online.lua $LUA_CONTROLLER_DIR > /dev/null 2>&1
loading_progress "Memindahkan file online.lua"
echo -e "${GREEN}File online.lua dipindahkan.${NC}"

mv $SRC_DIR/usr/lib/lua/luci/view/online.htm $LUA_VIEW_DIR > /dev/null 2>&1
loading_progress "Memindahkan file online.htm"
echo -e "${GREEN}File online.htm dipindahkan.${NC}"

# Pindahkan file CGI scripts
mv $SRC_DIR/www/cgi-bin/load_biaya $CGI_BIN_DIR > /dev/null 2>&1
mv $SRC_DIR/www/cgi-bin/minggu1 $CGI_BIN_DIR > /dev/null 2>&1
mv $SRC_DIR/www/cgi-bin/minggu2 $CGI_BIN_DIR > /dev/null 2>&1
mv $SRC_DIR/www/cgi-bin/minggu3 $CGI_BIN_DIR > /dev/null 2>&1
mv $SRC_DIR/www/cgi-bin/minggu4 $CGI_BIN_DIR > /dev/null 2>&1
mv $SRC_DIR/www/cgi-bin/mingguterakhir $CGI_BIN_DIR > /dev/null 2>&1
mv $SRC_DIR/www/cgi-bin/pemakaian $CGI_BIN_DIR > /dev/null 2>&1
mv $SRC_DIR/www/cgi-bin/save_biaya $CGI_BIN_DIR > /dev/null 2>&1
mv $SRC_DIR/www/cgi-bin/status $CGI_BIN_DIR > /dev/null 2>&1
loading_progress "Memindahkan CGI scripts"
echo -e "${GREEN}CGI scripts dipindahkan.${NC}"

mv $SRC_DIR/www/status_monitor.html $WWW_DIR > /dev/null 2>&1
loading_progress "Memindahkan file HTML"
echo -e "${GREEN}File HTML status monitor dipindahkan.${NC}"

chmod +x $CGI_BIN_DIR/* > /dev/null 2>&1
loading_progress "Mengatur izin eksekusi CGI"
echo -e "${GREEN}Izin eksekusi CGI diatur.${NC}"

/etc/init.d/uhttpd restart > /dev/null 2>&1
loading_progress "Restarting uhttpd"
echo -e "${GREEN}uhttpd telah direstart.${NC}"

# ------------------------
# 4. Feed Script & Instalasi Paket Nikki
# ------------------------
curl -s -L https://github.com/nikkinikki-org/OpenWrt-nikki/raw/refs/heads/main/feed.sh | ash > /dev/null 2>&1
loading_progress "Menjalankan feed script nikki"
echo -e "${GREEN}Feed script nikki selesai dijalankan.${NC}"

OPKG_NIKKI=$(opkg install nikki 2>&1)
loading_progress "Menginstal paket nikki"
echo -e "${GREEN}${OPKG_NIKKI}${NC}"

OPKG_LUCI_NIKKI=$(opkg install luci-app-nikki 2>&1)
loading_progress "Menginstal luci-app-nikki"
echo -e "${GREEN}${OPKG_LUCI_NIKKI}${NC}"

OPKG_LUCI_I18N=$(opkg install luci-i18n-nikki-zh-cn 2>&1)
loading_progress "Menginstal luci-i18n-nikki-zh-cn"
echo -e "${GREEN}${OPKG_LUCI_I18N}${NC}"

APK_NIKKI=$(apk add --allow-untrusted nikki 2>&1)
loading_progress "APK: Menginstal nikki"
echo -e "${GREEN}${APK_NIKKI}${NC}"

APK_LUCI_NIKKI=$(apk add --allow-untrusted luci-app-nikki 2>&1)
loading_progress "APK: Menginstal luci-app-nikki"
echo -e "${GREEN}${APK_LUCI_NIKKI}${NC}"

APK_LUCI_I18N=$(apk add --allow-untrusted luci-i18n-nikki-zh-cn 2>&1)
loading_progress "APK: Menginstal luci-i18n-nikki-zh-cn"
echo -e "${GREEN}${APK_LUCI_I18N}${NC}"

# ------------------------
# 5. Memproses File blm.tar.gz dan Konfigurasi Nikki Lainnya
# ------------------------
echo -e "${CYAN}Memindahkan dan mengekstrak blm.tar.gz ke /etc/nikki/${NC}"
mkdir -p /etc/nikki/ > /dev/null 2>&1
mv $SRC_DIR/blm.tar.gz /etc/nikki/ > /dev/null 2>&1
cd /etc/nikki/
tar -xzvf blm.tar.gz > /dev/null 2>&1
loading_progress "Mengekstrak blm.tar.gz"
echo -e "${GREEN}blm.tar.gz diekstrak.${NC}"

mkdir -p /etc/nikki/run/proxy_provider/ > /dev/null 2>&1
loading_progress "Membuat direktori proxy_provider"
echo -e "${GREEN}Direktori proxy_provider dibuat.${NC}"

base64 -d "$SRC_DIR/PID.txt" > /etc/nikki/run/proxy_provider/INDO.yaml
loading_progress "Memperbarui INDO.yaml"
echo -e "${GREEN}File INDO.yaml telah diperbarui.${NC}"

# ------------------------
# 6. Mengganti File vnstat.db dan Memperbarui /etc/nlbwmon/
# ------------------------
echo -e "${CYAN}Mengganti file vnstat.db dengan yang ada di repository${NC}"
mkdir -p /etc/vnstat > /dev/null 2>&1
if [ -f /etc/vnstat/vnstat.db ]; then
    echo -e "${YELLOW}Mengganti file vnstat.db dengan yang ada di repository${NC}"
    rm -f /etc/vnstat/vnstat.db
fi
mv $SRC_DIR/vnstat.db /etc/vnstat/ > /dev/null 2>&1
loading_progress "Memindahkan vnstat.db"
echo -e "${GREEN}File vnstat.db telah diganti.${NC}"

echo -e "${CYAN}Memperbarui file di /etc/nlbwmon/ dengan file backup dari repository${NC}"
if [ -d "/etc/nlbwmon" ]; then
    rm -rf /etc/nlbwmon/* > /dev/null 2>&1
fi
mkdir -p /etc/nlbwmon/ > /dev/null 2>&1
cp -r $SRC_DIR/etc/nlbwmon/* /etc/nlbwmon/ > /dev/null 2>&1
loading_progress "Memperbarui /etc/nlbwmon/"
echo -e "${GREEN}File di /etc/nlbwmon/ telah diperbarui.${NC}"

rm -rf $SRC_DIR > /dev/null 2>&1
loading_progress "Menghapus folder repository"
echo -e "${GREEN}Folder repository telah dihapus.${NC}"

# ------------------------
# 7. Membuat File nftables
# ------------------------
echo -e "${CYAN}Membuat file /etc/nftables.d/11-ttl.nft${NC}"
mkdir -p /etc/nftables.d/ > /dev/null 2>&1
cat << 'EOF' > /etc/nftables.d/11-ttl.nft
chain mangle_postrouting_ttl65 {
      type filter hook postrouting priority 300; policy accept;
        counter ip ttl set 65 
}

chain mangle_prerouting_ttl65 {
      type filter hook prerouting priority 300; policy accept;
        counter ip ttl set 65 
}
EOF
loading_progress "Membuat file 11-ttl.nft"
echo -e "${GREEN}File 11-ttl.nft telah dibuat.${NC}"

/etc/init.d/firewall restart > /dev/null 2>&1
loading_progress "Restarting firewall"
echo -e "${GREEN}Firewall telah direstart.${NC}"

# ------------------------
# 8. Instalasi & Konfigurasi wrtbwmon
# ------------------------
sleep 2
OPKG_WGET=$(opkg install wget 2>&1)
loading_progress "Menginstal wget"
echo -e "${GREEN}${OPKG_WGET}${NC}"

cd /tmp && wget https://github.com/brvphoenix/luci-app-wrtbwmon/releases/download/release-2.0.11/wrtbwmon_2.0.11_all.ipk > /dev/null 2>&1
loading_progress "Mengunduh wrtbwmon ipk"
echo -e "${GREEN}wrtbwmon ipk diunduh.${NC}"

OPKG_WRTBWMON=$(opkg install /tmp/wrtbwmon_2.0.11_all.ipk 2>&1)
loading_progress "Menginstal wrtbwmon"
echo -e "${GREEN}${OPKG_WRTBWMON}${NC}"

cd /tmp && wget https://github.com/brvphoenix/luci-app-wrtbwmon/releases/download/release-2.0.11/luci-app-wrtbwmon_2.0.11_all.ipk > /dev/null 2>&1
loading_progress "Mengunduh luci-app-wrtbwmon ipk"
echo -e "${GREEN}luci-app-wrtbwmon ipk diunduh.${NC}"

OPKG_LUCI_WRTBWMON=$(opkg install /tmp/luci-app-wrtbwmon_2.0.11_all.ipk 2>&1)
loading_progress "Menginstal luci-app-wrtbwmon"
echo -e "${GREEN}${OPKG_LUCI_WRTBWMON}${NC}"

sleep 2
/etc/init.d/wrtbwmon enable > /dev/null 2>&1
/etc/init.d/wrtbwmon start > /dev/null 2>&1
loading_progress "Memulai wrtbwmon"
echo -e "${GREEN}wrtbwmon telah diaktifkan dan dijalankan.${NC}"

# ------------------------
# 9. Instruksi Konfigurasi Manual wrtbwmon
# ------------------------
echo -e "${CYAN}-----------------------------------------------------------${NC}"
echo -e "${CYAN}Buka menu Network > Traffic Status di LuCI.${NC}"
echo -e "${CYAN}Kemudian klik CONFIGURE OPTIONS dan atur sebagai berikut:${NC}"
echo -e "${CYAN}  Default Refresh Intervals: 2 Seconds${NC}"
echo -e "${CYAN}  Default More Columns: Centang${NC}"
echo -e "${CYAN}  Show Zeros: Jangan di centang${NC}"
echo -e "${CYAN}  Upstream Bandwidth: 100${NC}"
echo -e "${CYAN}  Downstream Bandwidth: 100${NC}"
echo -e "${CYAN}-----------------------------------------------------------${NC}"
