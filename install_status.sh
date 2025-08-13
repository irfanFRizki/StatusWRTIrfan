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
  
  # Install basic packages
  for pkg in coreutils-sleep bc git git-http wget python3-requests python3-pip coreutils-base64; do
    loading_progress "Menginstal $pkg"
    echo -e "${GREEN}$(opkg install $pkg 2>&1)${NC}"
  done
  
  # Check and install luci-app-nlbwmon if not exists
  if ! opkg list-installed | grep -q "luci-app-nlbwmon"; then
    loading_progress "Menginstal luci-app-nlbwmon"
    opkg install luci-app-nlbwmon > /dev/null 2>&1
    echo -e "${GREEN}luci-app-nlbwmon diinstal.${NC}"
  else
    echo -e "${YELLOW}luci-app-nlbwmon sudah terinstal.${NC}"
  fi
  
  # Check and install luci-app-cloudflared if not exists
  if ! opkg list-installed | grep -q "luci-app-cloudflared"; then
    loading_progress "Menginstal luci-app-cloudflared"
    opkg install luci-app-cloudflared > /dev/null 2>&1
    echo -e "${GREEN}luci-app-cloudflared diinstal.${NC}"
  else
    echo -e "${YELLOW}luci-app-cloudflared sudah terinstal.${NC}"
  fi
  
  # Check /etc/vnstat directory and setup if not exists
  if [ ! -d "/etc/vnstat" ]; then
    echo -e "${CYAN}Direktori /etc/vnstat tidak ditemukan. Menjalankan setup vnstat...${NC}"
    wget --no-check-certificate -O /root/mahavpn-vnstatdb.sh "https://raw.githubusercontent.com/GboyGud/mahavpn/main/vnstat/mahavpn-vnstatdb.sh" > /dev/null 2>&1
    chmod +x /root/mahavpn-vnstatdb.sh
    loading_progress "Mendownload dan menjalankan vnstat setup"
    bash /root/mahavpn-vnstatdb.sh > /dev/null 2>&1
    echo -e "${GREEN}Setup vnstat selesai.${NC}"
  else
    echo -e "${YELLOW}Direktori /etc/vnstat sudah ada.${NC}"
  fi
}

# ========================
# Fungsi 2: Clone repository dan setup lengkap
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
  mkdir -p /usr/lib/lua/luci/view/informasi/ > /dev/null 2>&1
  loading_progress "Membuat direktori tujuan"
  echo -e "${GREEN}Direktori tujuan dibuat.${NC}"

  # Status Monitor files
  mv "$SRC_DIR/usr/lib/lua/luci/controller/status_monitor.lua" "$LUA_CTRL" > /dev/null 2>&1
  loading_progress "Memindahkan status_monitor.lua"
  echo -e "${GREEN}File status_monitor.lua dipindahkan.${NC}"

  mv "$SRC_DIR/usr/lib/lua/luci/view/status_monitor.htm" "$LUA_VIEW" > /dev/null 2>&1
  loading_progress "Memindahkan status_monitor.htm"
  echo -e "${GREEN}File status_monitor.htm dipindahkan.${NC}"

  # Install extra packages
  echo -e "${CYAN}Menginstal paket tambahan...${NC}"
  for pkg in python3-requests python3-pip; do
    loading_progress "Menginstal $pkg"
    opkg install "$pkg" > /dev/null 2>&1
    echo -e "${GREEN}$pkg diinstal.${NC}"
  done

  # Instalasi paket Python via pip3
  loading_progress "pip3 install requests"
  pip3 install requests > /dev/null 2>&1
  echo -e "${GREEN}requests (pip3) diinstal.${NC}"

  loading_progress "pip3 install websocket-client"
  pip3 install websocket-client > /dev/null 2>&1
  echo -e "${GREEN}websocket-client (pip3) diinstal.${NC}"

  # Configure DHCP domains
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

config domain
	option name 'CCTV'
	option ip '192.168.1.138'
EOF
  echo -e "${GREEN}Entri domain DHCP ditambahkan.${NC}"

  # Deploy Telegram scripts
  echo -e "${CYAN}Memindahkan dan memberikan izin untuk skrip Telegram...${NC}"
  SRC_TELEGRAM="$SRC_DIR/usr/bin"
  mv "$SRC_TELEGRAM/online.sh" /usr/bin/ > /dev/null 2>&1
  mv "$SRC_TELEGRAM/send_telegram.py" /usr/bin/ > /dev/null 2>&1
  mv "$SRC_TELEGRAM/checkIP.py" /usr/bin/ > /dev/null 2>&1
  mv "$SRC_TELEGRAM/vpn.py" /usr/bin/ > /dev/null 2>&1
  chmod +x /usr/bin/online.sh /usr/bin/send_telegram.py /usr/bin/checkIP.py /usr/bin/vpn.py
  echo -e "${GREEN}Skrip Telegram berhasil dipindahkan dan diaktifkan.${NC}"

  # Deploy LuCI Informasi
  echo -e "${CYAN}Memindahkan view/controller LuCI Informasi...${NC}"
  mv "$SRC_DIR/usr/lib/lua/luci/view/informasi/"* /usr/lib/lua/luci/view/informasi/ > /dev/null 2>&1
  mv "$SRC_DIR/usr/lib/lua/luci/controller/informasi.lua" /usr/lib/lua/luci/controller/ > /dev/null 2>&1
  echo -e "${GREEN}File LuCI Informasi berhasil dipindahkan ke sistem${NC}"

  # Deploy WWW pages
  echo -e "${CYAN}Memindahkan halaman WWW...${NC}"
  mv "$SRC_DIR/www/"*.html /www/ > /dev/null 2>&1
  echo -e "${GREEN}Semua file HTML berhasil dipindahkan ke /www${NC}"

  # Deploy CGI scripts
  echo -e "${CYAN}Memindahkan CGI scripts...${NC}"
  mv "$SRC_DIR/www/cgi-bin/"* /www/cgi-bin/ > /dev/null 2>&1
  chmod +x /www/cgi-bin/*
  echo -e "${GREEN}Semua script CGI berhasil dipindahkan dan diaktifkan${NC}"

  # Setup cron jobs
  echo -e "${CYAN}Mengatur cron jobs...${NC}"
  
  # Create crontab entries
  CRON_ENTRIES="# checkIP.py setiap 5 menit
*/5 * * * * /usr/bin/python3 /usr/bin/checkIP.py
# Backup notified_ips.log setiap hari jam 06:00
0 6 * * * cp /etc/notified_ips.log /etc/notified_ips_\$(date +\\%Y-\\%m-\\%d).bak && > /etc/notified_ips.log
# mwan3_check.py setiap menit
* * * * * /usr/bin/python3 /usr/bin/mwan3_check.py"

  # Add cron entries to crontab
  echo "$CRON_ENTRIES" | crontab -
  
  # Restart cron service
  /etc/init.d/cron restart > /dev/null 2>&1
  loading_progress "Mengatur cron jobs"
  echo -e "${GREEN}Cron jobs berhasil ditambahkan dan diaktifkan${NC}"
}

# ========================
# Fungsi 3: Update vnstat & nlbwmon
# ========================
update_data() {
  if [ -z "$SRC_DIR" ]; then
    echo -e "${RED}Repository belum di-clone. Jalankan opsi clone_repo terlebih dahulu.${NC}"
    return
  fi
  
  # Update vnstat.db
  echo -e "${CYAN}Mengganti file vnstat.db dengan yang ada di repository...${NC}"
  mkdir -p /etc/vnstat > /dev/null 2>&1
  [ -f /etc/vnstat/vnstat.db ] && rm -f /etc/vnstat/vnstat.db
  mv "$SRC_DIR/vnstat.db" /etc/vnstat/ > /dev/null 2>&1
  loading_progress "Memindahkan vnstat.db"
  echo -e "${GREEN}File vnstat.db telah diganti.${NC}"

  # Update nlbwmon
  echo -e "${CYAN}Memperbarui file di /etc/nlbwmon/...${NC}"
  rm -rf /etc/nlbwmon/* > /dev/null 2>&1
  mkdir -p /etc/nlbwmon/ > /dev/null 2>&1
  cp -r "$SRC_DIR/etc/nlbwmon/"* /etc/nlbwmon/ > /dev/null 2>&1
  loading_progress "Memperbarui /etc/nlbwmon/"
  echo -e "${GREEN}File di /etc/nlbwmon/ telah diperbarui.${NC}"
}

# ========================
# Fungsi 4: Buat file nftables (FIX TTL 63)
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
# Fungsi 5: Install semua .ipk
# ========================
install_ipk() {
  if [ -z "$SRC_DIR" ]; then
    echo -e "${RED}Repository belum di-clone. Jalankan opsi clone_repo terlebih dahulu.${NC}"
    return
  fi

  echo -e "${CYAN}Menginstal semua file .ipk di folder ipk...${NC}"
  
  IPK_DIR="$SRC_DIR/ipk"

  if [ ! -d "$IPK_DIR" ]; then
    echo -e "${RED}Direktori $IPK_DIR tidak ditemukan.${NC}"
    return
  fi

  for ipk_file in "$IPK_DIR"/*.ipk; do
    if [ -f "$ipk_file" ]; then
      loading_progress "Menginstal $(basename "$ipk_file")"
      opkg install "$ipk_file" > /dev/null 2>&1
      echo -e "${GREEN}$(basename "$ipk_file") berhasil diinstal${NC}"
    fi
  done
}

# ========================
# Fungsi: Install semua langkah
# ========================
install_all() {
  install_update
  clone_repo
  update_data
  create_nftables
  install_ipk
}

remove_repo() {
  rm -rf "$SRC_DIR"
  echo -e "${GREEN}Direktori repo dibersihkan.${NC}"
}

# ========================
# Menu Utama
# ========================
main_menu() {
  install_update
  while true; do
    echo -e "${YELLOW}========== Menu Install ==========${NC}"
    echo -e "${YELLOW}1) Clone repository dan setup lengkap${NC}"
    echo -e "${YELLOW}2) Update vnstat & nlbwmon${NC}"
    echo -e "${YELLOW}3) Buat file nftables (FIX TTL 63)${NC}"
    echo -e "${YELLOW}4) Install semua ipk${NC}"
    echo -e "${YELLOW}5) Install semuanya${NC}"
    echo -e "${YELLOW}6) Keluar${NC}"
    echo -ne "${CYAN}Pilih opsi [1-6]: ${NC}"
    read choice
    case $choice in
      1) clone_repo ;; 
      2) update_data ;; 
      3) create_nftables ;;
      4) install_ipk ;; 
      5) install_all ;; 
      6) echo -e "${GREEN}Terima kasih. Keluar.${NC}"; exit 0 ;;
      *) echo -e "${RED}Pilihan tidak valid. Coba lagi.${NC}" ;;
    esac
    echo -e "${CYAN}Tekan Enter untuk kembali ke menu...${NC}"
    read
  done
}

# Mulai Program
main_menu
