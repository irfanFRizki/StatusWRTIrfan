#!/usr/bin/env python3
# /usr/bin/mwan3_check.py
# Cron-friendly. Uses flock lock, --debug to write parsing details to /tmp/mwan3_check.debug.log.
# Requires: python3-requests (opkg install python3-requests)

from datetime import datetime, timedelta
import subprocess
import os
import json
import re
import sys
import hashlib
import time
import argparse

# try fcntl for flock
try:
    import fcntl
    HAS_FCNTL = True
except Exception:
    HAS_FCNTL = False

# requests import
try:
    import requests
except Exception:
    print("ERROR: python requests module not found. Install with: opkg install python3-requests")
    sys.exit(1)

# ================= CONFIG =================
BOT_TOKEN = "6901960737:AAEUEW0ZLHqRC1dwgol019_oo14zVF82xc8"
CHAT_ID = "5645537022"

LOG_FILES = [
    "/tmp/autoip-all-rakitan.log",
    "/tmp/autoip-all-rakitan.log.1"
]

OFFLINE_PATTERNS = [ r"Status:\s*OFFLINE", r"status:\s*ping failed", r"100\.00% failed" ]
OFFLINE_EXTRA_PATTERNS = [ r"Trying to refresh IP address", r"IP change received", r"\[IFDOWN\s+wan\]", r"\bIFDOWN wan\b" ]
ONLINE_PATTERNS = [ r"status:\s*ONLINE", r"Status:\s*ONLINE", r"🟢 Berhasil memperbarui IP Address", r"New WAN IP", r"\[GET IP\]\s*New WAN IP" ]

STATE_FILE = "/tmp/mwan3_check_state.json"
LOCK_FILE = "/tmp/mwan3_check.lock"   # flock file
DEBUG_LOG = "/tmp/mwan3_check.debug.log"

# dedupe TTL for identical messages (seconds)
MSG_DUP_TTL = 300

# scanning options
TAIL_READ_LINES = 2000
WINDOW_SECONDS = 60   # <-- changed as requested

DEVNULL = open(os.devnull, "wb")

# -------------------------------------------
# utility: debug logging (only if --debug)
# -------------------------------------------
debug_enabled = False

def debug_init(enabled):
    global debug_enabled
    debug_enabled = bool(enabled)
    if debug_enabled:
        try:
            # if debug log older than 48h, truncate it
            if os.path.exists(DEBUG_LOG):
                mtime = os.path.getmtime(DEBUG_LOG)
                if time.time() - mtime > 48 * 3600:
                    with open(DEBUG_LOG, "w"):
                        pass  # truncate
        except Exception:
            pass

def debug(msg):
    if not debug_enabled:
        return
    try:
        now = datetime.now().isoformat()
        with open(DEBUG_LOG, "a", encoding="utf-8", errors="ignore") as f:
            f.write(f"{now} {msg}\n")
    except Exception:
        pass

# -------------------------------------------
# locking via flock
# -------------------------------------------
lock_fd = None
def acquire_lock():
    global lock_fd
    try:
        # open lock file
        lock_fd = open(LOCK_FILE, "w")
        if HAS_FCNTL:
            try:
                fcntl.flock(lock_fd.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                debug("acquired flock lock")
                return True
            except BlockingIOError:
                debug("flock locked by another process")
                return False
            except Exception as e:
                debug(f"flock acquire error: {e}")
                return False
        else:
            # fallback: try create dir as lock
            try:
                os.mkdir(LOCK_FILE + ".dir")
                debug("acquired fallback dir lock")
                return True
            except FileExistsError:
                debug("fallback dir lock exists")
                return False
            except Exception as e:
                debug(f"fallback lock error: {e}")
                return False
    except Exception as e:
        debug(f"open lock file error: {e}")
        return False

def release_lock():
    global lock_fd
    try:
        if HAS_FCNTL and lock_fd:
            try:
                fcntl.flock(lock_fd.fileno(), fcntl.LOCK_UN)
            except Exception:
                pass
            try:
                lock_fd.close()
            except Exception:
                pass
            # remove lock file if empty (best-effort)
            try:
                if os.path.exists(LOCK_FILE) and os.path.getsize(LOCK_FILE) == 0:
                    os.remove(LOCK_FILE)
            except Exception:
                pass
            debug("released flock lock")
        else:
            # fallback remove dir
            try:
                if os.path.isdir(LOCK_FILE + ".dir"):
                    os.rmdir(LOCK_FILE + ".dir")
                    debug("released fallback dir lock")
            except Exception:
                pass
    except Exception:
        pass

# -------------------------------------------
# file/timestamp parsing helpers
# -------------------------------------------
_re_full = re.compile(r'(\d{2}-[A-Za-z]{3}-\d{4} \d{2}:\d{2}:\d{2})')
_re_dayname = re.compile(r'([A-Za-z]+ \d{2}-[A-Za-z]{3}-\d{4} \d{2}:\d{2}:\d{2})')
_re_time_only = re.compile(r'\[\s*(\d{2}:\d{2}:\d{2})\s*\]')
_re_time_short = re.compile(r'(\d{2}-[A-Za-z]{3}-\d{4})')

def read_all_lines(path):
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            return f.read().splitlines()
    except Exception:
        return []

def parse_dt_from_line(line, last_date_ctx):
    # 1) full timestamp
    m = _re_full.search(line)
    if m:
        try:
            dt = datetime.strptime(m.group(1), "%d-%b-%Y %H:%M:%S")
            return dt, dt.date()
        except Exception as e:
            debug(f"parse full ts error: {e} for {m.group(1)}")
    # 2) dayname + timestamp
    m = _re_dayname.search(line)
    if m:
        tok = m.group(1)
        try:
            try:
                dt = datetime.strptime(tok, "%A %d-%b-%Y %H:%M:%S")
            except Exception:
                dt = datetime.strptime(tok.split(" ", 1)[1], "%d-%b-%Y %H:%M:%S")
            return dt, dt.date()
        except Exception as e:
            debug(f"parse dayname ts error: {e} for {tok}")
    # 3) TIME header
    m = re.search(r'TIME\s*:\s*([A-Za-z]+ \d{2}-[A-Za-z]{3}-\d{4} \d{2}:\d{2}:\d{2})', line)
    if m:
        try:
            dt = datetime.strptime(m.group(1), "%A %d-%b-%Y %H:%M:%S")
            return dt, dt.date()
        except Exception:
            try:
                dt = datetime.strptime(m.group(1).split(" ",1)[1], "%d-%b-%Y %H:%M:%S")
                return dt, dt.date()
            except Exception as e:
                debug(f"parse TIME header error: {e} for {m.group(1)}")
    # 4) time-only [HH:MM:SS]
    m = _re_time_only.search(line)
    if m and last_date_ctx:
        timestr = m.group(1)
        try:
            dt = datetime.strptime(f"{last_date_ctx.strftime('%d-%b-%Y')} {timestr}", "%d-%b-%Y %H:%M:%S")
            return dt, last_date_ctx
        except Exception as e:
            debug(f"parse time-only error: {e} for {timestr}")
    # 5) date + time snippet
    m = _re_time_short.search(line)
    if m:
        try:
            datepart = m.group(1)
            m2 = re.search(r'(\d{2}:\d{2}:\d{2})', line)
            if m2:
                dt = datetime.strptime(f"{datepart} {m2.group(1)}", "%d-%b-%Y %H:%M:%S")
                return dt, dt.date()
        except Exception as e:
            debug(f"parse date+time snippet error: {e} for {line}")
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
                    debug(f"collected event: {dt} {status} from {p} line: {ln_stripped}")
    events.sort(key=lambda x: x[0])
    return events

# -------------------------------------------
# state persistence & dedupe
# -------------------------------------------
def load_state():
    state = {
        "last_status": None,
        "last_offline_time": None,
        "last_online_time": None,
        "offline_count_today": 0,
        "last_day": datetime.now().day,
        "last_msg_hash": None,
        "last_msg_time": None
    }
    if os.path.exists(STATE_FILE):
        try:
            with open(STATE_FILE, "r") as f:
                raw = json.load(f)
                state["last_status"] = raw.get("last_status")
                if raw.get("last_offline_time"):
                    try:
                        state["last_offline_time"] = datetime.fromisoformat(raw["last_offline_time"])
                    except Exception:
                        state["last_offline_time"] = None
                if raw.get("last_online_time"):
                    try:
                        state["last_online_time"] = datetime.fromisoformat(raw["last_online_time"])
                    except Exception:
                        state["last_online_time"] = None
                state["offline_count_today"] = int(raw.get("offline_count_today", 0))
                state["last_day"] = int(raw.get("last_day", datetime.now().day))
                state["last_msg_hash"] = raw.get("last_msg_hash")
                if raw.get("last_msg_time"):
                    try:
                        state["last_msg_time"] = datetime.fromisoformat(raw["last_msg_time"])
                    except Exception:
                        state["last_msg_time"] = None
        except Exception as e:
            debug(f"load_state error: {e}")
    if state["last_online_time"] is None:
        state["last_online_time"] = datetime.now()
    return state

def save_state(state):
    out = {
        "last_status": state.get("last_status"),
        "last_offline_time": state.get("last_offline_time").isoformat() if state.get("last_offline_time") else None,
        "last_online_time": state.get("last_online_time").isoformat() if state.get("last_online_time") else None,
        "offline_count_today": state.get("offline_count_today", 0),
        "last_day": state.get("last_day", datetime.now().day),
        "last_msg_hash": state.get("last_msg_hash"),
        "last_msg_time": state.get("last_msg_time").isoformat() if state.get("last_msg_time") else None
    }
    try:
        with open(STATE_FILE, "w") as f:
            json.dump(out, f)
    except Exception as e:
        debug(f"save_state error: {e}")

def msg_hash(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()

def should_send_message(state, text):
    h = msg_hash(text)
    now = datetime.now()
    last_h = state.get("last_msg_hash")
    last_t = state.get("last_msg_time")
    if last_h and last_h == h and last_t:
        if isinstance(last_t, str):
            try:
                last_t = datetime.fromisoformat(last_t)
            except Exception:
                last_t = None
        if last_t and (now - last_t).total_seconds() <= MSG_DUP_TTL:
            debug("should_send_message: suppressed due to duplicate within TTL")
            return False
    return True

def send_telegram_dedup(state, text):
    h = msg_hash(text)
    now = datetime.now()
    # persist hash/time BEFORE sending to avoid races
    state["last_msg_hash"] = h
    state["last_msg_time"] = now
    save_state(state)
    if not BOT_TOKEN or not CHAT_ID:
        debug("send_telegram_dedup: BOT_TOKEN/CHAT_ID not set")
        return False
    url = f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage"
    payload = {"chat_id": CHAT_ID, "text": text, "parse_mode": "HTML"}
    try:
        resp = requests.post(url, data=payload, timeout=10)
        debug(f"telegram response: {resp.status_code} {resp.text[:200]}")
        if resp.status_code != 200:
            debug(f"telegram send non-200: {resp.status_code}")
        return True
    except Exception as e:
        debug(f"telegram send error: {e}")
        return False

# -------------------------------------------
# safe mwan3 control (ubus + run)
# -------------------------------------------
def ubus_iface_up(iface):
    try:
        out = subprocess.check_output(["ubus", "call", f"network.interface.{iface}", "status"], stderr=subprocess.DEVNULL)
        j = json.loads(out.decode("utf-8", "ignore"))
        return bool(j.get("up", False))
    except Exception as e:
        debug(f"ubus_iface_up error for {iface}: {e}")
        return None

def run_mwan_cmd(cmd, iface):
    try:
        subprocess.run(["mwan3", cmd, iface], stdout=DEVNULL, stderr=DEVNULL, check=False)
    except Exception as e:
        debug(f"run_mwan_cmd error: {e}")

def set_mwan_status(wan_up):
    wan_state = ubus_iface_up("wan")
    wan2_state = ubus_iface_up("wan2")
    if wan_up:
        if wan_state is True:
            debug("set_mwan_status: WAN already UP according to ubus -> skipping ifup")
            return
        debug("set_mwan_status: running 'mwan3 ifup wan' (leave wan2 active)")
        run_mwan_cmd("ifup", "wan")
    else:
        if wan_state is False and wan2_state is True:
            debug("set_mwan_status: desired state already set (wan down, wan2 up) -> skip")
            return
        debug("set_mwan_status: running 'mwan3 ifdown wan' then 'mwan3 ifup wan2'")
        run_mwan_cmd("ifdown", "wan")
        time.sleep(0.8)
        run_mwan_cmd("ifup", "wan2")

# -------------------------------------------
# formatting
# -------------------------------------------
def human_delta(delta):
    total = int(delta.total_seconds())
    hh = total // 3600
    mm = (total % 3600) // 60
    ss = total % 60
    return f"{hh}h:{mm:02d}m:{ss:02d}s"

# -------------------------------------------
# main logic
# -------------------------------------------
def check_once():
    state = load_state()
    now = datetime.now()
    if now.day != state.get("last_day", now.day):
        state["offline_count_today"] = 0
        state["last_day"] = now.day
        debug("daily counter reset")

    events = collect_events_with_dates(LOG_FILES, WINDOW_SECONDS)
    if not events:
        debug(f"No recent events within last {WINDOW_SECONDS}s; now={now}")
        print(f"[INFO] No recent events found in logs within last {WINDOW_SECONDS} seconds. Time: {now}")
        return

    latest_dt, latest_status, raw_line, src_file = events[-1]
    debug(f"latest event chosen: {latest_dt} {latest_status} from {src_file} line:{raw_line}")
    print(f"[INFO] Latest event: {latest_dt} -> {latest_status} (from {os.path.basename(src_file)})")

    if latest_status == "OFFLINE":
        if state.get("last_status") != "OFFLINE":
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
            debug(f"prepared OFFLINE msg hash: {msg_hash(msg)}")
            if should_send_message(state, msg):
                set_mwan_status(False)
                send_telegram_dedup(state, msg)
                print("[INFO] OFFLINE action + notification sent")
            else:
                debug("OFFLINE: duplicate suppressed")
                print("[INFO] Duplicate OFFLINE message suppressed.")
        else:
            print(f"[INFO] Already OFFLINE. Latest event time: {latest_dt}")
            debug("no-op: already OFFLINE")

    elif latest_status == "ONLINE":
        if state.get("last_status") != "ONLINE":
            offline_duration = (latest_dt - state["last_offline_time"]) if state.get("last_offline_time") else timedelta(0)
            online_duration = (latest_dt - state["last_online_time"]) if state.get("last_online_time") else timedelta(0)
            state["last_status"] = "ONLINE"
            state["last_online_time"] = latest_dt
            save_state(state)
            msg = (
                f"✅ <b>WAN kembali ONLINE</b>\n"
                f"📅 {latest_dt.strftime('%Y-%m-%d %H:%M:%S')}\n"
                f"📊 OFFLINE hari ini : {state.get('offline_count_today', 0)} kali\n"
                f"⏳ Durasi OFFLINE   : {human_delta(offline_duration)}\n"
                f"⏳ Durasi ONLINE    : {human_delta(online_duration)}\n"
                f"🔁 Mengembalikan WAN utama (mwan3 ifup wan) — WAN2 left active as backup\n"
                f"ℹ️ Detected by log (file: {os.path.basename(src_file)}): {raw_line}"
            )
            debug(f"prepared ONLINE msg hash: {msg_hash(msg)}")
            if should_send_message(state, msg):
                set_mwan_status(True)
                send_telegram_dedup(state, msg)
                print("[INFO] ONLINE action + notification sent")
            else:
                debug("ONLINE: duplicate suppressed")
                print("[INFO] Duplicate ONLINE message suppressed.")
        else:
            print(f"[INFO] Already ONLINE. Latest event time: {latest_dt}")
            debug("no-op: already ONLINE")
    else:
        debug(f"latest event has unknown status: {latest_status} line: {raw_line}")
        print("[INFO] Latest event status not recognized.")

# -------------------------------------------
# entrypoint
# -------------------------------------------
def main():
    parser = argparse.ArgumentParser(description="MWAN3 failover checker (cron-friendly)")
    parser.add_argument("--debug", action="store_true", help="enable debug logging to /tmp/mwan3_check.debug.log")
    args = parser.parse_args()
    debug_init(args.debug)
    if not acquire_lock():
        debug("another instance running - exiting")
        print("[INFO] Another instance running - exiting.")
        return
    try:
        check_once()
    finally:
        release_lock()

if __name__ == "__main__":
    main()
