#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
vpn_telegram_monitor.py
Script untuk memonitor koneksi VPN via WebSocket, menghitung traffic per kategori
(Sosial Media, Game, Belanja), dan mengirim laporan ke Telegram Bot.
"""
import os
import sys
import json
import requests
import websocket
from datetime import datetime
from collections import defaultdict

# Konfigurasi lewat env var atau hardcode:
TELEGRAM_TOKEN   = os.getenv('TELEGRAM_TOKEN')   or '6901960737:AAEUEW0ZLHqRC1dwgol019_oo14zVF82xc8'
TELEGRAM_CHAT_ID = os.getenv('TELEGRAM_CHAT_ID') or '5645537022'
WS_URL           = os.getenv('VPN_WS_URL')      or 'ws://192.168.1.1:9090/connections?token=rizkikotet'
IP_MAPPING_URL   = os.getenv('VPN_IP_URL')      or 'http://192.168.1.1/cgi-bin/get_ips'

# Keywords kategori
SOCIAL_KEYS = ["youtube","tiktok","instagram","fb"]
GAME_KEYS   = ["roblox","ml","freefire","pubg"]
SHOP_KEYS   = ["shopee","tokopedia","blibli"]

# Mapping nama sederhana
SIMPLE_MAP = {
    'youtube': 'YouTube', 'tiktok': 'TikTok', 'instagram': 'Instagram', 'fb': 'Facebook',
    'roblox': 'Roblox', 'ml': 'Mobile Legends', 'freefire': 'Free Fire', 'pubg': 'PUBG Mobile',
    'shopee': 'Shopee', 'tokopedia': 'Tokopedia', 'blibli': 'Blibli'
}

# Emoji mapping untuk kategori
CATEGORY_EMOJIS = {
    'Sosial Media': '📱',
    'Game': '🎮',
    'Belanja': '🛒'
}

def fetch_ip_mapping():
    try:
        res = requests.get(IP_MAPPING_URL, timeout=5)
        res.raise_for_status()
        return res.json()
    except Exception as e:
        print(f'Gagal fetch IP mapping: {e}', file=sys.stderr)
        return {}

def fetch_connections():
    try:
        ws = websocket.create_connection(WS_URL, timeout=5)
        msg = ws.recv()
        ws.close()
        return json.loads(msg).get('connections', [])
    except Exception as e:
        print(f'Gagal fetch connections: {e}', file=sys.stderr)
        return []

def categorize(host):
    h = host.lower()
    for k in SOCIAL_KEYS:
        if k in h:
            return 'Sosial Media', k
    for k in GAME_KEYS:
        if k in h:
            return 'Game', k
    for k in SHOP_KEYS:
        if k in h:
            return 'Belanja', k
    return None, None

def human_readable(n):
    units = ['Bytes','KB','MB','GB','TB']
    for idx, unit in enumerate(units):
        if n < 1024 or unit == 'TB':
            return f"{n / (1024 ** idx):.2f} {unit}"
        n /= 1024

def process(conns, ip_map):
    devices = {}
    global_cat = defaultdict(int)

    for c in conns:
        ip = c.get('metadata', {}).get('sourceIP')
        host = c.get('metadata', {}).get('host', '')
        if not ip or not host:
            continue
        name = ip_map.get(ip, ip)
        bw = (c.get('upload') or 0) + (c.get('download') or 0)
        info = devices.setdefault(name, {'bw': 0, 'count': 0, 'last': '', 'cats': defaultdict(int), 'details': defaultdict(lambda: defaultdict(int))})
        info['bw'] += bw
        info['count'] += 1
        info['last'] = c.get('start', '')[:10]
        cat, keyword = categorize(host)
        if cat and keyword:
            info['cats'][cat] += bw
            info['details'][cat][keyword] += bw
            global_cat[cat] += bw
    return devices, global_cat

def format_message(devices, global_cat):
    now = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    
    # Header dengan visual yang lebih menarik
    lines = [
        "🔒 <b>VPN TRAFFIC MONITOR</b> 🔒",
        "━━━━━━━━━━━━━━━━━━━━━━━━━━",
        f"⏱ <i>Update Terakhir</i>: <code>{now}</code>",
        ""
    ]
    
    # Bagian perangkat aktif
    lines.append(f"📱 <b>PERANGKAT AKTIF</b> ({len(devices)})")
    if not devices:
        lines.append("   └ <i>Tidak ada koneksi aktif</i>")
    else:
        for name, info in devices.items():
            device_line = [
                f"┌ <b>📱 {name}</b>",
                f"├ 📊 Traffic: <code>{human_readable(info['bw'])}</code>",
                f"├ 🔗 Koneksi: <code>{info['count']}</code>",
                f"└ ⏱ Terakhir: <code>{info['last']}</code>"
            ]
            
            # Tambahkan detail kategori
            if info['cats']:
                device_line.append("   └ <b>KATEGORI:</b>")
                for cat, bw in info['cats'].items():
                    emoji = CATEGORY_EMOJIS.get(cat, '▫️')
                    detail_str = ', '.join(
                        f"{SIMPLE_MAP.get(k, k)}: {human_readable(v)}" 
                        for k, v in info['details'][cat].items()
                    )
                    device_line.append(f"      {emoji} <b>{cat}</b>: {detail_str}")
            
            lines.extend(device_line)
            lines.append("")  # Spasi antar perangkat

    # Ringkasan global dengan progress bar visual
    lines.append("🌐 <b>RINGKASAN GLOBAL</b>")
    for cat in ['Sosial Media', 'Game', 'Belanja']:
        emoji = CATEGORY_EMOJIS.get(cat, '▫️')
        traffic = global_cat.get(cat, 0)
        lines.append(f"   {emoji} <b>{cat}</b>: <code>{human_readable(traffic)}</code>")
    
    # Footer dengan informasi tambahan
    lines.extend([
        "",
        "━━━━━━━━━━━━━━━━━━━━━━━━━━",
        "⚡ <i>Laporan otomatis • VPN Monitoring</i> ⚡"
    ])
    
    return "\n".join(lines)

def send_telegram(token, chat_id, text):
    url = f"https://api.telegram.org/bot{token}/sendMessage"
    payload = {
        'chat_id': chat_id,
        'text': text,
        'parse_mode': 'HTML',
        'disable_web_page_preview': True
    }
    try:
        resp = requests.post(url, json=payload, timeout=10)
        resp.raise_for_status()
    except Exception as e:
        print(f'Gagal mengirim ke Telegram: {e}', file=sys.stderr)

def main():
    ip_map = fetch_ip_mapping()
    conns = fetch_connections()
    devices, global_cat = process(conns, ip_map)
    msg = format_message(devices, global_cat)
    send_telegram(TELEGRAM_TOKEN, TELEGRAM_CHAT_ID, msg)
    print('Pesan berhasil dikirim.')

if __name__ == '__main__':
    main()