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
