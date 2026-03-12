#!/usr/bin/env python3
import subprocess
import os
import re
from datetime import datetime

# Path konfigurasi
BASE_DIR = "/"
ONLINE_SCRIPT = os.path.join(BASE_DIR, "usr/bin/online.sh")
ALLOWED_IPS_FILE = os.path.join(BASE_DIR, "etc/allowed_ips.conf")
KICKED_IPS_FILE = os.path.join(BASE_DIR, "etc/kicked_ips.conf")
NOTIFIED_LOG_FILE = os.path.join(BASE_DIR, "etc/notified_ips.log")
SEND_TELEGRAM = os.path.join(BASE_DIR, "usr/bin/send_telegram.py")
ADMIN_PANEL_URL = "https://ip.irfanfajarrizki.my.id/list.html"

# Load daftar IP dari file .conf
def load_ip_list(filepath):
    ip_set = set()
    if os.path.exists(filepath):
        with open(filepath, "r") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                ip = line.split(",")[0].strip()
                ip_set.add(ip)
    return ip_set

# Load daftar IP yang sudah dikirim notifikasi
def load_notified_ips(filepath):
    ip_set = set()
    if os.path.exists(filepath):
        with open(filepath, "r") as f:
            for line in f:
                ip_set.add(line.strip())
    return ip_set

# Simpan IP yang sudah dikirim agar tidak dikirim ulang
def save_notified_ip(filepath, ip):
    with open(filepath, "a") as f:
        f.write(ip + "\n")

# Parsing output dari online.sh
def parse_online_output(output):
    devices = []
    lines = output.strip().splitlines()
    for line in lines:
        match = re.match(
            r"IP:\s*([\d\.]+),\s*MAC:\s*([0-9a-f:]+),\s*Hostname:\s*(.*?),\s*Status:\s*(.+)",
            line.strip(), re.IGNORECASE)
        if match:
            ip = match.group(1)
            mac = match.group(2)
            hostname = match.group(3) or "-"
            wifi_status = match.group(4)
            devices.append({
                "ip": ip.strip(),
                "mac": mac.strip(),
                "hostname": hostname.strip(),
                "wifi_status": wifi_status.strip()
            })
    return devices

# Kirim pesan Telegram untuk IP baru
def send_telegram_message(device):
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    message = (
        "🔔 **BOSS, ADA IP BARU!** 🔔\n"
        "══════════════════════════\n"
        f"📛 Nama Perangkat: {device['hostname']}\n"
        f"🆔 IP\t\t: {device['ip']}\n"
        f"📡 MAC\t\t: {device['mac']}\n"
        f"🌐 Status WIFI\t: {device['wifi_status']}\n"
        f"🕒 Waktu Deteksi\t: {now}\n"
        "🚩 Status\t\t: **IP BARU**\n"
        "══════════════════════════\n"
        f"🖥️ Panel Admin\t: {ADMIN_PANEL_URL}\n"
        "ℹ️ __Pantau terus di panel admin untuk aksi lebih lanjut__"
    )
    subprocess.run(["python3", SEND_TELEGRAM, message])

# Kirim warning harian jika ada IP belum dipindahkan ke allowed/kicked
def send_pending_ips_warning():
    notified_ips = load_notified_ips(NOTIFIED_LOG_FILE)
    allowed_ips = load_ip_list(ALLOWED_IPS_FILE)
    kicked_ips = load_ip_list(KICKED_IPS_FILE)

    pending_ips = sorted(notified_ips - allowed_ips - kicked_ips)
    if pending_ips:
        now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        message = (
            "⚠️ **PERINGATAN HARIAN!** ⚠️\n"
            "══════════════════════════\n"
            f"📅 Tanggal: {now}\n"
            f"🚨 Terdapat **{len(pending_ips)} IP** yang belum didaftarkan!\n"
            "Daftar IP:\n"
            + "\n".join(f"• {ip}" for ip in pending_ips)
            + "\n══════════════════════════\n"
            f"🖥️ Panel Admin\t: {ADMIN_PANEL_URL}\n"
            "📌 **Segera masukkan ke allowed/kicked list sesuai kebutuhan.**"
        )
        subprocess.run(["python3", SEND_TELEGRAM, message])

# Fungsi utama
def main():
    try:
        result = subprocess.run([ONLINE_SCRIPT], capture_output=True, text=True, check=True)
    except subprocess.CalledProcessError as e:
        print("Gagal menjalankan online.sh:", e)
        return

    devices = parse_online_output(result.stdout)
    allowed_ips = load_ip_list(ALLOWED_IPS_FILE)
    kicked_ips = load_ip_list(KICKED_IPS_FILE)
    notified_ips = load_notified_ips(NOTIFIED_LOG_FILE)

    for dev in devices:
        ip = dev["ip"].strip()
        if ip not in allowed_ips and ip not in kicked_ips and ip not in notified_ips:
            print(f"📢 Deteksi IP baru: {ip}")
            send_telegram_message(dev)
            save_notified_ip(NOTIFIED_LOG_FILE, ip)

if __name__ == "__main__":
    main()

    # Kirim warning 1x per hari, misal pukul 07:00–07:04
    now = datetime.now()
    if now.hour == 7 and now.minute < 5:
        send_pending_ips_warning()
