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
  echo -e "${CYAN}Memulai konfigurasi Nikki proxy provider...${NC}"
  curl -s -L https://github.com/nikkinikki-org/OpenWrt-nikki/raw/refs/heads/main/feed.sh | ash > /dev/null 2>&1
  loading_progress "Menjalankan feed script nikki"
  echo -e "${GREEN}Feed script nikki selesai dijalankan.${NC}"
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
  base64 -d "$SRC_DIR/PSG.txt" > /etc/nikki/run/proxy_provider/SGP.yaml
  loading_progress "Memperbarui SGP.yaml"
  echo -e "${GREEN}File SGP.yaml telah diperbarui.${NC}"
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
# Fungsi 7: Install mm.ipk dan tl.ipk langsung dari repo
# ========================
install_ipk() {
  if [ -z "$SRC_DIR" ]; then
    echo -e "${RED}Repository belum di-clone. Jalankan opsi clone_repo terlebih dahulu.${NC}"
    return
  fi
  
  echo -e "${CYAN}Menginstal mm.ipk dan tl.ipk langsung dari repository...${NC}"
  
  loading_progress "Menginstal mm.ipk"
  opkg install "$SRC_DIR/root/mm.ipk" > /dev/null 2>&1
  echo -e "${GREEN}mm.ipk berhasil diinstal${NC}"
  
  loading_progress "Menginstal tl.ipk" 
  opkg install "$SRC_DIR/root/tl.ipk" > /dev/null 2>&1
  echo -e "${GREEN}tl.ipk berhasil diinstal${NC}"
  
  # Hapus file ipk dari repo jika diperlukan
  # rm -f "$SRC_DIR/root/mm.ipk" "$SRC_DIR/root/tl.ipk"
}

# ========================
# Fungsi 8: Instal paket tambahan & pip
# ========================
install_extra() {
  echo -e "${CYAN}Menginstal paket tambahan...${NC}"
  for pkg in git-http python3-requests; do
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
    option ip '192.168.1.177'

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
# Fungsi 10: Deploy scripts Telegram (Menggunakan MV)
# ========================
deploy_telegram() {
  if [ -z "$SRC_DIR" ]; then
    echo -e "${RED}Repository belum di-clone. Jalankan opsi clone_repo terlebih dahulu.${NC}"
    return
  fi
  
  echo -e "${CYAN}Memindahkan dan memberikan izin untuk skrip Telegram...${NC}"
  
  # File sumber di repository
  SRC_TELEGRAM="$SRC_DIR/usr/bin"
  
  # Pindahkan file dari repo ke /usr/bin
  mv "$SRC_TELEGRAM/online.sh" /usr/bin/ > /dev/null 2>&1
  mv "$SRC_TELEGRAM/send_telegram.py" /usr/bin/ > /dev/null 2>&1
  
  # Berikan izin eksekusi
  chmod +x /usr/bin/online.sh /usr/bin/send_telegram.py
  
  echo -e "${GREEN}Skrip Telegram berhasil dipindahkan dan diaktifkan.${NC}"
}

# ========================
# Fungsi 11: Deploy informasi LuCI (Menggunakan MV)
# ========================
deploy_informasi() {
  if [ -z "$SRC_DIR" ]; then
    echo -e "${RED}Repository belum di-clone. Jalankan opsi clone_repo terlebih dahulu.${NC}"
    return
  fi
  
  echo -e "${CYAN}Memindahkan view/controller LuCI Informasi...${NC}"
  
  # Buat direktori tujuan jika belum ada
  mkdir -p /usr/lib/lua/luci/view/informasi/ > /dev/null 2>&1
  
  # Pindahkan file view
  mv "$SRC_DIR/usr/lib/lua/luci/view/informasi/"* /usr/lib/lua/luci/view/informasi/ > /dev/null 2>&1
  
  # Pindahkan file controller
  mv "$SRC_DIR/usr/lib/lua/luci/controller/informasi.lua" /usr/lib/lua/luci/controller/ > /dev/null 2>&1
  
  echo -e "${GREEN}File LuCI Informasi berhasil dipindahkan ke sistem${NC}"
}

# ========================
# Fungsi 12: Deploy halaman WWW (Menggunakan MV)
# ========================
deploy_www_pages() {
  if [ -z "$SRC_DIR" ]; then
    echo -e "${RED}Repository belum di-clone. Jalankan opsi clone_repo terlebih dahulu.${NC}"
    return
  fi
  
  echo -e "${CYAN}Memindahkan halaman WWW...${NC}"
  # Pindahkan semua file html dari repo ke /www
  mv "$SRC_DIR/www/"*.html /www/ > /dev/null 2>&1
  echo -e "${GREEN}Semua file HTML berhasil dipindahkan ke /www${NC}"
}

# ========================
# Fungsi 13: Deploy CGI scripts (Menggunakan MV)
# ========================
deploy_cgi_scripts() {
  if [ -z "$SRC_DIR" ]; then
    echo -e "${RED}Repository belum di-clone. Jalankan opsi clone_repo terlebih dahulu.${NC}"
    return
  fi
  
  echo -e "${CYAN}Memindahkan CGI scripts...${NC}"
  # Pindahkan seluruh isi direktori cgi-bin dari repo
  mv "$SRC_DIR/www/cgi-bin/"* /www/cgi-bin/ > /dev/null 2>&1
  
  # Berikan izin eksekusi ke semua file
  chmod +x /www/cgi-bin/*
  
  echo -e "${GREEN}Semua script CGI berhasil dipindahkan dan diaktifkan${NC}"
}

# ========================
# Fungsi 14: Deploy nikki_monitor.sh dan tambahkan ke rc.local
# ========================
deploy_nikki_monitor() {
  if [ -z "$SRC_DIR" ]; then
    echo -e "${RED}Repository belum di-clone. Jalankan opsi clone_repo terlebih dahulu.${NC}"
    return
  fi

  echo -e "${CYAN}Memindahkan nikki_monitor.sh ke /root...${NC}"
  mv "$SRC_DIR/root/nikki_monitor.sh" /root/ > /dev/null 2>&1
  chmod +x /root/nikki_monitor.sh
  echo -e "${GREEN}nikki_monitor.sh berhasil dipindahkan dan diaktifkan.${NC}"

  echo -e "${CYAN}Menambahkan nikki_monitor.sh ke /etc/rc.local...${NC}"
  # Cek apakah sudah ada
  if grep -q "nikki_monitor.sh" /etc/rc.local; then
    echo -e "${YELLOW}nikki_monitor.sh sudah ada di rc.local.${NC}"
  else
    # Tambahkan sebelum 'exit 0'
    sed -i '/exit 0/d' /etc/rc.local
    echo -e "/root/nikki_monitor.sh 15 10 &" >> /etc/rc.local
    echo "exit 0" >> /etc/rc.local
    echo -e "${GREEN}Berhasil ditambahkan ke rc.local.${NC}"
  fi
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
  deploy_nikki_monitor
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
    echo -e "${YELLOW}13) Deploy nikki_monitor.sh${NC}"
    echo -e "${YELLOW}14) Install semuanya${NC}"
    echo -e "${YELLOW}15) Keluar${NC}"
    echo -ne "${CYAN}Pilih opsi [1-15]: ${NC}"
    read choice
    case $choice in
      1) clone_repo ;; 2) install_nikki ;; 3) update_vnstat ;; 4) update_nlbwmon ;; 5) create_nftables ;;
      6) install_ipk ;; 7) install_extra ;; 8) configure_dhcp_domains ;; 9) deploy_telegram ;;
      10) deploy_informasi ;; 11) deploy_www_pages ;; 12) deploy_cgi_scripts ;;
      13) deploy_nikki_monitor ;; 14) install_all ;; 15) echo -e "${GREEN}Terima kasih. Keluar.${NC}"; exit 0 ;;
      *) echo -e "${RED}Pilihan tidak valid. Coba lagi.${NC}" ;;
    esac
    echo -e "${CYAN}Tekan Enter untuk kembali ke menu...${NC}"
    read
  done
}

# Mulai Program
main_menu
