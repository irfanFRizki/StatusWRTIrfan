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

# Global: Lokasi repository (di-set setelah clone)
SRC_DIR=""

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

# ========================
# Fungsi 1: Update paket & Instal dependensi
# ========================
install_update() {
  echo -e "${CYAN}Memulai update paket dan instalasi dependensi...${NC}"
  opkg update > /dev/null 2>&1
  loading_progress "Updating paket"
  echo -e "${GREEN}Update paket selesai.${NC}"
  for pkg in coreutils-sleep bc git git-http wget; do
    loading_progress "Menginstal $pkg"
    echo -e "${GREEN}$(opkg install $pkg 2>&1)${NC}"
  done
}

# ========================
# Fungsi 2: Clone repository dan pindahkan file (Status Monitor)
# ========================
clone_repo() {
  echo -e "${CYAN}Meng-clone repository StatusWRTIrfan...${NC}"
  cd /root || return
  git clone https://github.com/irfanFRizki/StatusWRTIrfan.git > /dev/null 2>&1
  loading_progress "Meng-clone repository"
  echo -e "${GREEN}Clone repository selesai.${NC}"
  SRC_DIR="/root/StatusWRTIrfan"

  # Direktori tujuan
  LUA_CTRL="/usr/lib/lua/luci/controller/"
  LUA_VIEW="/usr/lib/lua/luci/view/"
  CGI_BIN="/www/cgi-bin/"
  WWW_DIR="/www/"
  mkdir -p "$LUA_CTRL" "$LUA_VIEW" "$CGI_BIN" "$WWW_DIR" > /dev/null 2>&1
  loading_progress "Membuat direktori tujuan"
  echo -e "${GREEN}Direktori tujuan dibuat.${NC}"

  mv "$SRC_DIR/usr/lib/lua/luci/controller/status_monitor.lua" "$LUA_CTRL" > /dev/null 2>&1
  loading_progress "Memindahkan status_monitor.lua"
  echo -e "${GREEN}File status_monitor.lua dipindahkan.${NC}"

  mv "$SRC_DIR/usr/lib/lua/luci/view/status_monitor.htm" "$LUA_VIEW" > /dev/null 2>&1
  loading_progress "Memindahkan status_monitor.htm"
  echo -e "${GREEN}File status_monitor.htm dipindahkan.${NC}"
}

# ========================
# Fungsi 3: Instal & Konfigurasi Paket Nikki
# ========================
install_nikki() {
  echo -e "${CYAN}Memulai instalasi paket Nikki...${NC}"
  curl -s -L https://github.com/nikkinikki-org/OpenWrt-nikki/raw/refs/heads/main/feed.sh | ash > /dev/null 2>&1
  loading_progress "Menjalankan feed script nikki"
  echo -e "${GREEN}Feed script nikki selesai dijalankan.${NC}"
  for pkg in nikki luci-app-nikki luci-i18n-nikki-zh-cn; do
    loading_progress "Menginstal $pkg"
    echo -e "${GREEN}$(opkg install $pkg 2>&1)${NC}"
  done
  if [ -z "$SRC_DIR" ]; then
    echo -e "${RED}Repository belum di-clone. Jalankan opsi clone_repo terlebih dahulu.${NC}"
    return
  fi
  mkdir -p /etc/nikki/ > /dev/null 2>&1
  mv "$SRC_DIR/blm.tar.gz" /etc/nikki/ > /dev/null 2>&1
  cd /etc/nikki/ || return
  tar -xzvf blm.tar.gz > /dev/null 2>&1
  loading_progress "Mengekstrak blm.tar.gz"
  echo -e "${GREEN}blm.tar.gz diekstrak.${NC}"
  mkdir -p /etc/nikki/run/proxy_provider/ > /dev/null 2>&1
  loading_progress "Membuat direktori proxy_provider"
  echo -e "${GREEN}Direktori proxy_provider dibuat.${NC}"
  base64 -d "$SRC_DIR/PID.txt" > /etc/nikki/run/proxy_provider/INDO.yaml
  loading_progress "Memperbarui INDO.yaml"
  echo -e "${GREEN}File INDO.yaml telah diperbarui.${NC}"
}

# ========================
# Fungsi 4: Update vnstat.db
# ========================
update_vnstat() {
  if [ -z "$SRC_DIR" ]; then
    echo -e "${RED}Repository belum di-clone. Jalankan opsi clone_repo terlebih dahulu.${NC}"
    return
  fi
  echo -e "${CYAN}Mengganti file vnstat.db dengan yang ada di repository...${NC}"
  mkdir -p /etc/vnstat > /dev/null 2>&1
  [ -f /etc/vnstat/vnstat.db ] && rm -f /etc/vnstat/vnstat.db
  mv "$SRC_DIR/vnstat.db" /etc/vnstat/ > /dev/null 2>&1
  loading_progress "Memindahkan vnstat.db"
  echo -e "${GREEN}File vnstat.db telah diganti.${NC}"
}

# ========================
# Fungsi 5: Update nlbwmon
# ========================
update_nlbwmon() {
  if [ -z "$SRC_DIR" ]; then
    echo -e "${RED}Repository belum di-clone. Jalankan opsi clone_repo terlebih dahulu.${NC}"
    return
  fi
  echo -e "${CYAN}Memperbarui file di /etc/nlbwmon/...${NC}"
  rm -rf /etc/nlbwmon/* > /dev/null 2>&1
  mkdir -p /etc/nlbwmon/ > /dev/null 2>&1
  cp -r "$SRC_DIR/etc/nlbwmon/"* /etc/nlbwmon/ > /dev/null 2>&1
  loading_progress "Memperbarui /etc/nlbwmon/"
  echo -e "${GREEN}File di /etc/nlbwmon/ telah diperbarui.${NC}"
}

# ========================
# Fungsi 6: Buat file nftables (FIX TTL 63)
# ========================
create_nftables() {
  echo -e "${CYAN}Membuat file /etc/nftables.d/11-ttl.nft (FIX TTL 63)...${NC}"
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
  /etc/init.d/firewall restart > /dev/null 2>&1
  loading_progress "Restarting firewall"
  echo -e "${GREEN}Firewall telah direstart.${NC}"
}

# ========================
# Fungsi 7: Pindahkan & Install mm.ipk dan tl.ipk
# ========================
install_ipk() {
  if [ -z "$SRC_DIR" ]; then
    echo -e "${RED}Repository belum di-clone. Jalankan opsi clone_repo terlebih dahulu.${NC}"
    return
  fi
  echo -e "${CYAN}Memindahkan mm.ipk dan tl.ipk ke /root dan instalasi...${NC}"
  mv "$SRC_DIR/mm.ipk" /root/ > /dev/null 2>&1
  loading_progress "Memindahkan mm.ipk"
  opkg install /root/mm.ipk > /dev/null 2>&1
  echo -e "${GREEN}mm.ipk diinstal.${NC}"
  mv "$SRC_DIR/tl.ipk" /root/ > /dev/null 2>&1
  loading_progress "Memindahkan tl.ipk"
  opkg install /root/tl.ipk > /dev/null 2>&1
  echo -e "${GREEN}tl.ipk diinstal.${NC}"
}

# ========================
# Fungsi 8: Instal paket tambahan & pip
# ========================
install_extra() {
  echo -e "${CYAN}Menginstal paket tambahan...${NC}"
  for pkg in luci-app-nlbwmon luci-app-cloudflared git-http python3-requests; do
    loading_progress "Menginstal $pkg"
    opkg install $pkg > /dev/null 2>&1
    echo -e "${GREEN}$pkg diinstal.${NC}"
  done
  loading_progress "pip3 install requests"
  pip3 install requests > /dev/null 2>&1
  echo -e "${GREEN}requests (pip3) diinstal.${NC}"
}

# ========================
# Fungsi 9: Tambah entri domain DHCP
# ========================
configure_dhcp_domains() {
  echo -e "${CYAN}Menambahkan entri domain di /etc/config/dhcp...${NC}"
  cat >> /etc/config/dhcp << EOF
config domain
    option name 'HP_IRFAN'
    option ip '192.168.1.245'

config domain
    option name 'HP_TAB'
    option ip '192.168.1.106'

config domain
    option name 'HP_ANITA'
    option ip '192.168.1.220'

config domain
    option name 'HP_AQILLA'
    option ip '192.168.1.122'

config domain
    option name 'HP_JAMAL'
    option ip '192.168.1.169'

config domain
    option name 'LAPTOP'
    option ip '192.168.1.123'

config domain
    option name 'HP_AMAT'
    option ip '192.168.1.166'

config domain
    option name 'HP_BAPAK'
    option ip '192.168.1.233'
EOF
  echo -e "${GREEN}Entri domain DHCP ditambahkan.${NC}"
}

# ========================
# Fungsi 10: Deploy scripts Telegram
# ========================
deploy_telegram() {
  echo -e "${CYAN}Menyalin dan memberikan izin untuk skrip Telegram...${NC}"
  cp "/usr/bin/online.sh" /usr/bin/ > /dev/null 2>&1
  cp "/usr/bin/send_telegram.py" /usr/bin/ > /dev/null 2>&1
  chmod +x /usr/bin/online.sh /usr/bin/send_telegram.py
  echo -e "${GREEN}Skrip Telegram siap digunakan.${NC}"
}

# ========================
# Fungsi 11: Deploy informasi LuCI
# ========================
deploy_informasi() {
  echo -e "${CYAN}Menyalin view/controller LuCI Informasi...${NC}"
  mkdir -p /usr/lib/lua/luci/view/informasi/ > /dev/null 2>&1
  cp "$SRC_DIR/usr/lib/lua/luci/view/informasi/"* /usr/lib/lua/luci/view/informasi/ > /dev/null 2>&1
  cp "$SRC_DIR/usr/lib/lua/luci/controller/informasi.lua" /usr/lib/lua/luci/controller/ > /dev/null 2>&1
  echo -e "${GREEN}LuCI Informasi dipasang.${NC}"
}

# ========================
# Fungsi 12: Deploy halaman WWW
# ========================
deploy_www_pages() {
  echo -e "${CYAN}Menyalin halaman WWW...${NC}"
  for page in display.html samsung.html vpn.html; do
    cp "$SRC_DIR/www/$page" /www/ > /dev/null 2>&1
    echo -e "${GREEN}$page dipindahkan.${NC}"
  done
}

# ========================
# Fungsi 13: Deploy CGI scripts
# ========================
deploy_cgi_scripts() {
  echo -e "${CYAN}Menyalin CGI scripts...${NC}"
  for script in online traffic pwm-fan-status; do
    cp "$SRC_DIR/www/cgi-bin/$script" /www/cgi-bin/ > /dev/null 2>&1
    chmod +x "/www/cgi-bin/$script"
    echo -e "${GREEN}$script dipindahkan dan dieksekusi.${NC}"
  done
}

# ========================
# Fungsi: Install semua langkah
# ========================
install_all() {
  install_update
  clone_repo
  install_nikki
  update_vnstat
  update_nlbwmon
  create_nftables
  install_ipk
  install_extra
  configure_dhcp_domains
  deploy_telegram
  deploy_informasi
  deploy_www_pages
  deploy_cgi_scripts
  remove_repo
}

# ========================
# Menu Utama
# ========================
main_menu() {
  install_update
  while true; do
    echo -e "${YELLOW}========== Menu Install ==========${NC}"
    echo -e "${YELLOW}1) Clone repository dan pindahkan file (Status Monitor)${NC}"
    echo -e "${YELLOW}2) Instal dan konfigurasi paket Nikki${NC}"
    echo -e "${YELLOW}3) Update vnstat.db${NC}"
    echo -e "${YELLOW}4) Update nlbwmon${NC}"
    echo -e "${YELLOW}5) Buat file nftables (FIX TTL 63)${NC}"
    echo -e "${YELLOW}6) Pindahkan & Install mm.ipk dan tl.ipk${NC}"
    echo -e "${YELLOW}7) Instal paket tambahan & pip${NC}"
    echo -e "${YELLOW}8) Tambah entri domain DHCP${NC}"
    echo -e "${YELLOW}9) Deploy skrip Telegram${NC}"
    echo -e "${YELLOW}10) Deploy LuCI Informasi${NC}"
    echo -e "${YELLOW}11) Deploy halaman WWW${NC}"
    echo -e "${YELLOW}12) Deploy CGI scripts${NC}"
    echo -e "${YELLOW}13) Install semuanya${NC}"
    echo -e "${YELLOW}14) Keluar${NC}"
    echo -ne "${CYAN}Pilih opsi [1-14]: ${NC}"
    read choice
    case $choice in
      1) clone_repo ;; 2) install_nikki ;; 3) update_vnstat ;; 4) update_nlbwmon ;; 5) create_nftables ;;
      6) install_ipk ;; 7) install_extra ;; 8) configure_dhcp_domains ;; 9) deploy_telegram ;;
      10) deploy_informasi ;; 11) deploy_www_pages ;; 12) deploy_cgi_scripts ;;
      13) install_all ;; 14) echo -e "${GREEN}Terima kasih. Keluar.${NC}"; exit 0 ;;
      *) echo -e "${RED}Pilihan tidak valid. Coba lagi.${NC}" ;;
    esac
    echo -e "${CYAN}Tekan Enter untuk kembali ke menu...${NC}"
    read
  done
}

# Mulai Program
main_menu
