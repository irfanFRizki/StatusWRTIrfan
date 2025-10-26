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
# Fungsi untuk cek apakah package sudah terinstall
# ========================
check_package_installed() {
  local pkg_name="$1"
  if opkg list-installed | grep -q "^${pkg_name} "; then
    return 0  # terinstall
  else
    return 1  # belum terinstall
  fi
}

# ========================
# Fungsi untuk cek apakah python package sudah terinstall
# ========================
check_python_package_installed() {
  local pkg_name="$1"
  if pip3 list | grep -i "^${pkg_name} " >/dev/null 2>&1; then
    return 0  # terinstall
  else
    return 1  # belum terinstall
  fi
}

# ========================
# Fungsi Decode Credentials
# ========================
decode_credentials() {
  # Encoded credentials (base64)
  local encoded_data="$1"
  echo "$encoded_data" | base64 -d
}

# Encrypted bot credentials
AUTOIP_BOT_DATA="NzgzNzU4NTUxMzpBQUhtSDkzM1Y1ZmIxN1dzejdDTktVWk9zLXFnU2xMX0NCaw=="
AUTOIP_CHAT_DATA="NTY0NTUzNzAyMg=="
MAHABOT_BOT_DATA="ODQxNjgxNDM5NDpBQUdOUU9ZRWtldHcyME54UjduQTlMdEtRcjVjTWszYm9VVQ=="
MAHABOT_CHAT_DATA="NTY0NTUzNzAyMg=="
CLOUDFLARED_TOKEN_DATA="ZXlKaElqb2lNekEyTURNNVpEUTNaalZqTURCa09EWTBZVE13TldVeU1EQmhOVEl3Wm1VaUxDSjBJam9pTm1NMk16VXhOelV0TldFMllpMDBOelJrTFRnMllqY3RaakJpTVRRNU5XVm1OV1kxSWl3aWN5STZJazlIVlRCT2JVa3pUVzFSZEZwRWF6Qk5lVEF3VG5wTmVFeFVhM2RQVkZWMFQwUmpOVnBIU1hsT2VrcHRXVlJSZVNKOQ=="

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
# Fungsi Konfirmasi
# ========================
ask_confirmation() {
  local message="$1"
  while true; do
    echo -ne "${YELLOW}$message [y/n]: ${NC}"
    read -r answer
    case $answer in
      [Yy]|[Yy][Ee][Ss]) return 0 ;;
      [Nn]|[Nn][Oo]) return 1 ;;
      *) echo -e "${RED}Masukkan y (yes) atau n (no)${NC}" ;;
    esac
  done
}

# ========================
# Fungsi 1: Update paket, Install dependensi & Clone Repository
# ========================
update_and_clone() {
  echo -e "${CYAN}=== STEP 1: Update paket, instalasi dependensi & Clone Repository ===${NC}"
  
  # Update packages
  echo -e "${CYAN}Memperbarui daftar paket...${NC}"
  opkg update > /dev/null 2>&1
  loading_progress "Updating paket"
  echo -e "${GREEN}Update paket selesai.${NC}"
  
  # Install basic packages with check
  echo -e "${CYAN}Menginstal paket dasar...${NC}"
  packages=("coreutils-sleep" "bc" "git" "git-http" "wget" "python3-requests" "python3-pip" "coreutils-base64")
  for pkg in "${packages[@]}"; do
    if check_package_installed "$pkg"; then
      echo -e "${YELLOW}$pkg sudah terinstall, melewati instalasi.${NC}"
    else
      loading_progress "Menginstal $pkg"
      if opkg install "$pkg" > /dev/null 2>&1; then
        echo -e "${GREEN}$pkg berhasil diinstal.${NC}"
      else
        echo -e "${RED}Gagal menginstal $pkg.${NC}"
      fi
    fi
  done
  
  # Install PHP8 packages
  echo -e "${CYAN}Menginstal paket PHP8...${NC}"
  php8_packages=(
    "php8"
    "php8-cgi"
    "php8-cli"
    "php8-mod-curl"
    "php8-mod-mbstring"
    "php8-mod-session"
    "php8-mod-json"
    "php8-mod-openssl"
    "php8-mod-pdo"
    "php8-mod-pdo-sqlite"
    "php8-mod-sqlite3"
    "php8-mod-xml"
    "php8-mod-zip"
  )
  
  for pkg in "${php8_packages[@]}"; do
    if check_package_installed "$pkg"; then
      echo -e "${YELLOW}$pkg sudah terinstall, melewati instalasi.${NC}"
    else
      loading_progress "Menginstal $pkg"
      if opkg install "$pkg" > /dev/null 2>&1; then
        echo -e "${GREEN}$pkg berhasil diinstal.${NC}"
      else
        echo -e "${YELLOW}$pkg tidak tersedia atau gagal diinstal.${NC}"
      fi
    fi
  done
  
  # Check and install luci apps
  if check_package_installed "luci-app-nlbwmon"; then
    echo -e "${YELLOW}luci-app-nlbwmon sudah terinstall.${NC}"
  else
    loading_progress "Menginstal luci-app-nlbwmon"
    if opkg install luci-app-nlbwmon > /dev/null 2>&1; then
      echo -e "${GREEN}luci-app-nlbwmon berhasil diinstal.${NC}"
    else
      echo -e "${RED}Gagal menginstal luci-app-nlbwmon.${NC}"
    fi
  fi
  
  if check_package_installed "luci-app-cloudflared"; then
    echo -e "${YELLOW}luci-app-cloudflared sudah terinstall.${NC}"
  else
    loading_progress "Menginstal luci-app-cloudflared"
    if opkg install luci-app-cloudflared > /dev/null 2>&1; then
      echo -e "${GREEN}luci-app-cloudflared berhasil diinstal.${NC}"
    else
      echo -e "${RED}Gagal menginstal luci-app-cloudflared.${NC}"
    fi
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
  
  # Install extra packages with check
  echo -e "${CYAN}Menginstal paket tambahan...${NC}"
  extra_packages=("python3-requests" "python3-pip")
  for pkg in "${extra_packages[@]}"; do
    if check_package_installed "$pkg"; then
      echo -e "${YELLOW}$pkg sudah terinstall, melewati instalasi.${NC}"
    else
      loading_progress "Menginstal $pkg"
      if opkg install "$pkg" > /dev/null 2>&1; then
        echo -e "${GREEN}$pkg berhasil diinstal.${NC}"
      else
        echo -e "${RED}Gagal menginstal $pkg.${NC}"
      fi
    fi
  done

  # Instalasi paket Python via pip3 with check
  echo -e "${CYAN}Menginstal paket Python...${NC}"
  python_packages=("requests" "websocket-client")
  for pkg in "${python_packages[@]}"; do
    if check_python_package_installed "$pkg"; then
      echo -e "${YELLOW}$pkg (pip3) sudah terinstall, melewati instalasi.${NC}"
    else
      loading_progress "pip3 install $pkg"
      if pip3 install "$pkg" > /dev/null 2>&1; then
        echo -e "${GREEN}$pkg (pip3) berhasil diinstal.${NC}"
      else
        echo -e "${RED}Gagal menginstal $pkg (pip3).${NC}"
      fi
    fi
  done
  
  # Clone repository
  echo -e "${CYAN}Meng-clone repository StatusWRTIrfan...${NC}"
  cd /root || return
  
  # Remove existing directory if exists
  if [ -d "/root/StatusWRTIrfan" ]; then
    echo -e "${YELLOW}Direktori StatusWRTIrfan sudah ada, menghapus...${NC}"
    rm -rf /root/StatusWRTIrfan
  fi
  
  git clone https://github.com/irfanFRizki/StatusWRTIrfan.git > /dev/null 2>&1
  loading_progress "Meng-clone repository"
  echo -e "${GREEN}Clone repository selesai.${NC}"
  SRC_DIR="/root/StatusWRTIrfan"
  
  echo -e "${GREEN}✓ STEP 1 SELESAI${NC}\n"
}

# ========================
# Fungsi 2: Setup Repository (Deploy files & configurations)
# ========================
setup_repository() {
  echo -e "${CYAN}=== STEP 2: Setup Repository (Deploy & Configure) ===${NC}"
  
  if [ -z "$SRC_DIR" ] || [ ! -d "$SRC_DIR" ]; then
    echo -e "${RED}Repository belum di-clone. Tidak dapat melanjutkan setup.${NC}"
    return 1
  fi

  # Direktori tujuan
  LUA_CTRL="/usr/lib/lua/luci/controller/"
  LUA_VIEW="/usr/lib/lua/luci/view/"
  CGI_BIN="/www/cgi-bin/"
  WWW_DIR="/www/"
  mkdir -p "$LUA_CTRL" "$LUA_VIEW" "$CGI_BIN" "$WWW_DIR" > /dev/null 2>&1
  mkdir -p /usr/lib/lua/luci/view/informasi/ > /dev/null 2>&1
  loading_progress "Membuat direktori tujuan"
  echo -e "${GREEN}Direktori tujuan dibuat.${NC}"

  # Configure DHCP domains
  echo -e "${CYAN}Menambahkan entri domain dari repository...${NC}"
  if [ -f "$SRC_DIR/etc/config/dhcp" ]; then
    grep -A 2 "^config domain" "$SRC_DIR/etc/config/dhcp" | grep -v "^--$" >> /etc/config/dhcp
    loading_progress "Menambahkan entri domain DHCP"
    echo -e "${GREEN}Entri domain DHCP dari repository berhasil ditambahkan.${NC}"
  else
    echo -e "${YELLOW}File dhcp config tidak ditemukan di repository.${NC}"
  fi

  # Deploy Telegram scripts
  echo -e "${CYAN}Memindahkan dan memberikan izin untuk skrip Telegram...${NC}"
  SRC_TELEGRAM="$SRC_DIR/usr/bin"
  mv "$SRC_TELEGRAM/online.sh" /usr/bin/ > /dev/null 2>&1
  mv "$SRC_TELEGRAM/send_telegram.py" /usr/bin/ > /dev/null 2>&1
  mv "$SRC_TELEGRAM/checkIP.py" /usr/bin/ > /dev/null 2>&1
  mv "$SRC_TELEGRAM/vpn.py" /usr/bin/ > /dev/null 2>&1
  mv "$SRC_TELEGRAM/vnstat-backup.sh" /usr/bin/ > /dev/null 2>&1
  chmod +x /usr/bin/online.sh /usr/bin/send_telegram.py /usr/bin/checkIP.py /usr/bin/vpn.py /usr/bin/vnstat-backup.sh 2>/dev/null
  echo -e "${GREEN}Skrip Telegram berhasil dipindahkan dan diaktifkan.${NC}"

  # Configure GitHub Token for vnstat-backup.sh
  echo -e "${CYAN}Mengonfigurasi GitHub token di vnstat-backup.sh...${NC}"
  if [ -f "/usr/bin/vnstat-backup.sh" ]; then
    sed -i 's/GITHUB_TOKEN_ENCODED="Isi pesan ini di pesan tersimpan telegram"/GITHUB_TOKEN_ENCODED="Z2hwX1V5THZmNVNuVUgyRTJUZHFwZXpEb2ZObHhTMUI4UTQxdXVtZg=="/' /usr/bin/vnstat-backup.sh
    loading_progress "Mengonfigurasi GitHub token"
    echo -e "${GREEN}GitHub token berhasil dikonfigurasi di vnstat-backup.sh${NC}"
  else
    echo -e "${YELLOW}File /usr/bin/vnstat-backup.sh tidak ditemukan. Melewati konfigurasi GitHub token.${NC}"
  fi
  
  # Deploy WWW pages
  echo -e "${CYAN}Memindahkan halaman WWW...${NC}"
  mv "$SRC_DIR/www/"*.html /www/ > /dev/null 2>&1
  echo -e "${GREEN}Semua file HTML berhasil dipindahkan ke /www${NC}"

  # Deploy CGI scripts
  echo -e "${CYAN}Memindahkan CGI scripts...${NC}"
  mv "$SRC_DIR/www/cgi-bin/"* /www/cgi-bin/ > /dev/null 2>&1
  chmod +x /www/cgi-bin/* 2>/dev/null
  echo -e "${GREEN}Semua script CGI berhasil dipindahkan dan diaktifkan${NC}"

  # Move /www/game directory
  echo -e "${CYAN}Memindahkan direktori /www/game...${NC}"
  if [ -d "$SRC_DIR/www/game" ]; then
    mkdir -p /www/game > /dev/null 2>&1
    mv "$SRC_DIR/www/game/"* /www/game/ > /dev/null 2>&1
    loading_progress "Memindahkan direktori game ke /www/game"
    echo -e "${GREEN}Direktori game berhasil dipindahkan ke /www/game${NC}"
  else
    echo -e "${YELLOW}Direktori www/game tidak ditemukan di repository${NC}"
  fi

  # Move /root/game directory
  echo -e "${CYAN}Memindahkan direktori /root/game...${NC}"
  if [ -d "$SRC_DIR/root/game" ]; then
    mkdir -p /root/game > /dev/null 2>&1
    mv "$SRC_DIR/root/game/"* /root/game/ > /dev/null 2>&1
    loading_progress "Memindahkan direktori game ke /root/game"
    echo -e "${GREEN}Direktori game berhasil dipindahkan ke /root/game${NC}"
  else
    echo -e "${YELLOW}Direktori root/game tidak ditemukan di repository${NC}"
  fi

  # Setup cron jobs
  echo -e "${CYAN}Mengatur cron jobs...${NC}"
  
  EXISTING_CRON=$(crontab -l 2>/dev/null || echo "")
  
  NEW_ENTRIES=(
    "*/5 * * * * /usr/bin/python3 /usr/bin/checkIP.py"
    "0 6 * * * cp /etc/notified_ips.log /etc/notified_ips_\$(date +\\%Y-\\%m-\\%d).bak && > /etc/notified_ips.log"
    "* * * * * /usr/bin/python3 /usr/bin/mwan3_check.py"
	"0 * * * * /usr/bin/vnstat-backup.sh"
	"0 0 * * * /opt/data-monitor/run.sh --collect # data-monitor daily collection"
	"0 7 * * * /opt/data-monitor/run.sh --send # data-monitor scheduled report"
  )
  
  TEMP_CRON="/tmp/temp_cron"
  
  if [ -n "$EXISTING_CRON" ]; then
    echo "$EXISTING_CRON" > "$TEMP_CRON"
  else
    touch "$TEMP_CRON"
  fi
  
  for entry in "${NEW_ENTRIES[@]}"; do
    cmd_part=$(echo "$entry" | sed 's/^[^ ]* [^ ]* [^ ]* [^ ]* [^ ]* //')
    
    if ! grep -Fq "$cmd_part" "$TEMP_CRON" 2>/dev/null; then
      echo "$entry" >> "$TEMP_CRON"
      echo -e "${GREEN}Menambahkan cron job: $cmd_part${NC}"
    else
      echo -e "${YELLOW}Cron job sudah ada: $cmd_part${NC}"
    fi
  done
  
  crontab "$TEMP_CRON"
  rm -f "$TEMP_CRON"
  
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
    sed -i '/option region/d' /etc/config/cloudflared 2>/dev/null
    sed -i '/config cloudflared/,/^$/ { /config cloudflared/a\
	option region '\''us'\''
    }' /etc/config/cloudflared 2>/dev/null
    echo -e "${GREEN}Region 'us' ditambahkan ke konfigurasi cloudflared${NC}"
  else
    echo -e "${YELLOW}Region 'us' sudah dikonfigurasi${NC}"
  fi

  # Configure cloudflared token
  echo -e "${CYAN}Mengonfigurasi cloudflared token...${NC}"
  
  TARGET_TOKEN=$(decode_credentials "$CLOUDFLARED_TOKEN_DATA")
  
  if ! grep -q "option token '$TARGET_TOKEN'" /etc/config/cloudflared 2>/dev/null; then
    sed -i '/option token/d' /etc/config/cloudflared 2>/dev/null
    sed -i "/config cloudflared/,/^$/ { /config cloudflared/a\\
	option token '$TARGET_TOKEN'
    }" /etc/config/cloudflared 2>/dev/null
    echo -e "${GREEN}Token ditambahkan ke konfigurasi cloudflared${NC}"
  else
    echo -e "${YELLOW}Token sudah dikonfigurasi${NC}"
  fi

  # Configure cloudflared enabled option
  echo -e "${CYAN}Mengonfigurasi cloudflared enabled option...${NC}"
  if ! grep -q "option enabled '1'" /etc/config/cloudflared 2>/dev/null; then
    sed -i '/option enabled/d' /etc/config/cloudflared 2>/dev/null
    sed -i '/config cloudflared/,/^$/ { /config cloudflared/a\
	option enabled '\''1'\''
    }' /etc/config/cloudflared 2>/dev/null
    echo -e "${GREEN}Enabled '1' ditambahkan ke konfigurasi cloudflared${NC}"
  else
    echo -e "${YELLOW}Enabled '1' sudah dikonfigurasi${NC}"
  fi

  # Restart cloudflared service
  echo -e "${CYAN}Merestart layanan cloudflared...${NC}"
  /etc/init.d/cloudflared restart > /dev/null 2>&1
  loading_progress "Restarting cloudflared service"
  echo -e "${GREEN}Layanan cloudflared telah direstart.${NC}"

  # Configure nlbwmon database directory
  echo -e "${CYAN}Mengonfigurasi nlbwmon database directory...${NC}"
  if ! grep -q "option database_directory '/etc/nlbwmon'" /etc/config/nlbwmon 2>/dev/null; then
    sed -i '/option database_directory/d' /etc/config/nlbwmon 2>/dev/null
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

  # Configure /etc/config/autoip_rakitan
  echo -e "${CYAN}Mengonfigurasi /etc/config/autoip_rakitan...${NC}"
  if [ -f "/etc/config/autoip_rakitan" ]; then
    echo -e "${YELLOW}File /etc/config/autoip_rakitan sudah ada. Mengisi bagian yang kosong...${NC}"
    
    AUTOIP_BOT_TOKEN=$(decode_credentials "$AUTOIP_BOT_DATA")
    AUTOIP_CHAT_ID=$(decode_credentials "$AUTOIP_CHAT_DATA")
    
    sed -i "s/option port_modem ''/option port_modem '\/dev\/ttyUSB0'/" /etc/config/autoip_rakitan
    sed -i "s/option device_name ''/option device_name 'wwan0'/" /etc/config/autoip_rakitan  
    sed -i "s/option interface_name ''/option interface_name 'mm'/" /etc/config/autoip_rakitan
    sed -i "s/option parameter_type ''/option parameter_type 'httping'/" /etc/config/autoip_rakitan
    sed -i "s/option bot_token ''/option bot_token '$AUTOIP_BOT_TOKEN'/" /etc/config/autoip_rakitan
    sed -i "s/option chat_id ''/option chat_id '$AUTOIP_CHAT_ID'/" /etc/config/autoip_rakitan
    
    loading_progress "Mengisi konfigurasi autoip_rakitan"
    echo -e "${GREEN}Konfigurasi autoip_rakitan telah diperbarui${NC}"
  else
    echo -e "${YELLOW}File /etc/config/autoip_rakitan tidak ditemukan. Melewati konfigurasi.${NC}"
  fi

  # Configure /etc/config/mahabotwrt
  echo -e "${CYAN}Mengonfigurasi /etc/config/mahabotwrt...${NC}"
  if [ -f "/etc/config/mahabotwrt" ]; then
    echo -e "${YELLOW}File /etc/config/mahabotwrt sudah ada. Mengisi bagian yang kosong...${NC}"
    
    MAHABOT_BOT_TOKEN=$(decode_credentials "$MAHABOT_BOT_DATA")
    MAHABOT_CHAT_ID=$(decode_credentials "$MAHABOT_CHAT_DATA")
    
    sed -i "s/option bot_token ''/option bot_token '$MAHABOT_BOT_TOKEN'/" /etc/config/mahabotwrt
    sed -i "s/option chat_id ''/option chat_id '$MAHABOT_CHAT_ID'/" /etc/config/mahabotwrt
    
    loading_progress "Mengisi konfigurasi mahabotwrt"
    echo -e "${GREEN}Konfigurasi mahabotwrt telah diperbarui${NC}"
  else
    echo -e "${YELLOW}File /etc/config/mahabotwrt tidak ditemukan. Melewati konfigurasi.${NC}"
  fi
  
  echo -e "${GREEN}✓ STEP 2 SELESAI${NC}\n"
}

# ========================
# Fungsi 3: Update vnstat & nlbwmon
# ========================
update_data() {
  echo -e "${CYAN}=== STEP 3: Update vnstat & nlbwmon ===${NC}"
  
  if [ -z "$SRC_DIR" ] || [ ! -d "$SRC_DIR" ]; then
    echo -e "${RED}Repository belum di-clone. Melewati update data.${NC}"
    return 1
  fi
  
  # Update vnstat.db
  echo -e "${CYAN}Mengganti file vnstat.db dengan yang ada di repository...${NC}"
  mkdir -p /etc/vnstat > /dev/null 2>&1
  [ -f /etc/vnstat/vnstat.db ] && rm -f /etc/vnstat/vnstat.db
  if [ -f "$SRC_DIR/etc/vnstat/vnstat.db" ]; then
    mv "$SRC_DIR/etc/vnstat/vnstat.db" /etc/vnstat/ > /dev/null 2>&1
    loading_progress "Memindahkan vnstat.db"
    echo -e "${GREEN}File vnstat.db telah diganti.${NC}"
  else
    echo -e "${YELLOW}File vnstat.db tidak ditemukan di repository.${NC}"
  fi

  # Update nlbwmon
  echo -e "${CYAN}Memperbarui file di /etc/nlbwmon/...${NC}"
  if [ -d "$SRC_DIR/etc/nlbwmon" ]; then
    rm -rf /etc/nlbwmon/* > /dev/null 2>&1
    mkdir -p /etc/nlbwmon/ > /dev/null 2>&1
    mv "$SRC_DIR/etc/nlbwmon/"* /etc/nlbwmon/ > /dev/null 2>&1
    loading_progress "Memperbarui /etc/nlbwmon/"
    echo -e "${GREEN}File di /etc/nlbwmon/ telah diperbarui.${NC}"
  else
    echo -e "${YELLOW}Direktori nlbwmon tidak ditemukan di repository.${NC}"
  fi

  # Restart services
  echo -e "${CYAN}Merestart layanan vnstat dan nlbwmon...${NC}"
  /etc/init.d/vnstat restart > /dev/null 2>&1
  loading_progress "Restarting vnstat service"
  echo -e "${GREEN}Layanan vnstat telah direstart.${NC}"
  
  /etc/init.d/nlbwmon restart > /dev/null 2>&1
  loading_progress "Restarting nlbwmon service"
  echo -e "${GREEN}Layanan nlbwmon telah direstart.${NC}"
  
  echo -e "${GREEN}✓ STEP 3 SELESAI${NC}\n"
}

# ========================
# Fungsi 4: Buat file nftables (FIX TTL 65)
# ========================
create_nftables() {
  echo -e "${CYAN}=== STEP 4: Buat file nftables (FIX TTL 65) ===${NC}"
  
  current_ttl_check=$(nft list ruleset | grep "ip ttl set" 2>/dev/null || echo "")
  
  if echo "$current_ttl_check" | grep -q "ip ttl set 65"; then
    echo -e "${YELLOW}TTL sudah diset ke 65. Tidak perlu mengubah konfigurasi.${NC}"
  else
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
  fi
  
  echo -e "${GREEN}✓ STEP 4 SELESAI${NC}\n"
}

# ========================
# Fungsi 5: Install semua .ipk
# ========================
install_ipk() {
  echo -e "${CYAN}=== STEP 5: Install semua .ipk ===${NC}"
  
  if [ -z "$SRC_DIR" ] || [ ! -d "$SRC_DIR" ]; then
    echo -e "${RED}Repository belum di-clone. Melewati instalasi IPK.${NC}"
    return 1
  fi
  
  IPK_DIR="$SRC_DIR/ipk"

  if [ ! -d "$IPK_DIR" ]; then
    echo -e "${YELLOW}Direktori $IPK_DIR tidak ditemukan. Melewati instalasi IPK.${NC}"
  else
    for ipk_file in "$IPK_DIR"/*.ipk; do
      if [ -f "$ipk_file" ]; then
        pkg_basename=$(basename "$ipk_file")
        pkg_name=$(echo "$pkg_basename" | sed 's/_.*\.ipk$//')
        
        if check_package_installed "$pkg_name"; then
          echo -e "${YELLOW}$pkg_basename sudah terinstall, melewati instalasi.${NC}"
        else
          loading_progress "Menginstal $pkg_basename"
          if opkg install "$ipk_file" > /dev/null 2>&1; then
            echo -e "${GREEN}$pkg_basename berhasil diinstal${NC}"
          else
            echo -e "${RED}Gagal menginstal $pkg_basename${NC}"
          fi
        fi
      fi
    done
  fi
  
  echo -e "${GREEN}✓ STEP 5 SELESAI${NC}\n"
}

# ========================
# Fungsi 6: Install semua .ipk di folder /mm
# ========================
install_ipk_mm() {
  echo -e "${CYAN}=== STEP 6: Install semua .ipk di folder /mm ===${NC}"
  
  if [ -z "$SRC_DIR" ] || [ ! -d "$SRC_DIR" ]; then
    echo -e "${RED}Repository belum di-clone. Melewati instalasi IPK MM.${NC}"
    return 1
  fi
  
  IPK_MM_DIR="$SRC_DIR/mm"

  if [ ! -d "$IPK_MM_DIR" ]; then
    echo -e "${YELLOW}Direktori $IPK_MM_DIR tidak ditemukan. Melewati instalasi IPK MM.${NC}"
  else
    for ipk_file in "$IPK_MM_DIR"/*.ipk; do
      if [ -f "$ipk_file" ]; then
        pkg_basename=$(basename "$ipk_file")
        pkg_name=$(echo "$pkg_basename" | sed 's/_.*\.ipk$//')
        
        if check_package_installed "$pkg_name"; then
          echo -e "${YELLOW}$pkg_basename sudah terinstall, melewati instalasi.${NC}"
        else
          loading_progress "Menginstal $pkg_basename"
          if opkg install "$ipk_file" > /dev/null 2>&1; then
            echo -e "${GREEN}$pkg_basename berhasil diinstal${NC}"
          else
            echo -e "${RED}Gagal menginstal $pkg_basename${NC}"
          fi
        fi
      fi
    done
  fi
  
  echo -e "${GREEN}✓ STEP 6 SELESAI${NC}\n"
}

# ========================
# Fungsi 7: Install dan jalankan speedtest-telebot
# ========================
install_speedtest_telebot() {
  echo -e "${CYAN}=== STEP 7: Install dan jalankan speedtest-telebot ===${NC}"
  
  if [ -z "$SRC_DIR" ] || [ ! -d "$SRC_DIR" ]; then
    echo -e "${RED}Repository belum di-clone. Melewati instalasi speedtest-telebot.${NC}"
    return 1
  fi
  
  SPEEDTEST_SCRIPT="$SRC_DIR/root/install-speedtest-telebot.sh"

  if [ ! -f "$SPEEDTEST_SCRIPT" ]; then
    echo -e "${YELLOW}File install-speedtest-telebot.sh tidak ditemukan. Melewati instalasi speedtest-telebot.${NC}"
  else
    chmod +x "$SPEEDTEST_SCRIPT"
    loading_progress "Memberikan permission pada script"
    echo -e "${GREEN}Permission execute berhasil diberikan pada script${NC}"

    echo -e "${CYAN}Menjalankan script install-speedtest-telebot.sh...${NC}"
    loading_progress "Memulai instalasi speedtest-telebot"
    
    if bash "$SPEEDTEST_SCRIPT"; then
      echo -e "${GREEN}Script install-speedtest-telebot.sh berhasil dijalankan${NC}"
    else
      echo -e "${RED}Terjadi error saat menjalankan script install-speedtest-telebot.sh${NC}"
      echo -e "${YELLOW}Periksa output di atas untuk detail error${NC}"
    fi
  fi
  
  echo -e "${GREEN}✓ STEP 7 SELESAI${NC}\n"
}

# ========================
# Fungsi 8: Install LuCI Informasi Jaringan
# ========================
install_luci_informasi() {
  echo -e "${CYAN}=== STEP 8: Install LuCI Informasi Jaringan ===${NC}"
  
  if [ -z "$SRC_DIR" ] || [ ! -d "$SRC_DIR" ]; then
    echo -e "${RED}Repository belum di-clone. Melewati instalasi LuCI Informasi.${NC}"
    return 1
  fi
  
  echo -e "${CYAN}Memindahkan view/controller LuCI Informasi...${NC}"
  
  if [ -d "$SRC_DIR/usr/lib/lua/luci/view/informasi" ]; then
    mkdir -p /usr/lib/lua/luci/view/informasi/ > /dev/null 2>&1
    mv "$SRC_DIR/usr/lib/lua/luci/view/informasi/"* /usr/lib/lua/luci/view/informasi/ > /dev/null 2>&1
    loading_progress "Memindahkan view informasi"
    echo -e "${GREEN}View LuCI Informasi berhasil dipindahkan${NC}"
  else
    echo -e "${YELLOW}Direktori view/informasi tidak ditemukan di repository${NC}"
  fi
  
  if [ -f "$SRC_DIR/usr/lib/lua/luci/controller/informasi.lua" ]; then
    mkdir -p /usr/lib/lua/luci/controller/ > /dev/null 2>&1
    mv "$SRC_DIR/usr/lib/lua/luci/controller/informasi.lua" /usr/lib/lua/luci/controller/ > /dev/null 2>&1
    loading_progress "Memindahkan controller informasi"
    echo -e "${GREEN}Controller LuCI Informasi berhasil dipindahkan${NC}"
  else
    echo -e "${YELLOW}File controller/informasi.lua tidak ditemukan di repository${NC}"
  fi
  
  echo -e "${CYAN}Merestart layanan uhttpd...${NC}"
  /etc/init.d/uhttpd restart > /dev/null 2>&1
  loading_progress "Restarting uhttpd service"
  echo -e "${GREEN}Layanan uhttpd telah direstart${NC}"
  
  echo -e "${GREEN}✓ STEP 8 SELESAI${NC}\n"
}

# ========================
# Fungsi 9: Install opt/data-monitor
# ========================
install_data_monitor() {
  echo -e "${CYAN}=== STEP 9: Install opt/data-monitor ===${NC}"
  
  if [ -z "$SRC_DIR" ] || [ ! -d "$SRC_DIR" ]; then
    echo -e "${RED}Repository belum di-clone. Melewati instalasi data-monitor.${NC}"
    return 1
  fi
  
  echo -e "${CYAN}Memindahkan direktori /opt/data-monitor...${NC}"
  if [ -d "$SRC_DIR/opt/data-monitor" ]; then
    mkdir -p /opt/ > /dev/null 2>&1
    [ -d "/opt/data-monitor" ] && rm -rf /opt/data-monitor
    mv "$SRC_DIR/opt/data-monitor" /opt/ > /dev/null 2>&1
    loading_progress "Memindahkan direktori data-monitor"
    
    if [ -d "/opt/data-monitor" ]; then
      find /opt/data-monitor -type f -name "*.sh" -exec chmod +x {} \; 2>/dev/null
      find /opt/data-monitor -type f -name "*.py" -exec chmod +x {} \; 2>/dev/null
      echo -e "${GREEN}Direktori data-monitor berhasil dipindahkan ke /opt/data-monitor${NC}"
      echo -e "${GREEN}Permission execute berhasil diberikan pada script${NC}"
    fi
  else
    echo -e "${YELLOW}Direktori data-monitor tidak ditemukan di repository${NC}"
  fi
  
  echo -e "${GREEN}✓ STEP 9 SELESAI${NC}\n"
}

# ========================
# Fungsi: Install semua langkah
# ========================
install_all() {
  echo -e "${PURPLE}╔════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${PURPLE}║                 MEMULAI INSTALASI LENGKAP                  ║${NC}"  
  echo -e "${PURPLE}╚════════════════════════════════════════════════════════════╝${NC}\n"
  
  # Step 1: Update and Clone (Always run without confirmation)
  echo -e "${CYAN}Memulai Update Paket & Clone Repository...${NC}\n"
  update_and_clone
  
  # Check if clone was successful
  if [ -z "$SRC_DIR" ] || [ ! -d "$SRC_DIR" ]; then
    echo -e "${RED}Clone repository gagal. Instalasi dibatalkan.${NC}"
    return 1
  fi
  
  echo -e "\n${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║    Repository berhasil di-clone dan paket di-update!      ║${NC}"
  echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}\n"
  
  # Ask if user wants to continue with installation of other components
  echo -e "${CYAN}Tersedia komponen tambahan untuk diinstal:${NC}"
  echo -e "${YELLOW}  2. Setup Repository (Deploy & Configure)${NC}"
  echo -e "${YELLOW}  3. Update vnstat & nlbwmon${NC}"
  echo -e "${YELLOW}  4. Buat file nftables (FIX TTL 65)${NC}"
  echo -e "${YELLOW}  5. Install semua paket IPK${NC}"
  echo -e "${YELLOW}  6. Install paket IPK dari folder /mm${NC}"
  echo -e "${YELLOW}  7. Install dan jalankan speedtest-telebot${NC}"
  echo -e "${YELLOW}  8. Install LuCI Informasi Jaringan${NC}"
  echo -e "${YELLOW}  9. Install opt/data-monitor${NC}\n"
  
  if ! ask_confirmation "Apakah Anda ingin melanjutkan instalasi komponen tambahan?"; then
    echo -e "${YELLOW}Instalasi komponen tambahan dibatalkan.${NC}"
    echo -e "${CYAN}Hanya Update Paket & Clone Repository yang berhasil dijalankan.${NC}\n"
    return 0
  fi
  
  echo -e "\n${GREEN}Melanjutkan instalasi komponen tambahan...${NC}\n"
  
  # Step 2: Setup Repository
  if ask_confirmation "Install Setup Repository (Deploy & Configure)?"; then
    setup_repository
  else
    echo -e "${YELLOW}Setup Repository dilewati.${NC}\n"
  fi
  
  # Step 3: Update vnstat & nlbwmon
  if ask_confirmation "Install Update vnstat & nlbwmon?"; then
    update_data
  else
    echo -e "${YELLOW}Update vnstat & nlbwmon dilewati.${NC}\n"
  fi
  
  # Step 4: Create nftables
  if ask_confirmation "Install file nftables (FIX TTL 65)?"; then
    create_nftables
  else
    echo -e "${YELLOW}Pembuatan nftables dilewati.${NC}\n"
  fi
  
  # Step 5: Install IPK
  if ask_confirmation "Install semua paket IPK?"; then
    install_ipk
  else
    echo -e "${YELLOW}Install IPK dilewati.${NC}\n"
  fi
  
  # Step 6: Install IPK MM
  if ask_confirmation "Install paket IPK dari folder /mm?"; then
    install_ipk_mm
  else
    echo -e "${YELLOW}Install IPK MM dilewati.${NC}\n"
  fi
  
  # Step 7: Install speedtest-telebot
  if ask_confirmation "Install dan jalankan speedtest-telebot?"; then
    install_speedtest_telebot
  else
    echo -e "${YELLOW}Install speedtest-telebot dilewati.${NC}\n"
  fi
  
  # Step 8: Install LuCI Informasi
  if ask_confirmation "Install LuCI Informasi Jaringan?"; then
    install_luci_informasi
  else
    echo -e "${YELLOW}Install LuCI Informasi dilewati.${NC}\n"
  fi
  
  # Step 9: Install data-monitor
  if ask_confirmation "Install opt/data-monitor?"; then
    install_data_monitor
  else
    echo -e "${YELLOW}Install data-monitor dilewati.${NC}\n"
  fi
  
  echo -e "${PURPLE}╔════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${PURPLE}║                 INSTALASI BERHASIL DISELESAIKAN            ║${NC}"
  echo -e "${PURPLE}╚════════════════════════════════════════════════════════════╝${NC}"
}

# ========================
# Fungsi: Cleanup repository
# ========================
cleanup_repo() {
  if [ -d "$SRC_DIR" ]; then
    echo -e "${CYAN}Membersihkan direktori repository...${NC}"
    rm -rf "$SRC_DIR"
    loading_progress "Menghapus direktori repository"
    echo -e "${GREEN}Direktori repository telah dibersihkan.${NC}"
    SRC_DIR=""
  fi
}

# ========================
# Menu Utama - One Click Install
# ========================
main_menu() {
  echo -e "${PURPLE}╔════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${PURPLE}║                     ONE CLICK INSTALLER                    ║${NC}"
  echo -e "${PURPLE}║                   StatusWRT OpenWrt Setup                  ║${NC}"
  echo -e "${PURPLE}╚════════════════════════════════════════════════════════════╝${NC}\n"
  
  echo -e "${CYAN}Script ini akan menginstal dan mengkonfigurasi:${NC}"
  echo -e "${GREEN}• Update paket sistem dan dependensi (termasuk PHP8) - OTOMATIS${NC}"
  echo -e "${GREEN}• Clone repository StatusWRTIrfan - OTOMATIS${NC}"
  echo -e "${YELLOW}• Setup repository (Deploy & Configure) - dengan konfirmasi${NC}"
  echo -e "${YELLOW}• Update vnstat & nlbwmon database - dengan konfirmasi${NC}"
  echo -e "${YELLOW}• Konfigurasi nftables (TTL 65) - dengan konfirmasi${NC}"
  echo -e "${YELLOW}• Install semua paket IPK - dengan konfirmasi${NC}"
  echo -e "${YELLOW}• Install paket IPK dari folder /mm - dengan konfirmasi${NC}"
  echo -e "${YELLOW}• Install dan jalankan speedtest-telebot - dengan konfirmasi${NC}"
  echo -e "${YELLOW}• Install LuCI Informasi Jaringan - dengan konfirmasi${NC}"
  echo -e "${YELLOW}• Install opt/data-monitor - dengan konfirmasi${NC}"
  echo -e "${YELLOW}• Pindahkan folder game (/www/game dan /root/game)${NC}"
  echo -e "${YELLOW}• Konfigurasi cloudflared, telegram bot, dan lainnya${NC}\n"
  
  echo -e "${RED}PERINGATAN: ${NC}${YELLOW}Pastikan router terhubung ke internet!${NC}\n"
  echo -e "${CYAN}INFO: ${NC}${GREEN}Update & Clone repository akan berjalan otomatis.${NC}"
  echo -e "${GREEN}Setelah itu, setiap komponen akan meminta konfirmasi sebelum instalasi.${NC}\n"
  
  if ask_confirmation "Apakah Anda ingin memulai instalasi?"; then
    echo -e "\n${GREEN}Memulai instalasi...${NC}\n"
    install_all
    
    echo -e "\n${CYAN}Instalasi selesai!${NC}"
    
    if ask_confirmation "Apakah Anda ingin membersihkan file temporary?"; then
      cleanup_repo
    else
      echo -e "${YELLOW}File temporary tetap ada di: $SRC_DIR${NC}"
    fi
  else
    echo -e "${RED}Instalasi dibatalkan oleh user.${NC}"
  fi
}

# ========================
# Jalankan Script
# ========================
main_menu
