#!/usr/bin/env python3
# /usr/bin/mwan3_check.py
# Behavior:
#  - OFFLINE  -> run: mwan3 ifdown wan ; mwan3 ifup wan2
#  - ONLINE   -> run: mwan3 ifup wan  (DO NOT ifdown wan2; leave wan2 active)
#  - Reads from /tmp/autoip-all-rakitan.log and .log.1, infers timestamps, matches recent events
#  - Persist state to avoid spamming notifications
#  - Send Telegram notifications (if BOT_TOKEN and CHAT_ID set)
#  - Intended to be run via cron every 1 minute: "* * * * * /usr/bin/mwan3_check.py"

from datetime import datetime, timedelta
import subprocess
import os
import json
import re
import sys

try:
    import requests
except Exception:
    print("ERROR: python requests module not found. Install with: opkg install python3-requests")
    sys.exit(1)

# ====== CONFIG ======
BOT_TOKEN = "6901960737:AAEUEW0ZLHqRC1dwgol019_oo14zVF82xc8"
CHAT_ID = "5645537022"

LOG_FILES = [
    "/tmp/autoip-all-rakitan.log",
    "/tmp/autoip-all-rakitan.log.1"
]

# patterns
OFFLINE_PATTERNS = [ r"Status:\s*OFFLINE", r"status:\s*ping failed", r"100\.00% failed" ]
OFFLINE_EXTRA_PATTERNS = [ r"Trying to refresh IP address", r"IP change received from", r"\[IFDOWN wan\]", r"\bIFDOWN wan\b" ]
ONLINE_PATTERNS = [ r"status:\s*ONLINE", r"Status:\s*ONLINE", r"🟢 Berhasil memperbarui IP Address", r"New WAN IP", r"\[GET IP\]\s*New WAN IP" ]

STATE_FILE = "/tmp/mwan3_check_state.json"

# scanning options
TAIL_READ_LINES = 2000
WINDOW_SECONDS = 120   # keep by default; you can lower to 120-300 if you want stricter recentness

DEVNULL = open(os.devnull, "wb")

# ---------------- helpers ----------------
def read_all_lines(path):
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            return f.read().splitlines()
    except Exception:
        return []

_re_full = re.compile(r'(\d{2}-[A-Za-z]{3}-\d{4} \d{2}:\d{2}:\d{2})')
_re_dayname = re.compile(r'([A-Za-z]+ \d{2}-[A-Za-z]{3}-\d{4} \d{2}:\d{2}:\d{2})')
_re_time_only = re.compile(r'\[\s*(\d{2}:\d{2}:\d{2})\s*\]')
_re_time_short = re.compile(r'(\d{2}-[A-Za-z]{3}-\d{4})')

def parse_dt_from_line(line, last_date_ctx):
    m = _re_full.search(line)
    if m:
        try:
            dt = datetime.strptime(m.group(1), "%d-%b-%Y %H:%M:%S")
            return dt, dt.date()
        except Exception:
            pass
    m = _re_dayname.search(line)
    if m:
        try:
            tok = m.group(1)
            try:
                dt = datetime.strptime(tok, "%A %d-%b-%Y %H:%M:%S")
            except Exception:
                dt = datetime.strptime(tok.split(" ", 1)[1], "%d-%b-%Y %H:%M:%S")
            return dt, dt.date()
        except Exception:
            pass
    m = re.search(r'TIME\s*:\s*([A-Za-z]+ \d{2}-[A-Za-z]{3}-\d{4} \d{2}:\d{2}:\d{2})', line)
    if m:
        try:
            dt = datetime.strptime(m.group(1), "%A %d-%b-%Y %H:%M:%S")
            return dt, dt.date()
        except Exception:
            try:
                dt = datetime.strptime(m.group(1).split(" ",1)[1], "%d-%b-%Y %H:%M:%S")
                return dt, dt.date()
            except Exception:
                pass
    m = _re_time_only.search(line)
    if m and last_date_ctx:
        timestr = m.group(1)
        try:
            dt = datetime.strptime(f"{last_date_ctx.strftime('%d-%b-%Y')} {timestr}", "%d-%b-%Y %H:%M:%S")
            return dt, last_date_ctx
        except Exception:
            pass
    m = _re_time_short.search(line)
    if m:
        try:
            datepart = m.group(1)
            m2 = re.search(r'(\d{2}:\d{2}:\d{2})', line)
            if m2:
                dt = datetime.strptime(f"{datepart} {m2.group(1)}", "%d-%b-%Y %H:%M:%S")
                return dt, dt.date()
        except Exception:
            pass
    return None, last_date_ctx

def matches_any(line, patterns):
    for p in patterns:
        if re.search(p, line, re.IGNORECASE):
            return True
    return False

def collect_events_with_dates(paths, window_seconds=WINDOW_SECONDS):
    now = datetime.now()
    cutoff = now - timedelta(seconds=window_seconds)
    events = []
    for p in paths:
        if not os.path.exists(p):
            continue
        lines = read_all_lines(p)
        last_date_ctx = None
        for ln in lines:
            ln_stripped = ln.strip()
            dt, last_date_ctx = parse_dt_from_line(ln_stripped, last_date_ctx)
            is_offline = matches_any(ln_stripped, OFFLINE_PATTERNS) or matches_any(ln_stripped, OFFLINE_EXTRA_PATTERNS)
            is_online = matches_any(ln_stripped, ONLINE_PATTERNS)
            if (is_offline or is_online) and dt:
                if dt <= now and dt >= cutoff:
                    status = "OFFLINE" if is_offline else "ONLINE"
                    events.append((dt, status, ln_stripped, p))
    events.sort(key=lambda x: x[0])
    return events

# ---------------- state + telegram ----------------
def load_state():
    state = {
        "last_status": None,
        "last_offline_time": None,
        "last_online_time": None,
        "offline_count_today": 0,
        "last_day": datetime.now().day
    }
    if os.path.exists(STATE_FILE):
        try:
            with open(STATE_FILE, "r") as f:
                raw = json.load(f)
                state["last_status"] = raw.get("last_status")
                if raw.get("last_offline_time"):
                    state["last_offline_time"] = datetime.fromisoformat(raw["last_offline_time"])
                if raw.get("last_online_time"):
                    state["last_online_time"] = datetime.fromisoformat(raw["last_online_time"])
                state["offline_count_today"] = int(raw.get("offline_count_today", 0))
                state["last_day"] = int(raw.get("last_day", datetime.now().day))
        except Exception:
            pass
    if state["last_online_time"] is None:
        state["last_online_time"] = datetime.now()
    return state

def save_state(state):
    out = {
        "last_status": state["last_status"],
        "last_offline_time": state["last_offline_time"].isoformat() if state["last_offline_time"] else None,
        "last_online_time": state["last_online_time"].isoformat() if state["last_online_time"] else None,
        "offline_count_today": state["offline_count_today"],
        "last_day": state["last_day"]
    }
    try:
        with open(STATE_FILE, "w") as f:
            json.dump(out, f)
    except Exception:
        pass

def send_telegram(message):
    if not BOT_TOKEN or not CHAT_ID:
        print("[WARN] BOT_TOKEN or CHAT_ID not configured - skipping Telegram send")
        return
    url = f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage"
    payload = {"chat_id": CHAT_ID, "text": message, "parse_mode": "HTML"}
    try:
        resp = requests.post(url, data=payload, timeout=10)
        if resp.status_code != 200:
            print(f"[WARN] Telegram returned {resp.status_code}: {resp.text}")
    except Exception as e:
        print(f"[WARN] Failed to send Telegram: {e}")

# ---------------- safe mwan3 control ----------------
def ubus_iface_up(iface):
    try:
        out = subprocess.check_output(["ubus", "call", f"network.interface.{iface}", "status"], stderr=subprocess.DEVNULL)
        j = json.loads(out.decode("utf-8", "ignore"))
        return bool(j.get("up", False))
    except Exception:
        return None

def run_mwan_cmd(cmd, iface):
    try:
        subprocess.run(["mwan3", cmd, iface], stdout=DEVNULL, stderr=DEVNULL, check=False)
    except Exception:
        pass

def set_mwan_status(wan_up):
    if wan_up:
        # WAN kembali online, jangan matikan WAN2
        subprocess.call(["mwan3", "ifup", "wan"])
        print("[INFO] WAN online, WAN2 tetap aktif.")
    else:
        # WAN offline, aktifkan WAN2 dan matikan WAN
        subprocess.call(["mwan3", "ifdown", "wan"])
        subprocess.call(["mwan3", "ifup", "wan2"])
        print("[INFO] WAN offline, WAN2 aktif.")

# ---------------- formatting ----------------
def human_delta(delta):
    total = int(delta.total_seconds())
    hh = total // 3600
    mm = (total % 3600) // 60
    ss = total % 60
    return f"{hh}h:{mm:02d}m:{ss:02d}s"

# ---------------- main logic ----------------
def check_once():
    state = load_state()
    now = datetime.now()
    if now.day != state["last_day"]:
        state["offline_count_today"] = 0
        state["last_day"] = now.day

    events = collect_events_with_dates(LOG_FILES, WINDOW_SECONDS)
    if not events:
        print(f"[INFO] No recent events found in logs within last {WINDOW_SECONDS} seconds. Time: {now}")
        return

    latest_dt, latest_status, raw_line, src_file = events[-1]
    print(f"[INFO] Latest event: {latest_dt} -> {latest_status} (from {os.path.basename(src_file)})\n  line: {raw_line}")

    if latest_status == "OFFLINE":
        if state["last_status"] != "OFFLINE":
            state["last_offline_time"] = latest_dt
            state["offline_count_today"] = state.get("offline_count_today", 0) + 1
            state["last_status"] = "OFFLINE"
            save_state(state)
            msg = (
                f"🚨 <b>WAN OFFLINE terdeteksi</b>\n"
                f"📅 {latest_dt.strftime('%Y-%m-%d %H:%M:%S')}\n"
                f"❌ Detected by log (file: {os.path.basename(src_file)}): {raw_line}\n"
                f"🔁 Men-switch ke WAN2 sebagai backup (mwan3 ifdown wan; ifup wan2)\n"
                f"🕒 OFFLINE hari ini (terhitung): {state['offline_count_today']} kali"
            )
            print(msg)
            send_telegram(msg)
            set_mwan_status(False)
        else:
            print(f"[INFO] Already OFFLINE. Latest event time: {latest_dt}")
    elif latest_status == "ONLINE":
        if state["last_status"] != "ONLINE":
            offline_duration = (latest_dt - state["last_offline_time"]) if state["last_offline_time"] else timedelta(0)
            online_duration = (latest_dt - state["last_online_time"]) if state["last_online_time"] else timedelta(0)
            msg = (
                f"✅ <b>WAN kembali ONLINE</b>\n"
                f"📅 {latest_dt.strftime('%Y-%m-%d %H:%M:%S')}\n"
                f"📊 OFFLINE hari ini : {state.get('offline_count_today', 0)} kali\n"
                f"⏳ Durasi OFFLINE   : {human_delta(offline_duration)}\n"
                f"⏳ Durasi ONLINE    : {human_delta(online_duration)}\n"
                f"🔁 Mengembalikan WAN utama (mwan3 ifup wan) — WAN2 left active as backup\n"
                f"ℹ️ Detected by log (file: {os.path.basename(src_file)}): {raw_line}"
            )
            print(msg)
            send_telegram(msg)
            set_mwan_status(True)  # note: does NOT ifdown wan2
            state["last_status"] = "ONLINE"
            state["last_online_time"] = latest_dt
            save_state(state)
        else:
            print(f"[INFO] Already ONLINE. Latest event time: {latest_dt}")
    else:
        print(f"[INFO] Latest event status not recognized. Line: {raw_line}")

if __name__ == "__main__":
    check_once()
