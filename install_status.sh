#!/bin/sh
# Script: install_status.sh
# Deskripsi:
# 1. Meng-clone repositori StatusWRTIrfan (jika belum ada)
# 2. Membuat arsip tar.gz dari direktori usr dan www di dalam repositori
# 3. Memindahkan arsip html.tar.gz ke folder /usr dan mengekstraknya
# 4. Memindahkan arsip html2.tar.gz ke folder /www, mengekstraknya, dan mengatur permission file-file cgi
# 5. Setelah semuanya berhasil, menghapus folder StatusWRTIrfan, html.tar.gz, dan html2.tar.gz

# Masuk ke direktori /root
cd /root || { echo "Gagal masuk ke /root"; exit 1; }

# Clone repositori (jika direktori StatusWRTIrfan belum ada)
if [ ! -d "StatusWRTIrfan" ]; then
    echo "Meng-clone repositori StatusWRTIrfan..."
    git clone https://github.com/irfanFRizki/StatusWRTIrfan.git || { echo "Gagal meng-clone repositori"; exit 1; }
else
    echo "Direktori StatusWRTIrfan sudah ada, melewati cloning..."
fi

# Buat arsip untuk direktori usr
echo "Membuat arsip html.tar.gz untuk direktori usr..."
tar -czvf /root/html.tar.gz /root/StatusWRTIrfan/usr || { echo "Gagal membuat arsip html.tar.gz"; exit 1; }

# Buat arsip untuk direktori www
echo "Membuat arsip html2.tar.gz untuk direktori www..."
tar -czvf /root/html2.tar.gz /root/StatusWRTIrfan/www || { echo "Gagal membuat arsip html2.tar.gz"; exit 1; }

# Pindahkan dan ekstrak html.tar.gz ke /usr
echo "Memindahkan html.tar.gz ke /usr dan mengekstraknya..."
if [ ! -d "/usr" ]; then
    mkdir -p /usr
fi
mv /root/html.tar.gz /usr/ || { echo "Gagal memindahkan html.tar.gz ke /usr"; exit 1; }
cd /usr || { echo "Gagal masuk ke /usr"; exit 1; }
tar -xzvf html.tar.gz || { echo "Gagal mengekstrak html.tar.gz di /usr"; exit 1; }
cd /root

# Pindahkan dan ekstrak html2.tar.gz ke /www
echo "Memindahkan html2.tar.gz ke /www dan mengekstraknya..."
if [ ! -d "/www" ]; then
    mkdir -p /www
fi
mv /root/html2.tar.gz /www/ || { echo "Gagal memindahkan html2.tar.gz ke /www"; exit 1; }
cd /www || { echo "Gagal masuk ke /www"; exit 1; }
tar -xzvf html2.tar.gz || { echo "Gagal mengekstrak html2.tar.gz di /www"; exit 1; }

# Tambahkan permission eksekusi untuk file-file cgi di /www/cgi-bin/
echo "Mengatur permission eksekusi untuk file-file cgi..."
CGI_DIR="/www/cgi-bin"
FILES="load_biaya minggu1 minggu2 minggu3 minggu4 mingguterakhir pemakaian save_biaya status"

for file in $FILES; do
    if [ -f "$CGI_DIR/$file" ]; then
        chmod +x "$CGI_DIR/$file" || echo "Gagal mengatur permission untuk $CGI_DIR/$file"
    else
        echo "File $CGI_DIR/$file tidak ditemukan."
    fi
done

# Kembali ke direktori /root
cd /root

# Langkah pembersihan: menghapus folder dan file arsip yang tidak diperlukan
echo "Membersihkan folder StatusWRTIrfan dan file arsip..."
rm -rf /root/StatusWRTIrfan
rm -f /usr/html.tar.gz
rm -f /www/html2.tar.gz

echo "Proses selesai."
