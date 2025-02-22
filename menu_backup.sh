#!/bin/sh
# ========================
# Konfigurasi Global
# ========================
echo -n "Masukkan GITHUB_TOKEN: "
read GITHUB_TOKEN

REPO_OWNER="irfanFRizki"
REPO_NAME="StatusWRTIrfan"

# ========================
# Fungsi Menu Utama
# ========================
menu() {
  echo "----------------------------"
  echo "  Menu Backup GitHub"
  echo "----------------------------"
  echo "1) Backup file (input path secara manual)"
  echo "2) Backup folder /etc/nlbwmon"
  echo "3) Keluar"
  echo -n "Pilih opsi [1-3]: "
  read pilihan
  case "$pilihan" in
    1) backup_file ;;
    2) backup_nlbwmon ;;
    3) exit 0 ;;
    *) echo "Pilihan tidak valid. Coba lagi." ;;
  esac
}

# ========================
# Fungsi Backup File (dinamis) dengan loading progress
# ========================
backup_file() {
  echo -n "Masukkan path file yang ingin dibackup (misal: /etc/vnstat/vnstat.db): "
  read FILE_PATH

  if [ ! -f "$FILE_PATH" ]; then
    echo "File $FILE_PATH tidak ditemukan."
    return
  fi

  # Buat target path untuk repositori GitHub dengan menghilangkan karakter awal '/'
  TARGET_PATH=$(echo "$FILE_PATH" | sed 's|^/||')
  COMMIT_MESSAGE="Backup $FILE_PATH on $(date +'%Y-%m-%d %H:%M:%S')"

  # Encode file ke base64 dan hapus newline
  FILE_CONTENT=$(base64 "$FILE_PATH" | tr -d '\n')
  TMP_JSON="/tmp/payload.json"

  # Cek apakah file sudah ada di GitHub (ambil sha jika ada)
  EXISTING_RESPONSE=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/contents/$TARGET_PATH")
  SHA=$(echo "$EXISTING_RESPONSE" | grep -o '"sha": "[^"]*' | cut -d'"' -f4)

  # Buat payload JSON (dengan atau tanpa sha)
  if [ -n "$SHA" ]; then
    cat <<EOF > "$TMP_JSON"
{
  "message": "$COMMIT_MESSAGE",
  "content": "$FILE_CONTENT",
  "sha": "$SHA"
}
EOF
  else
    cat <<EOF > "$TMP_JSON"
{
  "message": "$COMMIT_MESSAGE",
  "content": "$FILE_CONTENT"
}
EOF
  fi

  # Lakukan PUT request ke GitHub API untuk upload/update file
  RESPONSE=$(curl -s -X PUT \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Content-Type: application/json" \
    -d @"$TMP_JSON" \
    "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/contents/$TARGET_PATH")

  rm "$TMP_JSON"

  # Cek apakah backup berhasil dengan mencari key "commit" pada respons
  if echo "$RESPONSE" | grep -q '"commit":'; then
    # Tampilkan loading progress dari 1% ke 100%
    for i in $(seq 1 100); do
      printf "\rLoading: %d%%" "$i"
      sleep 0.03
    done
    echo ""
    echo "Backup $FILE_PATH selesai."
  else
    echo "Backup gagal. Response: $RESPONSE"
  fi
}

# ========================
# Fungsi Backup Folder nlbwmon (tanpa loading progress)
# ========================
backup_nlbwmon() {
  LOCAL_DIR="/etc/nlbwmon"
  TARGET_DIR="etc/nlbwmon"
  COMMIT_MESSAGE_BASE="Backup file nlbwmon"

  for FILE_PATH in "$LOCAL_DIR"/*; do
    # Pastikan hanya memproses file biasa
    if [ ! -f "$FILE_PATH" ]; then
      continue
    fi

    FILENAME=$(basename "$FILE_PATH")
    TARGET_PATH="$TARGET_DIR/$FILENAME"
    COMMIT_MESSAGE="$COMMIT_MESSAGE_BASE: $FILENAME on $(date +'%Y-%m-%d %H:%M:%S')"

    # Encode file ke base64 dan hilangkan newline
    FILE_CONTENT=$(base64 "$FILE_PATH" | tr -d '\n')
    TMP_JSON="/tmp/payload.json"

    # Cek apakah file sudah ada di GitHub (ambil sha jika ada)
    EXISTING_RESPONSE=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
      "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/contents/$TARGET_PATH")
    SHA=$(echo "$EXISTING_RESPONSE" | grep -o '"sha": "[^"]*' | cut -d'"' -f4)

    # Buat payload JSON (dengan atau tanpa sha)
    if [ -n "$SHA" ]; then
      cat <<EOF > "$TMP_JSON"
{
  "message": "$COMMIT_MESSAGE",
  "content": "$FILE_CONTENT",
  "sha": "$SHA"
}
EOF
    else
      cat <<EOF > "$TMP_JSON"
{
  "message": "$COMMIT_MESSAGE",
  "content": "$FILE_CONTENT"
}
EOF
    fi

    # Lakukan PUT request untuk upload/update file ke GitHub
    curl -s -X PUT \
      -H "Authorization: token $GITHUB_TOKEN" \
      -H "Content-Type: application/json" \
      -d @"$TMP_JSON" \
      "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/contents/$TARGET_PATH"

    rm "$TMP_JSON"
    echo "Backup $FILENAME selesai."
  done

  echo "Backup folder nlbwmon selesai."
}

# ========================
# Loop Menu Utama
# ========================
while true; do
  menu
done
