#!/usr/bin/env python3
import requests
import sys
import json
from datetime import datetime

# Konfigurasi Bot Telegram (ganti sesuai milik Anda)
BOT_TOKEN = "6901960737:AAEUEW0ZLHqRC1dwgol019_oo14zVF82xc8"
CHAT_ID   = "5645537022"
LOG_FILE  = "/tmp/telegram_log.txt"

def log(line):
    # Tambah newline sendiri
    with open(LOG_FILE, "a") as f:
        f.write(f"[{datetime.now()}] {line}\n")

def main():
    # Ambil pesan dari argumen
    if len(sys.argv) < 2:
        print("Usage: send_telegram.py \"message text\"")
        sys.exit(1)

    message = sys.argv[1]

    url = f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage"
    payload = {
        "chat_id": CHAT_ID,
        "text": message,
        "parse_mode": "HTML"
    }

    try:
        response = requests.post(url, json=payload, timeout=10)
        result = response.json()

        # Log full JSON response
        log("RESPONSE: " + json.dumps(result, ensure_ascii=False))

        if result.get("ok"):
            status = "OK"
        else:
            status = "FAIL"
        log(f"{status}: {message}")

    except Exception as e:
        log("ERROR_EXCEPTION: " + str(e))

if __name__ == "__main__":
    main()