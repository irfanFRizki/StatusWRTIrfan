#!/usr/bin/env python3
import requests
import sys
import json
from datetime import datetime
import urllib.parse

# Konfigurasi Bot Telegram
BOT_TOKEN = "6901960737:AAEUEW0ZLHqRC1dwgol019_oo14zVF82xc8"
CHAT_ID   = "5645537022"
LOG_FILE  = "/tmp/telegram_log.txt"
# URL endpoint unblock di router
UNBLOCK_URL = "http://192.168.1.1/admin/services/informasi/notallowed/delete"

def log(line):
    with open(LOG_FILE, "a") as f:
        f.write(f"[{datetime.now()}] {line}\n")

def main():
    # Ambil pesan dari argumen
    if len(sys.argv) < 3:
        print("Usage: send_telegram.py \"message text\" ip_address")
        sys.exit(1)

    message = sys.argv[1]
    ip_address = sys.argv[2]

    url = f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage"
    
    # Payload dasar
    payload = {
        "chat_id": CHAT_ID,
        "text": message,
        "parse_mode": "HTML"
    }
    
    # Tambahkan inline keyboard
    callback_data = f"unblock_{ip_address}"
    unblock_query = f"ip={urllib.parse.quote(ip_address)}"
    
    payload["reply_markup"] = {
        "inline_keyboard": [
            [
                {
                    "text": "✅ Unblock IP",
                    "callback_data": callback_data
                },
                {
                    "text": "🌐 Buka Portal",
                    "url": f"{UNBLOCK_URL}?{unblock_query}"
                }
            ]
        ]
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