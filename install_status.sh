#!/bin/sh

# Fungsi untuk animasi loading
loading() {
    echo -n "Proses instalasi sedang berjalan"
    while true; do
        echo -n "."
        sleep 1
    done
}

# Mulai animasi loading di latar belakang
loading &
LOADING_PID=$!

# Update paket sebelum memulai instalasi
opkg update
sleep 2
opkg install bc
sleep 2
opkg install git
sleep 2
opkg install git-http
sleep 2

# Pindah ke direktori /root dan clone repository
cd /root
git clone https://github.com/irfanFRizki/StatusWRTIrfan.git

# Direktori sumber dari repository yang sudah di-clone
SRC_DIR="/root/StatusWRTIrfan"

# Direktori tujuan
LUA_CONTROLLER_DIR="/usr/lib/lua/luci/controller/"
LUA_VIEW_DIR="/usr/lib/lua/luci/view/"
CGI_BIN_DIR="/www/cgi-bin/"
WWW_DIR="/www/"

# Pastikan direktori tujuan ada
mkdir -p $LUA_CONTROLLER_DIR $LUA_VIEW_DIR $CGI_BIN_DIR $WWW_DIR

# Pindahkan file Lua controller
mv $SRC_DIR/usr/lib/lua/luci/controller/status_monitor.lua $LUA_CONTROLLER_DIR

# Pindahkan file Lua view
mv $SRC_DIR/usr/lib/lua/luci/view/status_monitor.htm $LUA_VIEW_DIR

# Pindahkan file CGI scripts
mv $SRC_DIR/www/cgi-bin/load_biaya $CGI_BIN_DIR
mv $SRC_DIR/www/cgi-bin/minggu1 $CGI_BIN_DIR
mv $SRC_DIR/www/cgi-bin/minggu2 $CGI_BIN_DIR
mv $SRC_DIR/www/cgi-bin/minggu3 $CGI_BIN_DIR
mv $SRC_DIR/www/cgi-bin/minggu4 $CGI_BIN_DIR
mv $SRC_DIR/www/cgi-bin/mingguterakhir $CGI_BIN_DIR
mv $SRC_DIR/www/cgi-bin/pemakaian $CGI_BIN_DIR
mv $SRC_DIR/www/cgi-bin/save_biaya $CGI_BIN_DIR
mv $SRC_DIR/www/cgi-bin/status $CGI_BIN_DIR

# Pindahkan file status monitor HTML
mv $SRC_DIR/www/status_monitor.html $WWW_DIR

# Beri izin eksekusi untuk file CGI agar bisa dijalankan
chmod +x $CGI_BIN_DIR/*

# Restart uhttpd agar perubahan diterapkan
/etc/init.d/uhttpd restart

# Hentikan animasi loading
kill $LOADING_PID
wait $LOADING_PID 2>/dev/null
echo "\nInstalasi StatusWRTIrfan selesai!"

# Jalankan feed script dan instalasi paket nikki
curl -s -L https://github.com/nikkinikki-org/OpenWrt-nikki/raw/refs/heads/main/feed.sh | ash

opkg install nikki
opkg install luci-app-nikki
opkg install luci-i18n-nikki-zh-cn
apk add --allow-untrusted nikki
apk add --allow-untrusted luci-app-nikki
apk add --allow-untrusted luci-i18n-nikki-zh-cn

# Pindahkan file blm.tar.gz ke /etc/nikki/ dan ekstrak isinya
echo "Memindahkan dan mengekstrak blm.tar.gz ke /etc/nikki/"
mkdir -p /etc/nikki/
mv $SRC_DIR/blm.tar.gz /etc/nikki/
cd /etc/nikki/
tar -xzvf blm.tar.gz

# Pindahkan file nlbwmon-backup-friWrt-2025-02-20.tar.gz ke /etc/nlbwmon/ dan ekstrak isinya
echo "Memindahkan dan mengekstrak nlbwmon-backup-friWrt-2025-02-20.tar.gz ke /etc/nlbwmon/"
mkdir -p /etc/nlbwmon/
mv $SRC_DIR/nlbwmon-backup-friWrt-2025-02-20.tar.gz /etc/nlbwmon/
cd /etc/nlbwmon/
BACKUP_DIR="nlbwmon-backup-friWrt-2025-02-20"
if [ -d "$BACKUP_DIR" ]; then
    echo "Duplikat data ditemukan. Menghapus data sebelumnya."
    rm -rf "$BACKUP_DIR"
fi
tar -xzvf nlbwmon-backup-friWrt-2025-02-20.tar.gz

# Ganti file vnstat.db dengan yang ada di repository
echo "Mengganti file vnstat.db dengan yang ada di repository"
mkdir -p /etc/vnstat
if [ -f /etc/vnstat/vnstat.db ]; then
    echo "File vnstat.db sebelumnya ditemukan, menghapusnya..."
    rm -f /etc/vnstat/vnstat.db
fi
mv $SRC_DIR/vnstat.db /etc/vnstat/

# Hapus folder repository yang sudah di-clone
rm -rf $SRC_DIR

# Buat file baru 11-ttl.nft di direktori /etc/nftables.d/
echo "Membuat file /etc/nftables.d/11-ttl.nft"
mkdir -p /etc/nftables.d/
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

# Restart firewall agar perubahan pada nftables diterapkan
/etc/init.d/firewall restart

# Instalasi dan konfigurasi wrtbwmon
sleep 2
opkg install wget
sleep 2
cd /tmp && wget https://github.com/brvphoenix/wrtbwmon/releases/download/v1.2.1-3/wrtbwmon_1.2.1-3_all.ipk
sleep 2
opkg install /tmp/wrtbwmon_1.2.1-3_all.ipk
sleep 2
cd /tmp && wget https://github.com/brvphoenix/luci-app-wrtbwmon/releases/download/release-2.0.13/luci-app-wrtbwmon_2.0.13_all.ipk
sleep 2
opkg install /tmp/luci-app-wrtbwmon_2.0.13_all.ipk
sleep 2
/etc/init.d/wrtbwmon enable && /etc/init.d/wrtbwmon start

# Instruksi konfigurasi manual wrtbwmon
echo "-----------------------------------------------------------"
echo "Buka menu Network > Traffic Status di LuCI."
echo "Kemudian klik CONFIGURE OPTIONS dan atur sebagai berikut:"
echo "  Default Refresh Intervals: 2 Seconds"
echo "  Default More Columns: Centang"
echo "  Show Zeros: Jangan di centang"
echo "  Upstream Bandwidth: 100"
echo "  Downstream Bandwidth: 100"
echo "-----------------------------------------------------------"
