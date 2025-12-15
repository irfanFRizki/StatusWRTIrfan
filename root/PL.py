#!/usr/bin/env python3
"""
PACKING LIST MONITOR BOT - Python Version (Public Sheets)
Bot Telegram untuk monitoring packing list dari Google Sheets public
Tidak memerlukan Google Service Account
"""

import os
import json
import logging
import sqlite3
import re
import requests
from datetime import datetime, timedelta
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, ReplyKeyboardMarkup, KeyboardButton
from telegram.ext import (
    Application,
    CommandHandler,
    CallbackQueryHandler,
    MessageHandler,
    filters,
    ContextTypes,
)

# ==========================================
# KONFIGURASI
# ==========================================

# Telegram Bot Token
TELEGRAM_TOKEN = "8504765068:AAE4T9AGMuWmFFYE8SkFpw6ahvkzb8V5vgg"

# Admin Chat ID untuk notifikasi
ADMIN_CHAT_ID = "5645537022"

# Google Sheets Public URL (bit.ly atau direct link)
# Format: https://docs.google.com/spreadsheets/d/{SHEET_ID}/edit
SHEET_URL = "https://docs.google.com/spreadsheets/d/1xeq7mUWk--Nar82WX-mmGAsELGsl9OdX4s1Prvfpnic/edit?usp=sharing"

# Sheet names
SHEET_PACKING_LIST = "2025"
SHEET_BOX = "BOX"

# Database untuk tracking
DB_FILE = "/root/packing_list_tracker.db"

# Cache duration (dalam detik) - untuk mengurangi request ke Google Sheets
CACHE_DURATION = 300  # 5 menit

# Logging
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO
)
logger = logging.getLogger(__name__)

# Global cache
_cache = {
    'data': {},
    'timestamp': {}
}

# ==========================================
# DATABASE INITIALIZATION
# ==========================================

def init_database():
    """Inisialisasi database SQLite untuk tracking"""
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS notified_packing_lists (
            packing_list TEXT PRIMARY KEY,
            notified_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS notified_h3 (
            packing_list TEXT PRIMARY KEY,
            est_bongkar DATE,
            notified_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS notified_box_images (
            jenis_barang TEXT,
            kirim_via TEXT,
            tanggal_kirim TEXT,
            PRIMARY KEY (jenis_barang, kirim_via, tanggal_kirim)
        )
    ''')
    
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS sheet_id_cache (
            id INTEGER PRIMARY KEY,
            sheet_id TEXT,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    
    conn.commit()
    conn.close()

# ==========================================
# GOOGLE SHEETS PUBLIC ACCESS
# ==========================================

def resolve_short_url(short_url):
    """Resolve bit.ly atau short URL ke full URL"""
    try:
        response = requests.head(short_url, allow_redirects=True, timeout=10)
        return response.url
    except Exception as e:
        logger.error(f"Error resolving short URL: {e}")
        return short_url

def extract_sheet_id(url):
    """Extract Sheet ID dari URL Google Sheets"""
    try:
        # Pattern untuk Google Sheets URL
        pattern = r'/spreadsheets/d/([a-zA-Z0-9-_]+)'
        match = re.search(pattern, url)
        
        if match:
            return match.group(1)
        
        logger.error(f"Cannot extract Sheet ID from URL: {url}")
        return None
        
    except Exception as e:
        logger.error(f"Error extracting sheet ID: {e}")
        return None

def get_sheet_id():
    """Get Sheet ID dengan caching"""
    try:
        # Check cache di database
        conn = sqlite3.connect(DB_FILE)
        cursor = conn.cursor()
        
        cursor.execute('SELECT sheet_id, updated_at FROM sheet_id_cache WHERE id = 1')
        result = cursor.fetchone()
        
        if result:
            sheet_id, updated_at = result
            # Cache valid untuk 1 hari
            cache_time = datetime.strptime(updated_at, '%Y-%m-%d %H:%M:%S')
            if (datetime.now() - cache_time).days < 1:
                conn.close()
                return sheet_id
        
        # Resolve URL dan extract ID
        logger.info("Resolving Sheet URL...")
        full_url = resolve_short_url(SHEET_URL)
        sheet_id = extract_sheet_id(full_url)
        
        if sheet_id:
            # Save to cache
            cursor.execute('''
                INSERT OR REPLACE INTO sheet_id_cache (id, sheet_id, updated_at) 
                VALUES (1, ?, datetime('now'))
            ''', (sheet_id,))
            conn.commit()
            logger.info(f"Sheet ID cached: {sheet_id}")
        
        conn.close()
        return sheet_id
        
    except Exception as e:
        logger.error(f"Error getting sheet ID: {e}")
        return None

def get_sheet_data_csv(sheet_name):
    """Ambil data dari Google Sheets menggunakan CSV export (public)"""
    try:
        sheet_id = get_sheet_id()
        if not sheet_id:
            return None
        
        # Check cache
        cache_key = f"{sheet_id}_{sheet_name}"
        if cache_key in _cache['data']:
            cache_time = _cache['timestamp'].get(cache_key, 0)
            if (datetime.now().timestamp() - cache_time) < CACHE_DURATION:
                logger.info(f"Using cached data for {sheet_name}")
                return _cache['data'][cache_key]
        
        # Google Sheets CSV export URL
        # Format: https://docs.google.com/spreadsheets/d/{SHEET_ID}/gviz/tq?tqx=out:csv&sheet={SHEET_NAME}
        csv_url = f"https://docs.google.com/spreadsheets/d/{sheet_id}/gviz/tq?tqx=out:csv&sheet={sheet_name}"
        
        logger.info(f"Fetching data from: {sheet_name}")
        response = requests.get(csv_url, timeout=30)
        
        if response.status_code == 200:
            # Parse CSV
            import csv
            from io import StringIO
            
            csv_data = StringIO(response.text)
            reader = csv.reader(csv_data)
            data = list(reader)
            
            # Cache data
            _cache['data'][cache_key] = data
            _cache['timestamp'][cache_key] = datetime.now().timestamp()
            
            logger.info(f"Successfully fetched {len(data)} rows from {sheet_name}")
            return data
        else:
            logger.error(f"Failed to fetch data: HTTP {response.status_code}")
            return None
            
    except Exception as e:
        logger.error(f"Error fetching sheet data: {e}")
        return None

# ==========================================
# HELPER FUNCTIONS
# ==========================================

def format_tanggal(date_str):
    """Format tanggal ke format Indonesia"""
    if not date_str or date_str == '':
        return '-'
    
    try:
        formats = ['%d/%m/%Y', '%Y-%m-%d', '%m/%d/%Y', '%d-%m-%Y']
        date_obj = None
        
        for fmt in formats:
            try:
                date_obj = datetime.strptime(str(date_str), fmt)
                break
            except:
                continue
        
        if not date_obj:
            return date_str
        
        bulan = [
            'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
            'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
        ]
        
        return f"{date_obj.day} {bulan[date_obj.month - 1]} {date_obj.year}"
    except:
        return date_str

def parse_float(value):
    """Parse value ke float, return 0 jika gagal"""
    try:
        # Remove comma if exists
        if isinstance(value, str):
            value = value.replace(',', '')
        return float(value) if value else 0
    except:
        return 0

def format_koli(value):
    """Format nilai koli tanpa desimal"""
    try:
        koli = int(float(value))
        return f"{koli} Koli"
    except:
        return "0 Koli"

def extract_container_name(packing_list):
    """Extract nama container dari packing list"""
    # Cari text dalam kurung
    match = re.search(r'\(([^)]+)\)', packing_list)
    if match:
        return match.group(1)
    
    # Jika tidak ada kurung, ambil prefix
    match = re.match(r'^([A-Z]+)', packing_list)
    if match:
        return match.group(1)
    
    return 'Lainnya'

# ==========================================
# KEYBOARD
# ==========================================

def get_main_keyboard():
    """Keyboard utama dengan inline buttons untuk menu utama"""
    keyboard = [
        [
            InlineKeyboardButton("📦 Cek Semua", callback_data="cek_all"),
            InlineKeyboardButton("🚢 Container", callback_data="cek_container")
        ],
        [
            InlineKeyboardButton("📦 Box", callback_data="cek_box"),
            InlineKeyboardButton("🚚 Metro", callback_data="cek_metro")
        ]
    ]
    return InlineKeyboardMarkup(keyboard)

def get_reply_keyboard():
    """Reply keyboard dengan menu, help, refresh"""
    keyboard = [
        [
            KeyboardButton("📋 Menu"),
            KeyboardButton("ℹ️ Help"),
            KeyboardButton("🔄 Refresh")
        ]
    ]
    return ReplyKeyboardMarkup(keyboard, resize_keyboard=True)

# ==========================================
# COMMAND HANDLERS
# ==========================================

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk command /start"""
    msg = (
        "👋 *Selamat Datang di Packing List Monitor Bot!*\n\n"
        "Bot ini membantu Anda memantau status packing list.\n\n"
        "Pilih menu di bawah untuk memulai:"
    )
    
    await update.message.reply_text(
        msg,
        parse_mode='Markdown',
        reply_markup=get_main_keyboard()
    )
    
    # Kirim reply keyboard
    await update.message.reply_text(
        "Gunakan tombol di bawah untuk navigasi cepat:",
        reply_markup=get_reply_keyboard()
    )

async def menu_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk command /menu"""
    msg = "📋 *MENU UTAMA*\n\nPilih menu yang Anda inginkan:"
    
    await update.message.reply_text(
        msg,
        parse_mode='Markdown',
        reply_markup=get_main_keyboard()
    )

# ==========================================
# MESSAGE HANDLERS (untuk KeyboardButton)
# ==========================================

async def handle_keyboard_button(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk keyboard button (Menu, Help, Refresh)"""
    text = update.message.text
    
    if text == "📋 Menu":
        msg = "📋 *MENU UTAMA*\n\nPilih menu yang Anda inginkan:"
        await update.message.reply_text(
            msg,
            parse_mode='Markdown',
            reply_markup=get_main_keyboard()
        )
    
    elif text == "ℹ️ Help":
        msg = get_help_text()
        await update.message.reply_text(
            msg,
            parse_mode='Markdown'
        )
    
    elif text == "🔄 Refresh":
        # Clear cache
        _cache['data'].clear()
        _cache['timestamp'].clear()
        msg = "🔄 *Cache telah di-refresh!*\n\nSilakan pilih menu lagi untuk melihat data terbaru."
        await update.message.reply_text(
            msg,
            parse_mode='Markdown',
            reply_markup=get_main_keyboard()
        )

# ==========================================
# CALLBACK QUERY HANDLERS
# ==========================================

async def button_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk button callback"""
    query = update.callback_query
    await query.answer()
    
    callback_data = query.data
    
    # Show loading message
    loading_msg = "⏳ Mengambil data..."
    await query.edit_message_text(text=loading_msg)
    
    try:
        if callback_data == "cek_all":
            result = cek_packing_list_all()
            
        elif callback_data == "cek_container":
            result = cek_container()
            
        elif callback_data == "cek_box":
            result = cek_box()
            
        elif callback_data == "cek_metro":
            result = cek_metro()
        
        else:
            result = "❌ Perintah tidak dikenali"
        
        # Split message if too long (Telegram limit 4096 characters)
        if len(result) > 4000:
            # Send in chunks
            chunks = [result[i:i+4000] for i in range(0, len(result), 4000)]
            await query.edit_message_text(
                text=chunks[0],
                parse_mode='Markdown',
                reply_markup=get_main_keyboard()
            )
            for chunk in chunks[1:]:
                await query.message.reply_text(
                    text=chunk,
                    parse_mode='Markdown'
                )
        else:
            await query.edit_message_text(
                text=result,
                parse_mode='Markdown',
                reply_markup=get_main_keyboard()
            )
            
    except Exception as e:
        logger.error(f"Error in button_callback: {e}")
        error_msg = f"❌ Terjadi kesalahan: {str(e)}\n\nSilakan coba lagi."
        await query.edit_message_text(
            text=error_msg,
            parse_mode='Markdown',
            reply_markup=get_main_keyboard()
        )

# ==========================================
# PACKING LIST FUNCTIONS
# ==========================================

def cek_packing_list_all():
    """Cek semua packing list yang belum bongkar"""
    try:
        data = get_sheet_data_csv(SHEET_PACKING_LIST)
        if not data:
            return '❌ Gagal mengambil data dari sheet. Pastikan sheet dapat diakses secara public.'
        
        box_data = get_box_data()
        
        container_groups = {}
        total_count = 0
        
        # Process packing list (skip header)
        for i in range(1, len(data)):
            row = data[i]
            if len(row) < 9:
                continue
            
            packing_list = row[1] if len(row) > 1 else ''
            ctns = parse_float(row[2] if len(row) > 2 else 0)
            est_bongkar = row[4] if len(row) > 4 else ''
            tanggal_bongkar = row[8] if len(row) > 8 else ''
            
            if not packing_list or packing_list.strip() == '':
                continue
            
            # Skip jika sudah dibongkar
            if tanggal_bongkar and tanggal_bongkar.strip() != '':
                continue
            
            if est_bongkar:
                total_count += 1
                
                container_name = extract_container_name(packing_list)
                
                if container_name not in container_groups:
                    container_groups[container_name] = {
                        'total_ctns': 0,
                        'items': [],
                        'est_bongkar': est_bongkar
                    }
                
                container_groups[container_name]['total_ctns'] += ctns
                container_groups[container_name]['items'].append({
                    'packing_list': packing_list,
                    'ctns': ctns
                })
        
        # Merge box data
        for box_key, box_info in box_data.items():
            if box_key in container_groups:
                container_groups[box_key]['box_items'] = box_info['items']
                container_groups[box_key]['box_total'] = box_info['total_koli']
            else:
                container_groups[box_key] = {
                    'total_ctns': 0,
                    'items': [],
                    'est_bongkar': None,
                    'box_items': box_info['items'],
                    'box_total': box_info['total_koli']
                }
        
        if total_count == 0 and not box_data:
            return '✅ Semua packing list sudah dibongkar!'
        
        msg = '📦 *PACKING LIST BELUM BONGKAR*\n'
        msg += f'Total: {total_count} packing list\n'
        msg += '━━━━━━━━━━━━━━━━━━\n\n'
        
        item_number = 1
        sorted_containers = sorted(container_groups.keys())
        
        for container_name in sorted_containers:
            container = container_groups[container_name]
            
            # Hitung total koli (ctns + box)
            total_koli = int(container["total_ctns"]) + int(container.get('box_total', 0))
            
            msg += f'*{container_name}* → {int(container["total_ctns"])}\n'
            
            if 'box_total' in container and container['box_total'] > 0:
                msg += f'BOX → {int(container["box_total"])}\n'
            
            if total_koli > 0:
                msg += f'*Total: {total_koli} Koli*\n'
            
            msg += '━━━━━━━━━━━━━━━━━━\n'
            
            for item in container.get('items', []):
                msg += f'{item_number}. {item["packing_list"]} → {int(item["ctns"])} Koli\n'
                item_number += 1
            
            if container.get('est_bongkar'):
                msg += f'📅 *Est Bongkar:* {format_tanggal(container["est_bongkar"])}\n'
            
            if 'box_items' in container:
                for box_item in container['box_items']:
                    msg += f'📦 BOX: {box_item["jenis_barang"]} → {box_item["koli"]}\n'
                    if box_item.get('tanggal_kirim'):
                        msg += f'   📅 Tanggal Kirim: {format_tanggal(box_item["tanggal_kirim"])}\n'
            
            msg += '━━━━━━━━━━━━━━━━━━\n\n'
        
        return msg
    
    except Exception as e:
        logger.error(f"Error in cek_packing_list_all: {e}")
        return f'❌ Error: {str(e)}'

def cek_container():
    """Cek hanya container (C-XX)"""
    try:
        data = get_sheet_data_csv(SHEET_PACKING_LIST)
        if not data:
            return '❌ Gagal mengambil data dari sheet.'
        
        box_data = get_box_data()
        container_groups = {}
        
        for i in range(1, len(data)):
            row = data[i]
            if len(row) < 9:
                continue
            
            packing_list = row[1] if len(row) > 1 else ''
            ctns = parse_float(row[2] if len(row) > 2 else 0)
            est_bongkar = row[4] if len(row) > 4 else ''
            tanggal_bongkar = row[8] if len(row) > 8 else ''
            
            if not packing_list or tanggal_bongkar:
                continue
            
            if '(' in packing_list and ')' in packing_list:
                container_name = extract_container_name(packing_list)
                
                if container_name.startswith('C-') or ('C....') or ('C...') or ('C..') in container_name:
                    if container_name not in container_groups:
                        container_groups[container_name] = {
                            'total_ctns': 0,
                            'items': [],
                            'est_bongkar': est_bongkar
                        }
                    
                    container_groups[container_name]['total_ctns'] += ctns
                    container_groups[container_name]['items'].append({
                        'packing_list': packing_list,
                        'ctns': ctns
                    })
        
        # Merge box data untuk container yang cocok
        for box_key, box_info in box_data.items():
            if box_key in container_groups:
                container_groups[box_key]['box_items'] = box_info['items']
                container_groups[box_key]['box_total'] = box_info['total_koli']
        
        if not container_groups:
            return '✅ Tidak ada container yang sedang dalam pengiriman.'
        
        msg = '🚢 *CONTAINER DALAM PENGIRIMAN*\n'
        msg += f'Total: {len(container_groups)} container\n'
        msg += '━━━━━━━━━━━━━━━━━━\n\n'
        
        for container_name in sorted(container_groups.keys()):
            container = container_groups[container_name]
            
            # Hitung total koli (ctns + box)
            total_ctns = int(container["total_ctns"])
            box_total = int(container.get('box_total', 0))
            total_koli = total_ctns + box_total
            
            msg += f'*{container_name}*\n'
            msg += f'Container: {total_ctns} Koli\n'
            
            if box_total > 0:
                msg += f'BOX: {box_total} Koli\n'
            
            msg += f'*Total: {total_koli} Koli*\n'
            msg += '━━━━━━━━━━━━━━━━━━\n'
            
            for item in container['items']:
                ctns_koli = int(item["ctns"])
                msg += f'• {item["packing_list"]} → {ctns_koli} Koli\n'
            
            # Tampilkan box items jika ada
            if 'box_items' in container:
                for box_item in container['box_items']:
                    msg += f'• BOX: {box_item["jenis_barang"]} → {box_item["koli"]}\n'
            
            if container['est_bongkar']:
                msg += f'\n📅 Est Bongkar: {format_tanggal(container["est_bongkar"])}\n'
            
            msg += '━━━━━━━━━━━━━━━━━━\n\n'
        
        return msg
    
    except Exception as e:
        logger.error(f"Error in cek_container: {e}")
        return f'❌ Error: {str(e)}'

def cek_box():
    """Cek update pengiriman box"""
    try:
        box_data = get_box_data()
        
        if not box_data:
            return '✅ Tidak ada box yang sedang dalam pengiriman.'
        
        msg = '📦 *BOX DALAM PENGIRIMAN*\n'
        msg += f'Total: {len(box_data)} group\n'
        msg += '━━━━━━━━━━━━━━━━━━\n\n'
        
        for container_name, box_info in sorted(box_data.items()):
            total_koli = int(box_info["total_koli"])
            msg += f'*{container_name}* → Total: {total_koli} Koli\n'
            msg += '━━━━━━━━━━━━━━━━━━\n'
            
            for item in box_info['items']:
                msg += f'📦 *{item["jenis_barang"]}* → {item["koli"]}\n'
                if item.get('tanggal_kirim'):
                    msg += f'   📅 Kirim: {format_tanggal(item["tanggal_kirim"])}\n'
                if item.get('link_gambar'):
                    msg += f'   🔗 [Lihat Gambar]({item["link_gambar"]})\n'
            
            msg += '\n'
        
        return msg
    
    except Exception as e:
        logger.error(f"Error in cek_box: {e}")
        return f'❌ Error: {str(e)}'

def cek_metro():
    """Cek packing list selain container (non C-XX)"""
    try:
        data = get_sheet_data_csv(SHEET_PACKING_LIST)
        if not data:
            return '❌ Gagal mengambil data dari sheet.'
        
        metro_items = []
        
        for i in range(1, len(data)):
            row = data[i]
            if len(row) < 9:
                continue
            
            packing_list = row[1] if len(row) > 1 else ''
            ctns = parse_float(row[2] if len(row) > 2 else 0)
            est_bongkar = row[4] if len(row) > 4 else ''
            tanggal_bongkar = row[8] if len(row) > 8 else ''
            
            if not packing_list or tanggal_bongkar:
                continue
            
            container_name = extract_container_name(packing_list)
            
            if not container_name.startswith('C-') and ('C....') and ('C...') and ('C..') not in container_name:
                metro_items.append({
                    'packing_list': packing_list,
                    'ctns': ctns,
                    'est_bongkar': est_bongkar,
                    'container': container_name
                })
        
        if not metro_items:
            return '✅ Tidak ada pengiriman metro yang sedang berjalan.'
        
        msg = '🚚 *PENGIRIMAN METRO*\n'
        msg += f'Total: {len(metro_items)} packing list\n'
        msg += '━━━━━━━━━━━━━━━━━━\n\n'
        
        for idx, item in enumerate(metro_items, 1):
            ctns_koli = int(item["ctns"])
            msg += f'{idx}. *{item["packing_list"]}*\n'
            msg += f'   Koli: {ctns_koli} Koli\n'
            if item['est_bongkar']:
                msg += f'   📅 Est Bongkar: {format_tanggal(item["est_bongkar"])}\n'
            msg += '\n'
        
        return msg
    
    except Exception as e:
        logger.error(f"Error in cek_metro: {e}")
        return f'❌ Error: {str(e)}'

def get_box_data():
    """Ambil data box dari sheet BOX"""
    try:
        data = get_sheet_data_csv(SHEET_BOX)
        if not data:
            return {}
        
        box_data = {}
        
        for i in range(1, len(data)):
            row = data[i]
            if len(row) < 6:
                continue
            
            jenis_barang = row[1] if len(row) > 1 else ''
            koli = parse_float(row[2] if len(row) > 2 else 0)
            kirim_via = row[3] if len(row) > 3 else ''
            tanggal_kirim = row[4] if len(row) > 4 else ''
            tanggal_bongkar = row[5] if len(row) > 5 else ''
            link_gambar = row[6] if len(row) > 6 else ''
            
            if not kirim_via or (tanggal_bongkar and tanggal_bongkar.strip() != ''):
                continue
            
            container_key = kirim_via.strip()
            
            if container_key not in box_data:
                box_data[container_key] = {
                    'total_koli': 0,
                    'items': []
                }
            
            box_data[container_key]['total_koli'] += koli
            
            koli_formatted = format_koli(koli) if koli > 0 else '-'
            
            box_data[container_key]['items'].append({
                'jenis_barang': jenis_barang,
                'koli': koli_formatted,
                'tanggal_kirim': tanggal_kirim,
                'link_gambar': link_gambar
            })
        
        return box_data
    
    except Exception as e:
        logger.error(f"Error in get_box_data: {e}")
        return {}

def get_help_text():
    """Get help text"""
    return (
        "📦 *PANDUAN PACKING LIST BOT*\n\n"
        "*MENU TERSEDIA:*\n"
        "• 📦 Cek Semua - Lihat semua PL yang belum bongkar\n"
        "• 🚢 Container - Lihat container (C-XX) dalam pengiriman\n"
        "• 📦 Box - Lihat pengiriman box\n"
        "• 🚚 Metro - Lihat pengiriman selain container\n\n"
        "*TOMBOL NAVIGASI:*\n"
        "• 📋 Menu - Kembali ke menu utama\n"
        "• ℹ️ Help - Tampilkan panduan ini\n"
        "• 🔄 Refresh - Clear cache dan ambil data terbaru\n\n"
        "*NOTIFIKASI OTOMATIS:*\n"
        "• Update packing list baru (setiap 1 jam)\n"
        "• 3 hari sebelum Est Bongkar (daily jam 08:00)\n"
        "• Link gambar dari sheet BOX (setiap 2 jam)\n\n"
        "*CATATAN:*\n"
        "Data diambil dari Google Sheets public.\n"
        "Cache: 5 menit untuk performa optimal."
    )

# ==========================================
# AUTO NOTIFICATION FUNCTIONS
# ==========================================

async def check_new_packing_list(context: ContextTypes.DEFAULT_TYPE):
    """Cek packing list baru dan kirim notifikasi"""
    try:
        # Clear cache untuk data terbaru
        cache_key = f"{get_sheet_id()}_{SHEET_PACKING_LIST}"
        if cache_key in _cache['data']:
            del _cache['data'][cache_key]
            del _cache['timestamp'][cache_key]
        
        data = get_sheet_data_csv(SHEET_PACKING_LIST)
        if not data:
            return
        
        conn = sqlite3.connect(DB_FILE)
        cursor = conn.cursor()
        
        for i in range(1, len(data)):
            row = data[i]
            if len(row) < 5:
                continue
            
            packing_list = row[1] if len(row) > 1 else ''
            ctns = row[2] if len(row) > 2 else ''
            tanggal_nota = row[3] if len(row) > 3 else ''
            est_bongkar = row[4] if len(row) > 4 else ''
            
            if not packing_list or packing_list.strip() == '':
                continue
            
            cursor.execute(
                'SELECT packing_list FROM notified_packing_lists WHERE packing_list = ?',
                (packing_list,)
            )
            
            if cursor.fetchone() is None:
                ctns_koli = int(parse_float(ctns)) if ctns else 0
                
                msg = '🆕 *PACKING LIST BARU*\n\n'
                msg += '━━━━━━━━━━━━━━━━━━\n'
                msg += f'*Packing List:* {packing_list}\n'
                msg += f'*Koli:* {ctns_koli} Koli\n'
                
                if tanggal_nota:
                    msg += f'*Tanggal Nota:* {format_tanggal(tanggal_nota)}\n'
                
                if est_bongkar:
                    msg += f'*Est Bongkar:* {format_tanggal(est_bongkar)}\n'
                
                msg += '━━━━━━━━━━━━━━━━━━'
                
                await context.bot.send_message(
                    chat_id=ADMIN_CHAT_ID,
                    text=msg,
                    parse_mode='Markdown'
                )
                
                cursor.execute(
                    'INSERT INTO notified_packing_lists (packing_list) VALUES (?)',
                    (packing_list,)
                )
        
        conn.commit()
        conn.close()
        
    except Exception as e:
        logger.error(f"Error in check_new_packing_list: {e}")

async def check_upcoming_bongkar(context: ContextTypes.DEFAULT_TYPE):
    """Cek H-3 sebelum Est Bongkar dan kirim notifikasi"""
    try:
        # Clear cache untuk data terbaru
        cache_key = f"{get_sheet_id()}_{SHEET_PACKING_LIST}"
        if cache_key in _cache['data']:
            del _cache['data'][cache_key]
            del _cache['timestamp'][cache_key]
        
        data = get_sheet_data_csv(SHEET_PACKING_LIST)
        if not data:
            return
        
        today = datetime.now().date()
        three_days_later = today + timedelta(days=3)
        
        conn = sqlite3.connect(DB_FILE)
        cursor = conn.cursor()
        
        for i in range(1, len(data)):
            row = data[i]
            if len(row) < 9:
                continue
            
            packing_list = row[1] if len(row) > 1 else ''
            ctns = row[2] if len(row) > 2 else ''
            est_bongkar = row[4] if len(row) > 4 else ''
            tanggal_bongkar = row[8] if len(row) > 8 else ''
            
            if not packing_list or tanggal_bongkar or not est_bongkar:
                continue
            
            try:
                formats = ['%d/%m/%Y', '%Y-%m-%d', '%m/%d/%Y', '%d-%m-%Y']
                est_date = None
                
                for fmt in formats:
                    try:
                        est_date = datetime.strptime(str(est_bongkar), fmt).date()
                        break
                    except:
                        continue
                
                if not est_date:
                    continue
                
                if est_date == three_days_later:
                    cursor.execute(
                        'SELECT packing_list FROM notified_h3 WHERE packing_list = ? AND est_bongkar = ?',
                        (packing_list, est_bongkar)
                    )
                    
                    if cursor.fetchone() is None:
                        ctns_koli = int(parse_float(ctns)) if ctns else 0
                        
                        msg = '⚠️ *3 HARI BARANG AKAN DATANG*\n\n'
                        msg += '━━━━━━━━━━━━━━━━━━\n'
                        msg += f'*Packing List:* {packing_list}\n'
                        msg += f'*Koli:* {ctns_koli} Koli\n'
                        msg += f'*Est Bongkar:* {format_tanggal(est_bongkar)}\n'
                        msg += '━━━━━━━━━━━━━━━━━━\n\n'
                        msg += '📌 Harap persiapkan untuk pembongkaran!'
                        
                        await context.bot.send_message(
                            chat_id=ADMIN_CHAT_ID,
                            text=msg,
                            parse_mode='Markdown'
                        )
                        
                        cursor.execute(
                            'INSERT INTO notified_h3 (packing_list, est_bongkar) VALUES (?, ?)',
                            (packing_list, est_bongkar)
                        )
            
            except Exception as e:
                logger.error(f"Error processing row: {e}")
                continue
        
        conn.commit()
        conn.close()
        
    except Exception as e:
        logger.error(f"Error in check_upcoming_bongkar: {e}")

async def check_box_with_images(context: ContextTypes.DEFAULT_TYPE):
    """Cek box dengan link gambar dan kirim notifikasi"""
    try:
        # Clear cache untuk data terbaru
        cache_key = f"{get_sheet_id()}_{SHEET_BOX}"
        if cache_key in _cache['data']:
            del _cache['data'][cache_key]
            del _cache['timestamp'][cache_key]
        
        data = get_sheet_data_csv(SHEET_BOX)
        if not data:
            return
        
        conn = sqlite3.connect(DB_FILE)
        cursor = conn.cursor()
        
        for i in range(1, len(data)):
            row = data[i]
            if len(row) < 7:
                continue
            
            jenis_barang = row[1] if len(row) > 1 else ''
            koli = row[2] if len(row) > 2 else ''
            kirim_via = row[3] if len(row) > 3 else ''
            tanggal_kirim = row[4] if len(row) > 4 else ''
            tanggal_bongkar = row[5] if len(row) > 5 else ''
            link_gambar = row[6] if len(row) > 6 else ''
            
            if not link_gambar or (tanggal_bongkar and tanggal_bongkar.strip() != ''):
                continue
            
            cursor.execute(
                'SELECT jenis_barang FROM notified_box_images WHERE jenis_barang = ? AND kirim_via = ? AND tanggal_kirim = ?',
                (jenis_barang, kirim_via, tanggal_kirim)
            )
            
            if cursor.fetchone() is None:
                koli_formatted = format_koli(koli) if koli else '0 Koli'
                
                msg = '📦 *BOX DENGAN GAMBAR*\n\n'
                msg += '━━━━━━━━━━━━━━━━━━\n'
                msg += f'*Jenis Barang:* {jenis_barang}\n'
                msg += f'*Koli:* {koli_formatted}\n'
                msg += f'*Kirim Via:* {kirim_via}\n'
                
                if tanggal_kirim:
                    msg += f'*Tanggal Kirim:* {format_tanggal(tanggal_kirim)}\n'
                
                msg += '━━━━━━━━━━━━━━━━━━\n'
                msg += f'🔗 [Lihat Gambar]({link_gambar})'
                
                await context.bot.send_message(
                    chat_id=ADMIN_CHAT_ID,
                    text=msg,
                    parse_mode='Markdown'
                )
                
                cursor.execute(
                    'INSERT INTO notified_box_images (jenis_barang, kirim_via, tanggal_kirim) VALUES (?, ?, ?)',
                    (jenis_barang, kirim_via, tanggal_kirim)
                )
        
        conn.commit()
        conn.close()
        
    except Exception as e:
        logger.error(f"Error in check_box_with_images: {e}")

# ==========================================
# MAIN FUNCTION
# ==========================================

def main():
    """Main function untuk menjalankan bot"""
    
    # Inisialisasi database
    init_database()
    
    # Test koneksi sheet
    logger.info("Testing sheet connection...")
    sheet_id = get_sheet_id()
    if sheet_id:
        logger.info(f"Sheet ID: {sheet_id}")
    else:
        logger.error("Failed to get Sheet ID. Please check SHEET_URL.")
        return
    
    # Buat aplikasi
    application = Application.builder().token(TELEGRAM_TOKEN).build()
    
    # Register command handlers
    application.add_handler(CommandHandler("start", start))
    application.add_handler(CommandHandler("menu", menu_command))
    
    # Register message handler untuk keyboard buttons
    application.add_handler(MessageHandler(
        filters.Regex('^(📋 Menu|ℹ️ Help|🔄 Refresh)$'),
        handle_keyboard_button
    ))
    
    # Register callback query handler
    application.add_handler(CallbackQueryHandler(button_callback))
    
    # Setup job queue untuk notifikasi otomatis
    job_queue = application.job_queue
    
    # Cek packing list baru setiap 1 jam
    job_queue.run_repeating(
        check_new_packing_list,
        interval=3600,
        first=10
    )
    
    # Cek H-3 sebelum bongkar setiap hari jam 08:00
    job_queue.run_daily(
        check_upcoming_bongkar,
        time=datetime.strptime("08:00", "%H:%M").time()
    )
    
    # Cek box dengan gambar setiap 2 jam
    job_queue.run_repeating(
        check_box_with_images,
        interval=7200,
        first=20
    )
    
    # Mulai bot
    logger.info("Bot started successfully!")
    logger.info(f"Monitoring sheet: {SHEET_URL}")
    application.run_polling(allowed_updates=Update.ALL_TYPES)

if __name__ == '__main__':
    main()