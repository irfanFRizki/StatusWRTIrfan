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
  colors=("$RED" "$YELLOW" "$GREEN" "$CYAN" "$BLUE" "$PURPLE")
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
  
  # Install dependencies
  for pkg in bc git git-http wget curl ash python3-requests; do
    loading_progress "Menginstal $pkg"
    opkg install $pkg > /dev/null 2>&1
    echo -e "${GREEN}$pkg terinstal.${NC}"
  done
  
  # Install Python requests via pip3
  loading_progress "Menginstal pip3 requests"
  pip3 install requests > /dev/null 2>&1
  echo -e "${GREEN}requests (pip3) terinstal.${NC}"
}

# ========================
# Fungsi 2: Clone repository & Pindahkan file
# ========================
clone_repo() {
  echo -e "${CYAN}Meng-clone repository StatusWRTIrfan...${NC}"
  cd /root || return
  git clone https://github.com/irfanFRizki/StatusWRTIrfan.git > /dev/null 2>&1
  loading_progress "Meng-clone repository"
  echo -e "${GREEN}Clone repository selesai.${NC}"

  SRC_DIR="/root/StatusWRTIrfan"
  LUA_CTRL="/usr/lib/lua/luci/controller"
  LUA_VIEW="/usr/lib/lua/luci/view"
  CGI_BIN="/www/cgi-bin"
  WWW_DIR="/www"

  mkdir -p "$LUA_CTRL" "$LUA_VIEW/informasi" "$CGI_BIN" "$WWW_DIR" > /dev/null 2>&1

  # Pindahkan status monitor
  mv "$SRC_DIR/usr/lib/lua/luci/controller/status_monitor.lua" "$LUA_CTRL/" > /dev/null 2>&1
  mv "$SRC_DIR/usr/lib/lua/luci/view/status_monitor.htm" "$LUA_VIEW/" > /dev/null 2>&1

  # Pindahkan skrip utama
  mv "$SRC_DIR/usr/bin/online.sh" /usr/bin/online.sh > /dev/null 2>&1
  mv "$SRC_DIR/usr/bin/send_telegram.py" /usr/bin/send_telegram.py > /dev/null 2>&1

  # Pindahkan CGI scripts
  for script in load_biaya minggu1 minggu2 minggu3 minggu4 mingguterakhir pemakaian save_biaya status online traffic pwm-fan-status; do
    mv "$SRC_DIR/www/cgi-bin/$script" "$CGI_BIN/" > /dev/null 2>&1
  done

  # Pindahkan view/controller informasi
  for view in allowed.htm info.htm informasi.htm log.htm notallowed.htm settings.htm telegram.htm; do
    mv "$SRC_DIR/usr/lib/lua/luci/view/informasi/$view" "$LUA_VIEW/informasi/" > /dev/null 2>&1
  done
  mv "$SRC_DIR/usr/lib/lua/luci/controller/informasi.lua" "$LUA_CTRL/" > /dev/null 2>&1

  # Pindahkan halaman statis WWW
  for page in display.html samsung.html vpn.html; do
    mv "$SRC_DIR/www/$page" "$WWW_DIR/" > /dev/null 2>&1
  done

  chmod +x /usr/bin/online.sh /usr/bin/send_telegram.py "$CGI_BIN/online" "$CGI_BIN/traffic" "$CGI_BIN/pwm-fan-status" > /dev/null 2>&1
  loading_progress "Memindahkan dan set izin file"

  /etc/init.d/uhttpd restart > /dev/null 2>&1
  loading_progress "Restarting uhttpd"
  echo -e "${GREEN}Clone & setup file selesai.${NC}"
}

# ========================
# Fungsi 3: Instal & Konfigurasi Nikki
# ========================
install_nikki() {
  echo -e "${CYAN}Memulai instalasi paket Nikki...${NC}"
  curl -sL https://github.com/nikkinikki-org/OpenWrt-nikki/raw/refs/heads/main/feed.sh | ash > /dev/null 2>&1
  loading_progress "Feed script nikki"
  for pkg in nikki luci-app-nikki luci-i18n-nikki-zh-cn; do
    opkg install $pkg > /dev/null 2>&1
    loading_progress "Menginstal $pkg"
  done

  if [ -z "$SRC_DIR" ]; then
    echo -e "${RED}Repository belum di-clone. Jalankan opsi clone terlebih dahulu.${NC}"
    return
  fi
  mkdir -p /etc/nikki/run/proxy_provider > /dev/null 2>&1
  mv "$SRC_DIR/blm.tar.gz" /etc/nikki/ > /dev/null 2>&1
  cd /etc/nikki || return
  tar -xzvf blm.tar.gz > /dev/null 2>&1
  base64 -d "$SRC_DIR/PID.txt" > /etc/nikki/run/proxy_provider/INDO.yaml
  loading_progress "Setup Nikki selesai"
}

# ========================
# Fungsi 4: Update vnstat.db
# ========================
update_vnstat() {
  if [ -z "$SRC_DIR" ]; then
    echo -e "${RED}Clone repo dulu (opsi 1).${NC}"; return
  fi
  echo -e "${CYAN}Mengganti vnstat.db...${NC}"
  mkdir -p /etc/vnstat
  rm -f /etc/vnstat/vnstat.db
  mv "$SRC_DIR/vnstat.db" /etc/vnstat/ > /dev/null 2>&1
  loading_progress "vnstat.db diganti"
}

# ========================
# Fungsi 5: Update nlbwmon
# ========================
update_nlbwmon() {
  if [ -z "$SRC_DIR" ]; then
    echo -e "${RED}Clone repo dulu (opsi 1).${NC}"; return
  fi
  echo -e "${CYAN}Updating nlbwmon...${NC}"
  rm -rf /etc/nlbwmon/*
  mkdir -p /etc/nlbwmon
  cp -r "$SRC_DIR/etc/nlbwmon/"* /etc/nlbwmon/
  loading_progress "nlbwmon updated"
}

# ========================
# Fungsi 6: Buat file nftables (FIX TTL 63)
# ========================
create_nftables() {
  echo -e "${CYAN}Membuat konfigurasi nftables...${NC}"
  mkdir -p /etc/nftables.d
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
  /etc/init.d/firewall restart > /dev/null 2>&1
  loading_progress "nftables created & firewall restarted"
}

# ========================
# Fungsi 7: Instal mm.ipk & tl.ipk
# ========================
install_mm_tl() {
  echo -e "${CYAN}Memindahkan & instal mm.ipk & tl.ipk...${NC}"
  if [ -z "$SRC_DIR" ]; then
    echo -e "${RED}Clone repo dulu (opsi 1).${NC}"; return
  fi
  mv "$SRC_DIR/mm.ipk" /root/ > /dev/null 2>&1
  mv "$SRC_DIR/tl.ipk" /root/ > /dev/null 2>&1
  opkg install /root/mm.ipk /root/tl.ipk > /dev/null 2>&1
  loading_progress "mm.ipk & tl.ipk installed"
}

# ========================
# Fungsi 8: Instal Luci Apps tambahan
# ========================
install_luci_apps() {
  echo -e "${CYAN}Menginstal luci-app-nlbwmon & cloudflared...${NC}"
  opkg install luci-app-nlbwmon > /dev/null 2>&1; loading_progress "luci-app-nlbwmon"
  opkg install luci-app-cloudflared > /dev/null 2>&1; loading_progress "luci-app-cloudflared"
}

# ========================
# Fungsi 9: Update DHCP Config
# ========================
update_dhcp_config() {
  echo -e "${CYAN}Menambahkan static DHCP...${NC}"
  cat << 'EOF' >> /etc/config/dhcp

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
  loading_progress "Static DHCP ditambahkan"
}

# ========================
# Fungsi 10: Konfigurasi ttyd
# ========================
configure_ttyd() {
  echo -e "${CYAN}Mengonfigurasi ttyd...${NC}"
  sed -i "s|option command .*|option command='\/bin\/login -f root'|" /etc/config/ttyd
  /etc/init.d/ttyd restart > /dev/null 2>&1
  loading_progress "ttyd diupdate"
}

# ========================
# Fungsi 11: Hapus folder repository
# ========================
remove_repo() {
  if [ -n "$SRC_DIR" ]; then
    rm -rf "$SRC_DIR"
    loading_progress "Menghapus folder repository"
    SRC_DIR=""
  else
    echo -e "${YELLOW}Belum ada repo untuk dihapus.${NC}"
  fi
}

# ========================
# Fungsi 12: Install semuanya
# ========================
install_all() {
  clone_repo
  install_nikki
  update_vnstat
  update_nlbwmon
  create_nftables
  install_mm_tl
  install_luci_apps
  update_dhcp_config
  configure_ttyd
  remove_repo
}

# ========================
# Menu Utama
# ========================
main_menu() {
  install_update
  while true; do
    echo -e "${YELLOW}======== Menu Install ========${NC}"
    echo -e "${YELLOW}1) Clone repo & setup files${NC}"
    echo -e "${YELLOW}2) Instal Nikki${NC}"
    echo -e "${YELLOW}3) Update vnstat.db${NC}"
    echo -e "${YELLOW}4) Update nlbwmon${NC}"
    echo -e "${YELLOW}5) Buat nftables TTL fix${NC}"
    echo -e "${YELLOW}6) Instal mm.ipk & tl.ipk${NC}"
    echo -e "${YELLOW}7) Instal Luci-app tambahan${NC}"
    echo -e "${YELLOW}8) Update DHCP Config${NC}"
    echo -e "${YELLOW}9) Konfigurasi ttyd${NC}"
    echo -e "${YELLOW}10) Hapus repo${NC}"
    echo -e "${YELLOW}11) Install semuanya${NC}"
    echo -e "${YELLOW}12) Keluar${NC}"
    echo -ne "${CYAN}Pilih [1-12]: ${NC}"; read choice
    case $choice in
      1) clone_repo ;; 2) install_nikki ;; 3) update_vnstat ;; 4) update_nlbwmon ;; 5) create_nftables ;;
      6) install_mm_tl ;; 7) install_luci_apps ;; 8) update_dhcp_config ;; 9) configure_ttyd ;;
      10) remove_repo ;; 11) install_all ;; 12) echo -e "${GREEN}Selesai.${NC}"; exit 0 ;;
      *) echo -e "${RED}Pilihan tidak valid.${NC}" ;;
    esac
    echo -e "${CYAN}Tekan Enter untuk kembali...${NC}"; read
  done
}

# Jalankan program
main_menu
