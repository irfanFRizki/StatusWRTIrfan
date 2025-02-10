#!/bin/sh

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

echo "Instalasi StatusWRTIrfan selesai!"

# Hapus folder repository yang sudah di-clone
rm -rf $SRC_DIR
