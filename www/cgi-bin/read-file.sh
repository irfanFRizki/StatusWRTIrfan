#!/bin/sh
# read-file.sh – Baca isi file dan cetak sebagai plain text

echo "Content-Type: text/plain"
echo ""

# Ambil parameter path
# QUERY_STRING contohnya: path=/etc/config/network
FILE=$(echo "$QUERY_STRING" \
  | sed -e 's/+/ /g' \
        -e 's/%2F/\//g' \
        -e 's/.*path=//')

# Cegah path traversal — hanya path absolut
case "$FILE" in
  /*) ;;
  *) echo "Invalid path"; exit 1;;
esac

# Jika file bisa dibaca, tampilkan; lainnya error
if [ -r "$FILE" ]; then
  cat "$FILE"
else
  echo "Error: tidak dapat membaca $FILE"
fi
