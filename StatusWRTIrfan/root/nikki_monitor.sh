#!/bin/bash
# nikki_monitor.sh
# Script untuk memantau service "nikki" (process bernama "mihomo")
# dan otomatis me-restart jika tidak berjalan, termasuk penanganan kegagalan 3x
# serta ekstraksi file tar.gz dan notifikasi Telegram.

# Konfigurasi Telegram Bot
TELEGRAM_BOT_TOKEN="6901960737:AAEUEW0ZLHqRC1dwgol019_oo14zVF82xc8"
TELEGRAM_CHAT_ID="5645537022"

# Waktu tunggu sebelum pengecekan pertama (detik)
DELAY=${1:-60}
# Interval pengecekan berikutnya (detik)
INTERVAL=${2:-10}
# File log
LOG_FILE="/tmp/nikki_monitor.log"

# Counter untuk percobaan restart gagal
failed_restarts=0

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

    # Tunggu 5 detik untuk memastikan service sempat start
    sleep 5

    # Cek ulang status service setelah restart
    if pidof mihomo >/dev/null; then
      log_msg "✅ Restart berhasil"
      failed_restarts=0
    else
      failed_restarts=$((failed_restarts + 1))
      log_msg "⚠️ Gagal melakukan restart (percobaan ke-$failed_restarts)"

      # Jika gagal 3x berturut-turut
      if [ $failed_restarts -ge 3 ]; then
        log_msg "🚨 3x percobaan restart gagal. Mengekstrak file tar.gz..."
        
        # Ekstraksi file
        cd /etc/nikki/ && tar -xzvf *.tar.gz
        log_msg "📦 File tar.gz telah diekstrak. Mencoba restart kembali..."
        
        # Restart service lagi
        /etc/init.d/nikki restart
        failed_restarts=0  # Reset counter

        # Cek hasil restart setelah ekstraksi
        sleep 5
        if pidof mihomo >/dev/null; then
          log_msg "✅ Restart berhasil setelah ekstraksi"
        else
          log_msg "❌ Restart masih gagal setelah ekstraksi"
        fi
      fi
    fi
  fi
  
  sleep "$INTERVAL"
done