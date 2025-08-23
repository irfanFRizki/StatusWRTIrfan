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
  
  # Get existing crontab
  EXISTING_CRON=$(crontab -l 2>/dev/null || echo "")
  
  # Define new cron entries to add
  NEW_ENTRIES=(
    "*/5 * * * * /usr/bin/python3 /usr/bin/checkIP.py"
    "0 6 * * * cp /etc/notified_ips.log /etc/notified_ips_\$(date +\\%Y-\\%m-\\%d).bak && > /etc/notified_ips.log"
    "* * * * * /usr/bin/python3 /usr/bin/mwan3_check.py"
  )
  
  # Create temporary cron file
  TEMP_CRON="/tmp/temp_cron"
  
  # Add existing cron entries first
  if [ -n "$EXISTING_CRON" ]; then
    echo "$EXISTING_CRON" > "$TEMP_CRON"
  else
    touch "$TEMP_CRON"
  fi
  
  # Add new entries only if they don't already exist
  for entry in "${NEW_ENTRIES[@]}"; do
    # Extract the command part for checking (everything after the time specification)
    cmd_part=$(echo "$entry" | sed 's/^[^ ]* [^ ]* [^ ]* [^ ]* [^ ]* //')
    
    if ! grep -Fq "$cmd_part" "$TEMP_CRON" 2>/dev/null; then
      echo "$entry" >> "$TEMP_CRON"
      echo -e "${GREEN}Menambahkan cron job: $cmd_part${NC}"
    else
      echo -e "${YELLOW}Cron job sudah ada: $cmd_part${NC}"
    fi
  done
  
  # Install the updated crontab
  crontab "$TEMP_CRON"
  rm -f "$TEMP_CRON"
  
  # Restart cron service
  /etc/init.d/cron restart > /dev/null 2>&1
  loading_progress "Mengatur cron jobs"
  echo -e "${GREEN}Cron jobs berhasil ditambahkan dan diaktifkan${NC}"

  # Move cloudflared certificate
  echo -e "${CYAN}Memindahkan cloudflared certificate...${NC}"
  mkdir -p /etc/cloudflared/ > /dev/null 2>&1
  if [ -f "$SRC_DIR/etc/cloudflared/cert.pem" ]; then
    mv "$SRC_DIR/etc/cloudflared/cert.pem" /etc/cloudflared/cert.pem > /dev/null 2>&1
    loading_progress "Memindahkan cert.pem"
    echo -e "${GREEN}cert.pem berhasil dipindahkan ke /etc/cloudflared/${NC}"
  else
    echo -e "${YELLOW}File cert.pem tidak ditemukan di repository${NC}"
  fi

  # Configure cloudflared region
  echo -e "${CYAN}Mengonfigurasi cloudflared region...${NC}"
  if ! grep -q "option region 'us'" /etc/config/cloudflared 2>/dev/null; then
    # Remove existing region line if exists
    sed -i '/option region/d' /etc/config/cloudflared 2>/dev/null
    # Add region option to the first config cloudflared section
    sed -i '/config cloudflared/,/^$/ { /config cloudflared/a\
	option region '\''us'\''
    }' /etc/config/cloudflared 2>/dev/null
    echo -e "${GREEN}Region 'us' ditambahkan ke konfigurasi cloudflared${NC}"
  else
    echo -e "${YELLOW}Region 'us' sudah dikonfigurasi${NC}"
  fi

  # Configure cloudflared token
  echo -e "${CYAN}Mengonfigurasi cloudflared token...${NC}"
  TARGET_TOKEN="eyJhIjoiMzA2MDM5ZDQ3ZjVjMDBkODY0YTMwNWUyMDBhNTIwZmUiLCJ0IjoiNmM2MzUxNzUtNWE2Yi00NzRkLTg2YjctZjBiMTQ5NWVmNWY1IiwicyI6Ik9HVTBObUkzTW1RdFpEazBNeTAwTnpNeExUa3dPVFV0T0RjNVpHSXlOekptWVRReSJ9"
  if ! grep -q "option token '$TARGET_TOKEN'" /etc/config/cloudflared 2>/dev/null; then
    # Remove existing token line if exists
    sed -i '/option token/d' /etc/config/cloudflared 2>/dev/null
    # Add token option to the first config cloudflared section
    sed -i "/config cloudflared/,/^$/ { /config cloudflared/a\\
	option token '$TARGET_TOKEN'
    }" /etc/config/cloudflared 2>/dev/null
    echo -e "${GREEN}Token ditambahkan ke konfigurasi cloudflared${NC}"
  else
    echo -e "${YELLOW}Token sudah dikonfigurasi${NC}"
  fi

  # Configure nlbwmon database directory
  echo -e "${CYAN}Mengonfigurasi nlbwmon database directory...${NC}"
  if ! grep -q "option database_directory '/etc/nlbwmon'" /etc/config/nlbwmon 2>/dev/null; then
    # Remove existing database_directory line if exists
    sed -i '/option database_directory/d' /etc/config/nlbwmon 2>/dev/null
    # Add database_directory option to the first config nlbwmon section
    sed -i '/config nlbwmon/,/^$/ { /config nlbwmon/a\
	option database_directory '\''/etc/nlbwmon'\''
    }' /etc/config/nlbwmon 2>/dev/null
    echo -e "${GREEN}Database directory '/etc/nlbwmon' ditambahkan ke konfigurasi nlbwmon${NC}"
  else
    echo -e "${YELLOW}Database directory '/etc/nlbwmon' sudah dikonfigurasi${NC}"
  fi

  # Move VPN configuration
  echo -e "${CYAN}Memindahkan konfigurasi VPN...${NC}"
  if [ -d "$SRC_DIR/etc/vpn" ]; then
    mkdir -p /etc/ > /dev/null 2>&1
    mv "$SRC_DIR/etc/vpn" /etc/ > /dev/null 2>&1
    loading_progress "Memindahkan direktori VPN"
    echo -e "${GREEN}Direktori VPN berhasil dipindahkan ke /etc/vpn${NC}"
  else
    echo -e "${YELLOW}Direktori VPN tidak ditemukan di repository${NC}"
  fi

  # Move IP configuration files
  echo -e "${CYAN}Memindahkan file konfigurasi IP...${NC}"
  if [ -f "$SRC_DIR/etc/allowed_ips.conf" ]; then
    mv "$SRC_DIR/etc/allowed_ips.conf" /etc/allowed_ips.conf > /dev/null 2>&1
    loading_progress "Memindahkan allowed_ips.conf"
    echo -e "${GREEN}allowed_ips.conf berhasil dipindahkan ke /etc/${NC}"
  else
    echo -e "${YELLOW}File allowed_ips.conf tidak ditemukan di repository${NC}"
  fi

  if [ -f "$SRC_DIR/etc/kicked_ips.conf" ]; then
    mv "$SRC_DIR/etc/kicked_ips.conf" /etc/kicked_ips.conf > /dev/null 2>&1
    loading_progress "Memindahkan kicked_ips.conf"
    echo -e "${GREEN}kicked_ips.conf berhasil dipindahkan ke /etc/${NC}"
  else
    echo -e "${YELLOW}File kicked_ips.conf tidak ditemukan di repository${NC}"
  fi
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
  mv "$SRC_DIR/etc/nlbwmon/"* /etc/nlbwmon/ > /dev/null 2>&1
  loading_progress "Memperbarui /etc/nlbwmon/"
  echo -e "${GREEN}File di /etc/nlbwmon/ telah diperbarui.${NC}"

  # Restart services
  echo -e "${CYAN}Merestart layanan vnstat dan nlbwmon...${NC}"
  /etc/init.d/vnstat restart > /dev/null 2>&1
  loading_progress "Restarting vnstat service"
  echo -e "${GREEN}Layanan vnstat telah direstart.${NC}"
  
  /etc/init.d/nlbwmon restart > /dev/null 2>&1
  loading_progress "Restarting nlbwmon service"
  echo -e "${GREEN}Layanan nlbwmon telah direstart.${NC}"
}

# ========================
# Fungsi 4: Buat file nftables (FIX TTL 63)
# ========================
create_nftables() {
  echo -e "${CYAN}Memeriksa konfigurasi TTL saat ini...${NC}"
  
  # Check current TTL setting
  current_ttl_check=$(nft list ruleset | grep "ip ttl set" 2>/dev/null || echo "")
  
  if echo "$current_ttl_check" | grep -q "ip ttl set 65"; then
    echo -e "${YELLOW}TTL sudah diset ke 65. Tidak perlu mengubah konfigurasi.${NC}"
    return
  fi
  
  if [[ -n "$current_ttl_check" ]] && ! echo "$current_ttl_check" | grep -q "ip ttl set 65"; then
    echo -e "${YELLOW}TTL saat ini tidak diset ke 65. Melanjutkan konfigurasi...${NC}"
  else
    echo -e "${CYAN}Tidak ada konfigurasi TTL ditemukan. Membuat konfigurasi baru...${NC}"
  fi
  
  echo -e "${CYAN}Membuat file /etc/nftables.d/11-ttl.nft (FIX TTL 65)...${NC}"
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
  echo -e "${GREEN}Firewall telah direstart dengan TTL 65.${NC}"
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
    echo -e "${CYAN}Info: Anda dapat memilih beberapa opsi dengan format: 1,3,4 atau 1,2${NC}"
    echo -ne "${CYAN}Pilih opsi [1-6] atau kombinasi: ${NC}"
    read choice
    
    # Handle exit first
    if [[ "$choice" == "6" ]]; then
      echo -e "${GREEN}Terima kasih. Keluar.${NC}"; 
      exit 0
    fi
    
    # Handle single or multiple choices
    if [[ "$choice" =~ ^[1-6](,[1-6])*$ ]]; then
      # Split choices by comma
      IFS=',' read -ra CHOICES <<< "$choice"
      
      # Execute each choice
      for selected in "${CHOICES[@]}"; do
        case $selected in
          1) echo -e "${BLUE}Menjalankan: Clone repository dan setup lengkap${NC}"; clone_repo ;; 
          2) echo -e "${BLUE}Menjalankan: Update vnstat & nlbwmon${NC}"; update_data ;; 
          3) echo -e "${BLUE}Menjalankan: Buat file nftables (FIX TTL 63)${NC}"; create_nftables ;;
          4) echo -e "${BLUE}Menjalankan: Install semua ipk${NC}"; install_ipk ;; 
          5) echo -e "${BLUE}Menjalankan: Install semuanya${NC}"; install_all ;; 
          6) echo -e "${GREEN}Terima kasih. Keluar.${NC}"; exit 0 ;;
          *) echo -e "${RED}Pilihan $selected tidak valid.${NC}" ;;
        esac
      done
    else
      echo -e "${RED}Format tidak valid. Gunakan angka 1-6 atau kombinasi seperti 1,3,4${NC}"
    fi
    
    echo -e "${CYAN}Tekan Enter untuk kembali ke menu...${NC}"
    read
  done
}

# Mulai Program
main_menu
