#!/bin/bash
# nikki_monitor.sh
# Script untuk memantau service "nikki" (process bernama "mihomo")
# dan otomatis me-restart jika tidak berjalan, sekaligus
# mengirim notifikasi ke Telegram melalui bot.

# Konfigurasi Telegram Bot
TELEGRAM_BOT_TOKEN="6901960737:AAEUEW0ZLHqRC1dwgol019_oo14zVF82xc8"  # Ganti dengan token bot Anda
TELEGRAM_CHAT_ID="5645537022"      # Ganti dengan chat ID tujuan

# Waktu tunggu sebelum pengecekan pertama (detik)
DELAY=${1:-60}
# Interval pengecekan berikutnya (detik)
INTERVAL=${2:-10}
# File log
LOG_FILE="/tmp/nikki_monitor.log"

# Fungsi untuk mencatat log dengan timestamp
log_msg() {
  local msg="$1"
  local timestamp="$(date -R | cut -d' ' -f1-5)"
  echo "[$timestamp] $msg" >> "$LOG_FILE"
  send_telegram "$msg"
}

# Fungsi untuk mengirim pesan ke Telegram
send_telegram() {
  local text="$1"
  # Escape karakter agar aman dikirim
  local safe_text=$(echo "$text" | sed 's/"/\\"/g')
  curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d chat_id="${TELEGRAM_CHAT_ID}" \
    -d parse_mode="Markdown" \
    -d text="[$(date "+%Y-%m-%d %H:%M:%S")] $safe_text" > /dev/null
}

# Mulai monitoring
log_msg "Menunggu $DELAY detik sebelum mulai pengecekan service nikki..."
sleep "$DELAY"

# Loop pengecekan
while true; do
  if pidof mihomo >/dev/null; then
    log_msg "✅ Service nikki sudah berjalan"
    exit 0
  else
    log_msg "⚠️ Service nikki belum berjalan, mencoba menjalankan ulang..."
    /etc/init.d/nikki restart
  fi
  sleep "$INTERVAL"
done
