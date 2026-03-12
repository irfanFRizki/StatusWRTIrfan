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

# ========================
# Konfigurasi Global
# ========================
printf "${CYAN}Masukkan GITHUB_TOKEN: ${NC}"
read GITHUB_TOKEN

# Ambil username GitHub dari token
GITHUB_USER=$(curl -s -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/user | grep -o '"login": "[^"]*' | cut -d'"' -f4)

REPO_OWNER="irfanFRizki"
REPO_NAME="StatusWRTIrfan"

# Tampilkan banner informasi dengan warna-warni
printf "${GREEN}========================================${NC}\n"
printf "${RED}Repo Owner : ${YELLOW}%s${NC}\n" "$REPO_OWNER"
printf "${BLUE}Repo Name  : ${PURPLE}%s${NC}\n" "$REPO_NAME"
printf "${CYAN}GitHub User: ${GREEN}%s${NC}\n" "$GITHUB_USER"
printf "${GREEN}========================================${NC}\n\n"

# ========================
# Fungsi Menu Utama
# ========================
menu() {
  printf "${CYAN}----------------------------${NC}\n"
  printf "${CYAN}  Menu Backup GitHub${NC}\n"
  printf "${CYAN}----------------------------${NC}\n"
  printf "${YELLOW}1) Backup file (input path secara manual)${NC}\n"
  printf "${YELLOW}2) Backup folder /etc/nlbwmon${NC}\n"
  printf "${YELLOW}3) Keluar${NC}\n"
  printf "${CYAN}Pilih opsi [1-3]: ${NC}"
  read pilihan
  case "$pilihan" in
    1) backup_file ;;
    2) backup_nlbwmon ;;
    3) exit 0 ;;
    *) printf "${RED}Pilihan tidak valid. Coba lagi.${NC}\n" ;;
  esac
}

# ========================
# Fungsi Loading Progress dengan warna-warni
# ========================
loading_progress() {
  label="$1"
  # Daftar warna untuk efek bergantian
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
# Fungsi Backup File (dinamis) dengan loading progress
# ========================
backup_file() {
  printf "${CYAN}Masukkan path file yang ingin dibackup (misal: /etc/vnstat/vnstat.db): ${NC}"
  read FILE_PATH

  if [ ! -f "$FILE_PATH" ]; then
    printf "${RED}File %s tidak ditemukan.${NC}\n" "$FILE_PATH"
    return
  fi

  TARGET_PATH=$(echo "$FILE_PATH" | sed 's|^/||')
  COMMIT_MESSAGE="Backup $FILE_PATH on $(date +'%Y-%m-%d %H:%M:%S')"
  FILE_CONTENT=$(base64 "$FILE_PATH" | tr -d '\n')
  TMP_JSON="/tmp/payload.json"

  EXISTING_RESPONSE=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/contents/$TARGET_PATH")
  SHA=$(echo "$EXISTING_RESPONSE" | grep -o '"sha": "[^"]*' | cut -d'"' -f4)

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

  RESPONSE=$(curl -s -X PUT \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Content-Type: application/json" \
    -d @"$TMP_JSON" \
    "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/contents/$TARGET_PATH")

  rm "$TMP_JSON"

  if echo "$RESPONSE" | grep -q '"commit":'; then
    loading_progress "Loading"
    printf "${GREEN}Backup %s selesai.${NC}\n" "$FILE_PATH"
  else
    printf "${RED}Backup gagal. Response: %s${NC}\n" "$RESPONSE"
  fi
}

# ========================
# Fungsi Backup Folder nlbwmon dengan loading progress
# ========================
backup_nlbwmon() {
  LOCAL_DIR="/etc/nlbwmon"
  TARGET_DIR="etc/nlbwmon"
  COMMIT_MESSAGE_BASE="Backup file nlbwmon"

  for FILE_PATH in "$LOCAL_DIR"/*; do
    if [ ! -f "$FILE_PATH" ]; then
      continue
    fi

    FILENAME=$(basename "$FILE_PATH")
    TARGET_PATH="$TARGET_DIR/$FILENAME"
    COMMIT_MESSAGE="$COMMIT_MESSAGE_BASE: $FILENAME on $(date +'%Y-%m-%d %H:%M:%S')"
    FILE_CONTENT=$(base64 "$FILE_PATH" | tr -d '\n')
    TMP_JSON="/tmp/payload.json"

    EXISTING_RESPONSE=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
      "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/contents/$TARGET_PATH")
    SHA=$(echo "$EXISTING_RESPONSE" | grep -o '"sha": "[^"]*' | cut -d'"' -f4)

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

    RESPONSE=$(curl -s -X PUT \
      -H "Authorization: token $GITHUB_TOKEN" \
      -H "Content-Type: application/json" \
      -d @"$TMP_JSON" \
      "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/contents/$TARGET_PATH")

    rm "$TMP_JSON"

    if echo "$RESPONSE" | grep -q '"commit":'; then
      loading_progress "Loading for $FILENAME"
      printf "${GREEN}Backup %s selesai.${NC}\n" "$FILENAME"
    else
      printf "${RED}Backup %s gagal.${NC}\n" "$FILENAME"
    fi
  done

  printf "${BLUE}Backup folder nlbwmon selesai.${NC}\n"
}

# ========================
# Loop Menu Utama
# ========================
while true; do
  menu
done
