#!/usr/bin/env python3
import requests
import sys
import json
from datetime import datetime

# Konfigurasi Bot Telegram (ganti sesuai dengan milik kamu)
BOT_TOKEN = "6901960737:AAEUEW0ZLHqRC1dwgol019_oo14zVF82xc8"
CHAT_ID = "5645537022"
LOG_FILE = "/tmp/telegram_log.txt"

# Ambil pesan dari argumen
if len(sys.argv) < 2:
    print("Usage: send_telegram.py \"message text\"")
    sys.exit(1)

message = sys.argv[1]

# Kirim pesan ke Telegram
url = f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage"
payload = {
    "chat_id": CHAT_ID,
    "text": message,
    "parse_mode": "Markdown"
}

try:
    response = requests.post(url, json=payload)
    result = response.json()
    status = "OK" if result.get("ok") else "FAIL"

    # Simpan log
    with open(LOG_FILE, "a") as log:
        log.write(f"[{datetime.now()}] {status}: {message}\n")
except Exception as e:
    with open(LOG_FILE, "a") as log:
        log.write(f"[{datetime.now()}] ERROR: {str(e)}\n")
