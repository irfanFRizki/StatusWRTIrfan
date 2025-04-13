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
# Fungsi 1: Update paket & instal dependensi
# ========================
install_update() {
  echo -e "${CYAN}Memulai update paket dan instalasi dependensi...${NC}"
  opkg update > /dev/null 2>&1
  loading_progress "Updating paket"
  echo -e "${GREEN}Update paket selesai.${NC}"
  
  local pkg
  pkg=$(opkg install bc 2>&1)
  loading_progress "Menginstal bc"
  echo -e "${GREEN}${pkg}${NC}"
  
  pkg=$(opkg install git 2>&1)
  loading_progress "Menginstal git"
  echo -e "${GREEN}${pkg}${NC}"
  
  pkg=$(opkg install git-http 2>&1)
  loading_progress "Menginstal git-http"
  echo -e "${GREEN}${pkg}${NC}"
  
  pkg=$(opkg install wget 2>&1)
  loading_progress "Menginstal wget"
  echo -e "${GREEN}${pkg}${NC}"
}

# ========================
# Fungsi 2: Clone repository dan pindahkan file (Status Monitor & Online)
# ========================
clone_repo() {
  echo -e "${CYAN}Meng-clone repository StatusWRTIrfan...${NC}"
  cd /root || return
  git clone https://github.com/irfanFRizki/StatusWRTIrfan.git > /dev/null 2>&1
  loading_progress "Meng-clone repository"
  echo -e "${GREEN}Clone repository selesai.${NC}"
  
  SRC_DIR="/root/StatusWRTIrfan"
  
  # Direktori tujuan LuCI dan CGI
  LUA_CONTROLLER_DIR="/usr/lib/lua/luci/controller/"
  LUA_VIEW_DIR="/usr/lib/lua/luci/view/"
  CGI_BIN_DIR="/www/cgi-bin/"
  WWW_DIR="/www/"

  mkdir -p "$LUA_CONTROLLER_DIR" "$LUA_VIEW_DIR" "$CGI_BIN_DIR" "$WWW_DIR" > /dev/null 2>&1
  loading_progress "Membuat direktori tujuan"
  echo -e "${GREEN}Direktori tujuan dibuat.${NC}"
  
  # Pindahkan file status_monitor
  mv "$SRC_DIR/usr/lib/lua/luci/controller/status_monitor.lua" "$LUA_CONTROLLER_DIR" > /dev/null 2>&1
  loading_progress "Memindahkan status_monitor.lua"
  echo -e "${GREEN}File status_monitor.lua dipindahkan.${NC}"
  
  mv "$SRC_DIR/usr/lib/lua/luci/view/status_monitor.htm" "$LUA_VIEW_DIR" > /dev/null 2>&1
  loading_progress "Memindahkan status_monitor.htm"
  echo -e "${GREEN}File status_monitor.htm dipindahkan.${NC}"
  
  # Pindahkan file online.sh (online.lua & online.htm dihapus sesuai permintaan)
  mv "$SRC_DIR/usr/bin/online.sh" /usr/bin/online.sh > /dev/null 2>&1
  loading_progress "Memindahkan online.sh"
  echo -e "${GREEN}File online.sh dipindahkan ke /usr/bin.${NC}"
  
  # Pindahkan file CGI scripts
  mv "$SRC_DIR/www/cgi-bin/load_biaya" "$CGI_BIN_DIR" > /dev/null 2>&1
  mv "$SRC_DIR/www/cgi-bin/minggu1" "$CGI_BIN_DIR" > /dev/null 2>&1
  mv "$SRC_DIR/www/cgi-bin/minggu2" "$CGI_BIN_DIR" > /dev/null 2>&1
  mv "$SRC_DIR/www/cgi-bin/minggu3" "$CGI_BIN_DIR" > /dev/null 2>&1
  mv "$SRC_DIR/www/cgi-bin/minggu4" "$CGI_BIN_DIR" > /dev/null 2>&1
  mv "$SRC_DIR/www/cgi-bin/mingguterakhir" "$CGI_BIN_DIR" > /dev/null 2>&1
  mv "$SRC_DIR/www/cgi-bin/pemakaian" "$CGI_BIN_DIR" > /dev/null 2>&1
  mv "$SRC_DIR/www/cgi-bin/save_biaya" "$CGI_BIN_DIR" > /dev/null 2>&1
  mv "$SRC_DIR/www/cgi-bin/status" "$CGI_BIN_DIR" > /dev/null 2>&1
  loading_progress "Memindahkan CGI scripts"
  echo -e "${GREEN}CGI scripts dipindahkan.${NC}"
  
  mv "$SRC_DIR/www/status_monitor.html" "$WWW_DIR" > /dev/null 2>&1
  loading_progress "Memindahkan file HTML status_monitor"
  echo -e "${GREEN}File HTML status_monitor dipindahkan.${NC}"
  
  # Pasang file informasi (view dan controller)
  mkdir -p "/usr/lib/lua/luci/view/informasi" > /dev/null 2>&1
  mv "$SRC_DIR/usr/lib/lua/luci/view/informasi/allowed.htm" "/usr/lib/lua/luci/view/informasi/" > /dev/null 2>&1
  mv "$SRC_DIR/usr/lib/lua/luci/view/informasi/info.htm" "/usr/lib/lua/luci/view/informasi/" > /dev/null 2>&1
  mv "$SRC_DIR/usr/lib/lua/luci/view/informasi/informasi.htm" "/usr/lib/lua/luci/view/informasi/" > /dev/null 2>&1
  mv "$SRC_DIR/usr/lib/lua/luci/view/informasi/log.htm" "/usr/lib/lua/luci/view/informasi/" > /dev/null 2>&1
  mv "$SRC_DIR/usr/lib/lua/luci/view/informasi/notallowed.htm" "/usr/lib/lua/luci/view/informasi/" > /dev/null 2>&1
  mv "$SRC_DIR/usr/lib/lua/luci/view/informasi/settings.htm" "/usr/lib/lua/luci/view/informasi/" > /dev/null 2>&1
  mv "$SRC_DIR/usr/lib/lua/luci/view/informasi/telegram.htm" "/usr/lib/lua/luci/view/informasi/" > /dev/null 2>&1
  mkdir -p "/usr/lib/lua/luci/controller/" > /dev/null 2>&1
  mv "$SRC_DIR/usr/lib/lua/luci/controller/informasi.lua" "/usr/lib/lua/luci/controller/" > /dev/null 2>&1
  loading_progress "Memindahkan file informasi"
  echo -e "${GREEN}File informasi telah dipasang.${NC}"
  
  chmod +x "$CGI_BIN_DIR"/* > /dev/null 2>&1
  loading_progress "Mengatur izin eksekusi CGI"
  echo -e "${GREEN}Izin eksekusi CGI diatur.${NC}"
  
  /etc/init.d/uhttpd restart > /dev/null 2>&1
  loading_progress "Restarting uhttpd"
  echo -e "${GREEN}uhttpd telah direstart.${NC}"
}

# ========================
# Fungsi 3: Update vnstat.db
# ========================
update_vnstat() {
  if [ -z "$SRC_DIR" ]; then
    echo -e "${RED}Repository belum di-clone. Silakan pilih opsi 1 terlebih dahulu.${NC}"
    return
  fi
  echo -e "${CYAN}Mengganti file vnstat.db dengan yang ada di repository${NC}"
  mkdir -p /etc/vnstat > /dev/null 2>&1
  if [ -f /etc/vnstat/vnstat.db ]; then
    echo -e "${YELLOW}Mengganti file vnstat.db dengan yang ada di repository${NC}"
    rm -f /etc/vnstat/vnstat.db
  fi
  mv "$SRC_DIR/vnstat.db" /etc/vnstat/ > /dev/null 2>&1
  loading_progress "Memindahkan vnstat.db"
  echo -e "${GREEN}File vnstat.db telah diganti.${NC}"
}

# ========================
# Fungsi 4: Update nlbwmon
# ========================
update_nlbwmon() {
  if [ -z "$SRC_DIR" ]; then
    echo -e "${RED}Repository belum di-clone. Silakan pilih opsi 1 terlebih dahulu.${NC}"
    return
  fi
  echo -e "${CYAN}Memperbarui file di /etc/nlbwmon/ dengan file backup dari repository${NC}"
  if [ -d "/etc/nlbwmon" ]; then
    rm -rf /etc/nlbwmon/* > /dev/null 2>&1
  fi
  mkdir -p /etc/nlbwmon/ > /dev/null 2>&1
  cp -r "$SRC_DIR/etc/nlbwmon/"* /etc/nlbwmon/ > /dev/null 2>&1
  loading_progress "Memperbarui /etc/nlbwmon/"
  echo -e "${GREEN}File di /etc/nlbwmon/ telah diperbarui.${NC}"
}

# ========================
# Fungsi 5: Buat file nftables (FIX TTL 63)
# ========================
create_nftables() {
  echo -e "${CYAN}Membuat file /etc/nftables.d/11-ttl.nft (FIX TTL 63)${NC}"
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
}

# ========================
# Fungsi 6: Pasang file mm.ipk, instal paket tambahan, dan file lain
# ========================
install_misc() {
  echo -e "${CYAN}Memasang file mm.ipk dan instal paket tambahan...${NC}"
  
  # Pindahkan mm.ipk dari /root dan instal
  if [ -f /root/mm.ipk ]; then
    mv /root/mm.ipk /tmp/mm.ipk
    loading_progress "Memindahkan mm.ipk"
    pkg=$(opkg install /tmp/mm.ipk 2>&1)
    loading_progress "Menginstal mm.ipk"
    echo -e "${GREEN}${pkg}${NC}"
  else
    echo -e "${YELLOW}File /root/mm.ipk tidak ditemukan.${NC}"
  fi
  
  # Instal paket luci-app-nlbwmon dan luci-app-cloudflared
  pkg=$(opkg install luci-app-nlbwmon 2>&1)
  loading_progress "Menginstal luci-app-nlbwmon"
  echo -e "${GREEN}${pkg}${NC}"
  
  pkg=$(opkg install luci-app-cloudflared 2>&1)
  loading_progress "Menginstal luci-app-cloudflared"
  echo -e "${GREEN}${pkg}${NC}"
  
  # Pasang file send_telegram.py dan atur izin eksekusi untuk online.sh dan send_telegram.py
  mv "$SRC_DIR/usr/bin/send_telegram.py" /usr/bin/send_telegram.py > /dev/null 2>&1
  loading_progress "Memindahkan send_telegram.py"
  chmod +x /usr/bin/online.sh /usr/bin/send_telegram.py
  echo -e "${GREEN}File online.sh dan send_telegram.py sudah diatur sebagai executable.${NC}"
}

# ========================
# Fungsi 7: Tambahkan konfigurasi domain ke DHCP
# ========================
update_dhcp() {
  echo -e "${CYAN}Menambahkan konfigurasi domain ke file DHCP (/etc/config/dhcp)${NC}"
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
  loading_progress "Memperbarui DHCP"
  echo -e "${GREEN}Konfigurasi DHCP telah diperbarui.${NC}"
}

# ========================
# Fungsi 8: Hapus folder repository
# ========================
remove_repo() {
  if [ -n "$SRC_DIR" ]; then
    rm -rf "$SRC_DIR" > /dev/null 2>&1
    loading_progress "Menghapus folder repository"
    echo -e "${GREEN}Folder repository telah dihapus.${NC}"
    SRC_DIR=""
  else
    echo -e "${YELLOW}Repository belum di-clone.${NC}"
  fi
}

# ========================
# Fungsi 9: Install semuanya
# ========================
install_all() {
  clone_repo
  update_vnstat
  update_nlbwmon
  create_nftables
  install_misc
  update_dhcp
  show_instructions
  remove_repo
}

# ========================
# Fungsi 10: Tampilkan instruksi konfigurasi manual
# ========================
show_instructions() {
  echo -e "${CYAN}-----------------------------------------------------------${NC}"
  echo -e "${CYAN}Buka menu Network > Traffic Status di LuCI.${NC}"
  echo -e "${CYAN}Kemudian klik CONFIGURE OPTIONS dan atur sebagai berikut:${NC}"
  echo -e "${CYAN}  Default Refresh Intervals: 2 Seconds${NC}"
  echo -e "${CYAN}  Default More Columns: Centang${NC}"
  echo -e "${CYAN}  Show Zeros: Jangan dicentang${NC}"
  echo -e "${CYAN}  Upstream Bandwidth: 100${NC}"
  echo -e "${CYAN}  Downstream Bandwidth: 100${NC}"
  echo -e "${CYAN}-----------------------------------------------------------${NC}"
}

# ========================
# Menu Utama
# ========================
main_menu() {
  install_update
  echo -e "${GREEN}Update paket dan instal dependensi selesai.${NC}"
  while true; do
    echo -e "${YELLOW}========== Menu Install ==========${NC}"
    echo -e "${YELLOW}1) Clone repository dan pindahkan file (Status Monitor & Online)${NC}"
    echo -e "${YELLOW}2) Update vnstat.db${NC}"
    echo -e "${YELLOW}3) Update nlbwmon${NC}"
    echo -e "${YELLOW}4) Buat file nftables ( FIX TTL 63 )${NC}"
    echo -e "${YELLOW}5) Pasang file mm.ipk & instal paket tambahan (luci-app-nlbwmon & luci-app-cloudflared) serta file send_telegram.py${NC}"
    echo -e "${YELLOW}6) Tambahkan konfigurasi domain ke DHCP${NC}"
    echo -e "${YELLOW}7) Tampilkan instruksi konfigurasi manual${NC}"
    echo -e "${YELLOW}8) Hapus folder repository${NC}"
    echo -e "${YELLOW}9) Install semuanya${NC}"
    echo -e "${YELLOW}10) Keluar${NC}"
    echo -ne "${CYAN}Pilih opsi [1-10]: ${NC}"
    read choice
    case $choice in
      1) clone_repo ;;
      2) update_vnstat ;;
      3) update_nlbwmon ;;
      4) create_nftables ;;
      5) install_misc ;;
      6) update_dhcp ;;
      7) show_instructions ;;
      8) remove_repo ;;
      9) install_all ;;
      10) echo -e "${GREEN}Terima kasih. Keluar.${NC}"; exit 0 ;;
      *) echo -e "${RED}Pilihan tidak valid. Coba lagi.${NC}" ;;
    esac
    echo -e "${CYAN}Tekan Enter untuk kembali ke menu...${NC}"
    read
  done
}

# ========================
# Mulai Program
# ========================
main_menu
