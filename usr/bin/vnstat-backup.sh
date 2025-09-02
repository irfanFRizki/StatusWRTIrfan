#!/bin/bash

# Konfigurasi
GITHUB_TOKEN_ENCODED="Isi pesan ini di pesan tersimpan telegram"  # Base64 encoded token
GITHUB_USER="irfanFRizki"
GITHUB_REPO="StatusWRTIrfan"
GITHUB_BRANCH="main"

# Decode GitHub token
GITHUB_TOKEN=$(echo "$GITHUB_TOKEN_ENCODED" | base64 -d)
SOURCE_FILE="/etc/vnstat/vnstat.db"
WORK_DIR="/tmp/StatusWRTIrfan"
TARGET_PATH="etc/vnstat/vnstat.db"

# Fungsi untuk log
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> /var/log/vnstat-backup.log
}

# Cek apakah file source ada
if [ ! -f "$SOURCE_FILE" ]; then
    log "ERROR: Source file $SOURCE_FILE tidak ditemukan"
    exit 1
fi

# Setup atau update repository
if [ -d "$WORK_DIR/.git" ]; then
    log "INFO: Updating existing repository"
    cd "$WORK_DIR"
    git pull origin "$GITHUB_BRANCH" 2>/dev/null
else
    log "INFO: Cloning repository"
    rm -rf "$WORK_DIR"
    git clone "https://$GITHUB_TOKEN@github.com/$GITHUB_USER/$GITHUB_REPO.git" "$WORK_DIR"
    if [ $? -ne 0 ]; then
        log "ERROR: Failed to clone repository"
        exit 1
    fi
    cd "$WORK_DIR"
fi

# Konfigurasi git
git config user.name "OpenWrt Auto Backup"
git config user.email "backup@openwrt.local"

# Buat direktori target jika belum ada
mkdir -p "$(dirname "$TARGET_PATH")"

# Copy file vnstat.db
cp "$SOURCE_FILE" "$TARGET_PATH"
if [ $? -ne 0 ]; then
    log "ERROR: Failed to copy $SOURCE_FILE to $TARGET_PATH"
    exit 1
fi

# Cek apakah ada perubahan
if git diff --quiet "$TARGET_PATH" 2>/dev/null; then
    log "INFO: No changes detected in vnstat.db"
    exit 0
fi

# Add dan commit
git add "$TARGET_PATH"
git commit -m "Auto backup vnstat.db $(date '+%Y-%m-%d %H:%M:%S')"
if [ $? -ne 0 ]; then
    log "ERROR: Failed to commit changes"
    exit 1
fi

# Push dengan retry logic
RETRY_COUNT=0
MAX_RETRIES=3

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    git push origin "$GITHUB_BRANCH" 2>/dev/null
    if [ $? -eq 0 ]; then
        log "SUCCESS: vnstat.db backed up successfully"
        break
    else
        RETRY_COUNT=$((RETRY_COUNT + 1))
        log "WARNING: Push failed, retry $RETRY_COUNT/$MAX_RETRIES"
        if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
            sleep 10
        else
            log "ERROR: Failed to push after $MAX_RETRIES retries"
            exit 1
        fi
    fi
done

# Cleanup old log entries
tail -n 100 /var/log/vnstat-backup.log > /tmp/vnstat-backup-temp.log 2>/dev/null
mv /tmp/vnstat-backup-temp.log /var/log/vnstat-backup.log 2>/dev/null