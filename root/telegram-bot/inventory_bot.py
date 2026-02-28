#!/usr/bin/env python3
"""
INVENTORY MANAGEMENT BOT - Python Version (COMBINED)
Bot Telegram untuk mengelola inventory barang dari Google Sheets

FITUR GABUNGAN:
- Semua fungsi dari inventory_bot(7).py
- Fitur estimasi kedatangan yang canggih
- Container dengan kode sama digabungkan (misal: C03 total 2 PL, 30 koli)
- Estimasi menggunakan TG NOTA paling awal
- Format tanggal estimasi menggunakan bahasa Indonesia
- Format output estimasi yang lebih jelas dan terstruktur
- Item dengan estimasi tanggal sama digabungkan dalam 1 nomor urut
- Barang yang datang hari ini diprioritaskan paling atas dengan note "HARI INI AKAN DATANG BARANG"
- Error handling yang lebih baik
"""
import os
import json
import logging
import sqlite3
import re
import requests
from datetime import datetime, timedelta
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import (
    Application,
    CommandHandler,
    CallbackQueryHandler,
    MessageHandler,
    filters,
    ContextTypes,
    ConversationHandler,
)
import gspread
from oauth2client.service_account import ServiceAccountCredentials

# ==========================================
# KONFIGURASI
# ==========================================

# Telegram Bot Token
TELEGRAM_TOKEN = "8210470204:AAHVqXVIzrnRfRnZYMP-Tkxk0ZHPsvow2Cc"

# Google Sheets Configuration
CREDENTIALS_FILE = "/root/credentials.json"

# PILIH SALAH SATU:
# Opsi 1: Gunakan Spreadsheet ID (Recommended)
SPREADSHEET_ID = "1bSzvHxKQkq86C6cNdiF1OrrykAyyvSs_kYlg9O9BHbM"  # ID dari URL spreadsheet
USE_SPREADSHEET_ID = True

# Opsi 2: Gunakan Nama Spreadsheet (case-sensitive)
SPREADSHEET_NAME = "inventory-bot"
# USE_SPREADSHEET_ID = False  # Uncomment jika pakai nama

# Nama Sheet
SHEET_SUDAH_BONGKAR = "Barang Sudah Bongkar"
SHEET_BELUM_BONGKAR = "Barang Belum Bongkar"
SHEET_CHECK_POAN = "Check POan"

# Header rows
HEADER_ROW_SUDAH_BONGKAR = 7  # Header di baris 7, data mulai baris 8
HEADER_ROW_BELUM_BONGKAR = 4  # Header di baris 4, data mulai baris 5

# Database untuk tracking
DB_FILE = "/root/inventory_tracker.db"

# Conversation states
WAITING_NUMBER, WAITING_DATE, WAITING_STE, WAITING_PL_NAME, WAITING_KOLI, WAITING_MARKING, WAITING_TG_NOTA, WAITING_CONTAINER_CODE, WAITING_MARKINGAN_CHOICE, WAITING_PL_SELECTION = range(10)

# Logging
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO,
    handlers=[
        logging.FileHandler('/root/inventory_bot.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Global variables
_gspread_client = None
_spreadsheet = None

# ==========================================
# GOOGLE SHEETS SETUP
# ==========================================

def setup_gspread():
    """Setup Google Sheets API client"""
    try:
        scope = ['https://spreadsheets.google.com/feeds',
                 'https://www.googleapis.com/auth/drive']
        creds = ServiceAccountCredentials.from_json_keyfile_name(
            CREDENTIALS_FILE, scope
        )
        client = gspread.authorize(creds)
        logger.info("✅ Google Sheets API connected successfully")
        return client
    except Exception as e:
        logger.error(f"❌ Error setting up gspread: {e}")
        return None

def get_spreadsheet():
    """Get spreadsheet object"""
    global _gspread_client, _spreadsheet
    if not _gspread_client:
        _gspread_client = setup_gspread()
    if not _spreadsheet:
        try:
            if USE_SPREADSHEET_ID:
                _spreadsheet = _gspread_client.open_by_key(SPREADSHEET_ID)
                logger.info(f"✅ Opened spreadsheet by ID: {SPREADSHEET_ID}")
            else:
                _spreadsheet = _gspread_client.open(SPREADSHEET_NAME)
                logger.info(f"✅ Opened spreadsheet by name: {SPREADSHEET_NAME}")
        except Exception as e:
            logger.error(f"❌ Error opening spreadsheet: {e}")
            logger.error(f"Details: {str(e)}")
            return None
    return _spreadsheet

def get_sheet(sheet_name):
    """Get worksheet by name"""
    try:
        spreadsheet = get_spreadsheet()
        if not spreadsheet:
            return None
        sheet = spreadsheet.worksheet(sheet_name)
        logger.info(f"✅ Accessed sheet: {sheet_name}")
        return sheet
    except Exception as e:
        logger.error(f"❌ Error accessing sheet {sheet_name}: {e}")
        return None

# ==========================================
# SHEET DATA FUNCTIONS
# ==========================================

def get_sudah_bongkar_data(force_refresh=False):
    """Ambil data dari sheet Barang Sudah Bongkar"""
    try:
        sheet = get_sheet(SHEET_SUDAH_BONGKAR)
        if not sheet:
            return None
        
        # Force refresh untuk mendapatkan data terbaru
        if force_refresh:
            global _spreadsheet
            _spreadsheet = None
            sheet = get_sheet(SHEET_SUDAH_BONGKAR)
        
        all_data = sheet.get_all_values()
        
        # Data mulai dari baris 8 (index 7)
        data_rows = all_data[HEADER_ROW_SUDAH_BONGKAR:]
        
        logger.info(f"✅ Fetched {len(data_rows)} rows from {SHEET_SUDAH_BONGKAR}")
        return data_rows
    except Exception as e:
        logger.error(f"❌ Error fetching data from {SHEET_SUDAH_BONGKAR}: {e}")
        return None

def get_belum_bongkar_data():
    """Ambil data dari sheet Barang Belum Bongkar"""
    try:
        sheet = get_sheet(SHEET_BELUM_BONGKAR)
        if not sheet:
            return None
        
        all_data = sheet.get_all_values()
        
        # Data mulai dari baris 5 (index 4)
        data_rows = all_data[HEADER_ROW_BELUM_BONGKAR:]
        
        logger.info(f"✅ Fetched {len(data_rows)} rows from {SHEET_BELUM_BONGKAR}")
        return data_rows
    except Exception as e:
        logger.error(f"❌ Error fetching data from {SHEET_BELUM_BONGKAR}: {e}")
        return None

def get_check_poan_data():
    """Ambil data dari sheet Check POan"""
    try:
        sheet = get_sheet(SHEET_CHECK_POAN)
        if not sheet:
            return None
        
        all_data = sheet.get_all_values()
        
        # Asumsikan header di baris 1, data mulai baris 2
        data_rows = all_data[1:]
        
        logger.info(f"✅ Fetched {len(data_rows)} rows from {SHEET_CHECK_POAN}")
        return data_rows
    except Exception as e:
        logger.error(f"❌ Error fetching data from {SHEET_CHECK_POAN}: {e}")
        return None

def update_cell_sudah_bongkar(row_num, col_letter, value):
    """
    Update cell di sheet Barang Sudah Bongkar
    row_num: nomor baris actual (8, 9, 10, ...)
    col_letter: huruf kolom (G, H, I, ...)
    """
    try:
        sheet = get_sheet(SHEET_SUDAH_BONGKAR)
        if not sheet:
            return False
        
        cell = f"{col_letter}{row_num}"
        sheet.update(cell, [[value]])
        logger.info(f"✅ Updated {SHEET_SUDAH_BONGKAR} {cell} = {value}")
        return True
    except Exception as e:
        logger.error(f"❌ Error updating cell: {e}")
        return False

def delete_row_belum_bongkar(row_num):
    """
    Delete row dari sheet Barang Belum Bongkar
    row_num: nomor baris actual (5, 6, 7, ...)
    """
    try:
        sheet = get_sheet(SHEET_BELUM_BONGKAR)
        if not sheet:
            return False
        
        sheet.delete_rows(row_num)
        logger.info(f"✅ Deleted row {row_num} from {SHEET_BELUM_BONGKAR}")
        return True
    except Exception as e:
        logger.error(f"❌ Error deleting row: {e}")
        return False

def copy_row_format(sheet, source_row, target_row, start_col=1, end_col=10):
    """
    Copy format (warna, border, dll) dari source_row ke target_row
    """
    try:
        sheet.spreadsheet.batch_update({
            "requests": [
                {
                    "copyPaste": {
                        "source": {
                            "sheetId": sheet.id,
                            "startRowIndex": source_row - 1,
                            "endRowIndex": source_row,
                            "startColumnIndex": start_col - 1,
                            "endColumnIndex": end_col
                        },
                        "destination": {
                            "sheetId": sheet.id,
                            "startRowIndex": target_row - 1,
                            "endRowIndex": target_row,
                            "startColumnIndex": start_col - 1,
                            "endColumnIndex": end_col
                        },
                        "pasteType": "PASTE_FORMAT"
                    }
                }
            ]
        })
        return True
    except Exception as e:
        logger.error(f"❌ Failed copy row format: {e}")
        return False

def append_row_sudah_bongkar(row_data):
    """Append row + copy table format"""
    try:
        sheet = get_sheet(SHEET_SUDAH_BONGKAR)
        if not sheet:
            return False

        all_data = sheet.get_all_values()

        # cari baris data terakhir (untuk NO & format)
        last_data_row = 0
        last_no = 0

        for idx, row in enumerate(all_data[HEADER_ROW_SUDAH_BONGKAR:], start=HEADER_ROW_SUDAH_BONGKAR + 1):
            if len(row) > 1 and row[1]:
                try:
                    last_no = int(row[1])
                    last_data_row = idx
                except:
                    continue

        next_no = last_no + 1
        row_data[1] = next_no  # kolom B

        # append data dulu
        sheet.append_row(row_data)
        new_row_index = len(all_data) + 1

        # copy format dari baris sebelumnya
        if last_data_row > 0:
            copy_row_format(
                sheet,
                source_row=last_data_row,
                target_row=new_row_index,
                start_col=1,
                end_col=10
            )

        logger.info(f"✅ Appended formatted row NO {next_no}")
        return True

    except Exception as e:
        logger.error(f"❌ Error append formatted row: {e}")
        return False

def reorder_belum_bongkar_numbers():
    """Reorder nomor di sheet Barang Belum Bongkar mulai dari 1"""
    try:
        sheet = get_sheet(SHEET_BELUM_BONGKAR)
        if not sheet:
            return False
        
        all_data = sheet.get_all_values()
        data_rows = all_data[HEADER_ROW_BELUM_BONGKAR:]
        
        # Update nomor urut untuk setiap baris yang ada data
        updates = []
        for idx, row in enumerate(data_rows):
            if len(row) > 2 and row[2]:  # Jika ada PACKING LIST (kolom C)
                actual_row = HEADER_ROW_BELUM_BONGKAR + 1 + idx
                new_no = idx + 1
                updates.append({
                    'range': f'B{actual_row}',
                    'values': [[new_no]]
                })
        
        # Batch update untuk efisiensi
        if updates:
            for update in updates:
                sheet.update(update['range'], update['values'])
            logger.info(f"✅ Reordered {len(updates)} rows in {SHEET_BELUM_BONGKAR}")
            return True
    except Exception as e:
        logger.error(f"❌ Error reordering {SHEET_BELUM_BONGKAR}: {e}")
        return False

def append_row_belum_bongkar(row_data):
    """
    Append row ke sheet Barang Belum Bongkar dengan format yang sama
    row_data: list berisi data untuk kolom B-F
    [NO, PACKING LIST, KOLI, MARKING, TG NOTA]
    Kolom A = kosong
    Kolom B = NO (auto increment)
    Kolom C = PACKING LIST
    Kolom D = KOLI
    Kolom E = MARKING
    Kolom F = TG NOTA
    """
    try:
        sheet = get_sheet(SHEET_BELUM_BONGKAR)
        if not sheet:
            return False

        all_data = sheet.get_all_values()
        
        # Cari nomor terakhir di kolom B
        last_no = 0
        last_data_row = 0
        for idx, row in enumerate(all_data[HEADER_ROW_BELUM_BONGKAR:], start=HEADER_ROW_BELUM_BONGKAR + 1):
            if len(row) > 1 and row[1]:
                try:
                    no = int(row[1])
                    if no > last_no:
                        last_no = no
                        last_data_row = idx
                except:
                    continue

        next_no = last_no + 1
        row_data[0] = next_no  # kolom B (NO)

        # Append data
        sheet.append_row(row_data)
        new_row_index = len(all_data) + 1

        # Copy format dari baris sebelumnya
        if last_data_row > 0:
            copy_row_format(
                sheet,
                source_row=last_data_row,
                target_row=new_row_index,
                start_col=1,
                end_col=6
            )

        logger.info(f"✅ Appended row to {SHEET_BELUM_BONGKAR} NO {next_no}")
        return True

    except Exception as e:
        logger.error(f"❌ Error appending row to {SHEET_BELUM_BONGKAR}: {e}")
        return False

# ==========================================
# HELPER FUNCTIONS
# ==========================================

def format_tanggal(date_str):
    """Format tanggal ke format DD Month YYYY"""
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

def parse_date_input(date_str):
    """Parse input tanggal dari user dan format ke bahasa Indonesia"""
    try:
        # Parse input
        if '/' in date_str:
            date_obj = datetime.strptime(date_str, '%d/%m/%Y')
        elif '-' in date_str:
            date_obj = datetime.strptime(date_str, '%d-%m-%Y')
        else:
            return None
        
        # Nama bulan bahasa Indonesia (huruf kapital di awal)
        bulan_indonesia = [
            'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
            'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
        ]
        
        # Format: DD Bulan YYYY (contoh: 12 Januari 2026)
        return f"{date_obj.day} {bulan_indonesia[date_obj.month - 1]} {date_obj.year}"
    except:
        return None

def parse_float(value):
    """Parse value ke float, return 0 jika gagal"""
    try:
        if isinstance(value, str):
            value = value.replace(',', '')
        return float(value) if value else 0
    except:
        return 0

def format_hari_ini():
    """Format tanggal hari ini dalam bahasa Indonesia"""
    today = datetime.now()
    bulan = [
        'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
        'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
    ]
    return f"{today.day} {bulan[today.month - 1]} {today.year}"

def format_days_until(days):
    """Format jumlah hari menjadi text yang user-friendly"""
    if days < 0:
        return f"terlambat {abs(days)} hari"
    elif days == 0:
        return "hari ini"
    elif days == 1:
        return "1 hari lagi / Besok"
    else:
        return f"{days} hari lagi"

# ==========================================
# FUNGSI ESTIMASI KEDATANGAN
# ==========================================

def parse_date_for_estimasi(date_str):
    """Parse tanggal dari berbagai format untuk estimasi"""
    if not date_str or not date_str.strip():
        return None
    
    date_str = date_str.strip()
    
    # Map bulan Indonesia ke English
    bulan_map = {
        'januari': 'January', 'februari': 'February', 'maret': 'March',
        'april': 'April', 'mei': 'May', 'juni': 'June',
        'juli': 'July', 'agustus': 'August', 'september': 'September',
        'oktober': 'October', 'november': 'November', 'desember': 'December'
    }
    
    # Replace bulan Indonesia dengan English (case insensitive)
    date_lower = date_str.lower()
    for indo, eng in bulan_map.items():
        if indo in date_lower:
            date_str = date_str.replace(indo, eng)
            date_str = date_str.replace(indo.capitalize(), eng)
            break
    
    # Format yang mungkin
    formats = [
        '%d %B %Y',      # 6 January 2026
        '%d %b %Y',      # 6 Jan 2026
        '%d/%m/%Y',      # 06/01/2026
        '%d-%m-%Y',      # 06-01-2026
        '%Y-%m-%d',      # 2026-01-06
        '%d.%m.%Y',      # 06.01.2026
        '%d %m %Y',      # 06 01 2026
        '%d/%m/%y',      # 06/01/26
        '%d-%m-%y',      # 06-01-26
    ]
    
    for fmt in formats:
        try:
            return datetime.strptime(date_str, fmt)
        except ValueError:
            continue
    
    return None

def calculate_estimasi(markingan, tg_nota, container_type=None):
    """
    Hitung estimasi kedatangan berdasarkan markingan dan TG NOTA
    
    Args:
        markingan: string marking (misal: '/SEA', '/AIR', 'C03', 'CONTAINER', dll)
        tg_nota: tanggal nota (string)
        container_type: untuk identifikasi container
    
    Returns:
        tuple: (estimasi_date, days_delta, category)
    """
    tg_nota_date = parse_date_for_estimasi(tg_nota)
    
    if not tg_nota_date:
        return None, None, None
    
    if not markingan or not markingan.strip():
        return None, None, None
    
    markingan_upper = markingan.upper().strip()
    
    # 1. Cek apakah ini CONTAINER atau kode container (C03, C04, dll)
    is_container = (
        container_type or
        'CONTAINER' in markingan_upper or
        'KONFIRMASI' in markingan_upper or
        (markingan_upper.startswith('C') and len(markingan_upper) <= 4 and markingan_upper[1:].isdigit())
    )
    
    if is_container:
        # Container selalu +1 bulan
        estimasi_date = tg_nota_date + timedelta(days=30)
        return estimasi_date, 30, 'CONTAINER'
    
    # 2. Cek apakah ini SEA
    if '/SEA' in markingan_upper or markingan_upper.endswith('/SEA') or markingan_upper.endswith('SEA'):
        estimasi_date = tg_nota_date + timedelta(days=30)
        return estimasi_date, 30, 'SEA'
    
    # 3. Cek apakah ini AIR
    if '/AIR' in markingan_upper or markingan_upper.endswith('/AIR') or markingan_upper.endswith('AIR'):
        estimasi_date = tg_nota_date + timedelta(days=7)
        return estimasi_date, 7, 'AIR'
    
    return None, None, None

def get_estimasi_data():
    """
    Ambil semua data belum bongkar dan hitung estimasinya
    Container dengan kode sama digabungkan, estimasi dari TG NOTA paling awal
    """
    data_rows = get_belum_bongkar_data()
    if not data_rows:
        return []
    
    # Dictionary untuk menggabungkan container dengan kode yang sama
    container_groups = {}
    metro_list = []
    today = datetime.now()
    
    for idx, row in enumerate(data_rows, start=HEADER_ROW_BELUM_BONGKAR + 1):
        if not row or len(row) < 6:
            continue
        
        # Cek apakah row kosong
        if not any(cell.strip() for cell in row):
            continue
        
        # Mapping kolom yang benar:
        # A (0) = kosong
        # B (1) = NO
        # C (2) = PACKING LIST
        # D (3) = KOLI
        # E (4) = PENGIRIMAN (MARKINGAN)
        # F (5) = TG NOTA
        no = row[1] if len(row) > 1 else ''
        packing_list = row[2] if len(row) > 2 else ''
        koli = row[3] if len(row) > 3 else ''
        markingan = row[4] if len(row) > 4 else ''  # Kolom PENGIRIMAN
        tg_nota = row[5] if len(row) > 5 else ''
        
        if not packing_list.strip():
            continue
        
        # Cek apakah ini container (C03, C04, CONTAINER, dll)
        is_container = (
            markingan.upper() == 'CONTAINER' or
            re.match(r'^C\d+$', markingan.upper().strip())
        )
        
        if is_container:
            # Normalisasi kode container
            container_code = markingan.upper().strip()
            
            # Parse tanggal nota untuk mendapatkan objek datetime
            tg_nota_date = parse_date_for_estimasi(tg_nota)
            
            if tg_nota_date:
                # Tambahkan ke grup container
                if container_code not in container_groups:
                    container_groups[container_code] = {
                        'items': [],
                        'total_koli': 0,
                        'earliest_date': tg_nota_date,
                        'earliest_nota': tg_nota
                    }
                
                # Update data grup
                container_groups[container_code]['items'].append({
                    'no': no,
                    'packing_list': packing_list,
                    'koli': koli,
                    'tg_nota': tg_nota,
                    'tg_nota_date': tg_nota_date
                })
                
                container_groups[container_code]['total_koli'] += parse_float(koli)
                
                # Update tanggal paling awal
                if tg_nota_date < container_groups[container_code]['earliest_date']:
                    container_groups[container_code]['earliest_date'] = tg_nota_date
                    container_groups[container_code]['earliest_nota'] = tg_nota
        else:
            # Untuk METRO dan lainnya, proses seperti biasa
            estimasi_date, days_delta, category = calculate_estimasi(markingan, tg_nota)
            
            if estimasi_date:
                # Format tanggal estimasi ke bahasa Indonesia
                bulan_indonesia = [
                    'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
                    'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
                ]
                estimasi_formatted = f"{estimasi_date.day} {bulan_indonesia[estimasi_date.month - 1]} {estimasi_date.year}"
                
                days_until = (estimasi_date - today).days
                
                metro_list.append({
                    'no': no,
                    'markingan': markingan,
                    'packing_list': packing_list,
                    'koli': koli,
                    'tg_nota': tg_nota,
                    'estimasi_date': estimasi_date,
                    'estimasi_formatted': estimasi_formatted,
                    'days_until': days_until,
                    'category': category,
                    'is_grouped': False,
                    'row_data': row
                })
    
    # Proses container groups
    estimasi_list = []
    
    for container_code, data in container_groups.items():
        # Hitung estimasi dari tanggal paling awal
        earliest_date = data['earliest_date']
        estimasi_date = earliest_date + timedelta(days=30)  # Container +30 hari
        days_until = (estimasi_date - today).days
        
        # Format tanggal estimasi ke bahasa Indonesia
        bulan_indonesia = [
            'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
            'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
        ]
        estimasi_formatted = f"{estimasi_date.day} {bulan_indonesia[estimasi_date.month - 1]} {estimasi_date.year}"
        
        # Buat string packing list gabungan
        pl_names = [item['packing_list'] for item in data['items']]
        combined_pl = f"{container_code} ({len(pl_names)} PL)"
        
        estimasi_list.append({
            'no': container_code,
            'markingan': container_code,
            'packing_list': combined_pl,
            'packing_list_detail': pl_names,
            'koli': str(int(data['total_koli'])),
            'tg_nota': data['earliest_nota'],
            'estimasi_date': estimasi_date,
            'estimasi_formatted': estimasi_formatted,
            'days_until': days_until,
            'category': 'CONTAINER',
            'is_grouped': True,
            'item_count': len(pl_names),
            'items_detail': data['items']
        })
    
    # Tambahkan metro list
    estimasi_list.extend(metro_list)
    
    # Sort by estimasi_date
    estimasi_list.sort(key=lambda x: x['estimasi_date'])
    
    return estimasi_list

def categorize_by_timeframe(estimasi_list):
    """Kategorikan data estimasi berdasarkan timeframe"""
    categories = {
        'week_1': [],
        'week_2': [],
        'week_3': [],
        'month_1': [],
        'later': []
    }
    
    for item in estimasi_list:
        days = item['days_until']
        
        if days < 0:
            categories['week_1'].append(item)  # Terlambat masuk kategori minggu 1
        elif days <= 7:
            categories['week_1'].append(item)
        elif days <= 14:
            categories['week_2'].append(item)
        elif days <= 21:
            categories['week_3'].append(item)
        elif days <= 30:
            categories['month_1'].append(item)
        else:
            categories['later'].append(item)
    
    return categories

def group_estimasi_by_date(estimasi_list):
    """
    Gabungkan item dengan tanggal estimasi yang sama
    Prioritaskan yang hari ini paling atas
    """
    from collections import OrderedDict
    
    today = datetime.now()
    today_date = today.date()
    
    # Group by date
    grouped = OrderedDict()
    
    for item in estimasi_list:
        date_key = item['estimasi_date'].date()
        
        if date_key not in grouped:
            grouped[date_key] = {
                'estimasi_formatted': item['estimasi_formatted'],
                'estimasi_date': item['estimasi_date'],
                'days_until': item['days_until'],
                'items': [],
                'is_today': date_key == today_date
            }
        
        grouped[date_key]['items'].append(item)
    
    # Sort: hari ini dulu, lalu yang terlambat, lalu yang akan datang
    sorted_groups = []
    
    # 1. Hari ini (prioritas tertinggi)
    for date_key, group in grouped.items():
        if group['is_today']:
            sorted_groups.append(group)
    
    # 2. Yang terlambat (negatif days)
    for date_key, group in grouped.items():
        if not group['is_today'] and group['days_until'] < 0:
            sorted_groups.append(group)
    
    # 3. Yang akan datang (positif days)
    future_groups = []
    for date_key, group in grouped.items():
        if not group['is_today'] and group['days_until'] > 0:
            future_groups.append(group)
    
    # Sort future groups by date
    future_groups.sort(key=lambda x: x['estimasi_date'])
    sorted_groups.extend(future_groups)
    
    return sorted_groups

def format_estimasi_message_new(group_data, index):
    """Format pesan untuk grup estimasi dengan tanggal yang sama"""
    items = group_data['items']
    
    msg = f"{index}. Estimasi: {group_data['estimasi_formatted']} ({format_days_until(group_data['days_until'])})\n"
    
    # Tambahkan note jika hari ini
    if group_data['is_today']:
        msg += "⚠️ *HARI INI AKAN DATANG BARANG*\n"
    
    msg += "\n"
    
    # Jika hanya 1 item dalam grup
    if len(items) == 1:
        item = items[0]
        msg += f"📦 {item['packing_list']}\n"
        
        # Jika container yang digabung, tampilkan detail
        if item.get('is_grouped', False) and item.get('items_detail'):
            msg += f"├ Total Koli: {item['koli']}\n"
            msg += f"├ Detail:\n"
            for i, detail in enumerate(item['items_detail'], 1):
                msg += f"│  {i}. {detail['packing_list']} ({detail['koli']} koli)\n"
            # Tambahkan TG Nota item terakhir
            if item['items_detail']:
                last_item = item['items_detail'][-1]
                msg += f"│     TG Nota: {last_item['tg_nota']}\n"
            msg += f"└ TG Nota (Paling Awal): {item['tg_nota']}\n"
        else:
            msg += f"├ Markingan: {item['markingan']}\n"
            msg += f"├ Koli: {item['koli']}\n"
            msg += f"└ TG Nota: {item['tg_nota']}\n"
    else:
        # Jika lebih dari 1 item dalam grup, tampilkan semua
        for idx, item in enumerate(items, 1):
            msg += f"📦 {item['packing_list']}\n"
            
            # Jika container yang digabung, tampilkan detail
            if item.get('is_grouped', False) and item.get('items_detail'):
                msg += f"├ Total Koli: {item['koli']}\n"
                msg += f"├ Detail:\n"
                for i, detail in enumerate(item['items_detail'], 1):
                    msg += f"│  {i}. {detail['packing_list']} ({detail['koli']} koli)\n"
                # Tambahkan TG Nota item terakhir
                if item['items_detail']:
                    last_item = item['items_detail'][-1]
                    msg += f"│     TG Nota: {last_item['tg_nota']}\n"
                msg += f"└ TG Nota (Paling Awal): {item['tg_nota']}\n"
            else:
                msg += f"├ Markingan: {item['markingan']}\n"
                msg += f"├ Koli: {item['koli']}\n"
                msg += f"└ TG Nota: {item['tg_nota']}\n"
            
            # Tambahkan separator jika bukan item terakhir
            if idx < len(items):
                msg += "\n"
    
    return msg

# ==========================================
# KEYBOARD
# ==========================================

def get_main_keyboard():
    """Keyboard utama"""
    keyboard = [
        [InlineKeyboardButton("📦 Barang Sudah Bongkar", callback_data="sudah_bongkar")],
        [InlineKeyboardButton("🚚 Barang Belum Bongkar", callback_data="belum_bongkar")],
        [InlineKeyboardButton("📅 Estimasi Kedatangan", callback_data='estimasi_dashboard')],
    ]
    return InlineKeyboardMarkup(keyboard)

def get_sudah_bongkar_keyboard():
    """Menu Barang Sudah Bongkar"""
    keyboard = [
        [InlineKeyboardButton("📦 Belum Bongkar", callback_data="belum_bongkar_sb")],
        [InlineKeyboardButton("🔍 Proses Check", callback_data="proses_check")],
        [InlineKeyboardButton("📝 Proses Receipt", callback_data="proses_receipt")],
        [InlineKeyboardButton("⏳ Barang Belum Turun", callback_data="belum_turun")],
        [InlineKeyboardButton("📦 Semua Barang DiGudang", callback_data="semua_barang")],
        [InlineKeyboardButton("✅ Check POan", callback_data="check_poan")],
        [InlineKeyboardButton("🔙 Back", callback_data="back_main")]
    ]
    return InlineKeyboardMarkup(keyboard)

def get_belum_bongkar_keyboard():
    """Menu Barang Belum Bongkar"""
    keyboard = [
        [InlineKeyboardButton("🚢 Container", callback_data="kategori_container")],
        [InlineKeyboardButton("🚚 Metro", callback_data="kategori_metro")],
        [InlineKeyboardButton("🇨🇳 Semua Barang di Cina", callback_data="cina_semua")],
        [InlineKeyboardButton("➕ Penambahan PL Baru", callback_data="tambah_pl_baru")],
        [InlineKeyboardButton("📅 Lihat Estimasi", callback_data='estimasi_belum_bongkar')],
        [InlineKeyboardButton("🔙 Back", callback_data="back_main")]
    ]
    return InlineKeyboardMarkup(keyboard)

def get_check_poan_keyboard():
    """Menu Check POan"""
    keyboard = [
        [InlineKeyboardButton("✅ POan ADA", callback_data="poan_ada")],
        [InlineKeyboardButton("❌ POan TIDAK ADA", callback_data="poan_tidak_ada")],
        [InlineKeyboardButton("🔙 Back", callback_data="sudah_bongkar")]
    ]
    return InlineKeyboardMarkup(keyboard)

def get_marking_keyboard():
    """Menu Marking untuk Penambahan PL Baru"""
    keyboard = [
        [InlineKeyboardButton("1. METRO/HART-MLL/AIR", callback_data="marking_1")],
        [InlineKeyboardButton("2. METRO/HART-MLL/SEA", callback_data="marking_2")],
        [InlineKeyboardButton("3. METRO/HART-MLT/AIR", callback_data="marking_3")],
        [InlineKeyboardButton("4. METRO/HART-MLT/SEA", callback_data="marking_4")],
        [InlineKeyboardButton("5. METRO/HART-MLJ/AIR", callback_data="marking_5")],
        [InlineKeyboardButton("6. METRO/HART-MLJ/SEA", callback_data="marking_6")],
        [InlineKeyboardButton("7. METRO/HART-XP/AIR", callback_data="marking_7")],
        [InlineKeyboardButton("8. METRO/HART-XP/SEA", callback_data="marking_8")],
        [InlineKeyboardButton("9. CONTAINER", callback_data="marking_9")],
        [InlineKeyboardButton("🔙 Cancel", callback_data="belum_bongkar")]
    ]
    return InlineKeyboardMarkup(keyboard)

# ==========================================
# COMMAND HANDLERS
# ==========================================

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk command /start"""
    msg = (
        "👋 *Selamat Datang di Inventory Management Bot!*\n"
        "Bot ini untuk mengelola inventory barang:\n"
        f"• {SHEET_SUDAH_BONGKAR}\n"
        f"• {SHEET_BELUM_BONGKAR}\n"
        f"• {SHEET_CHECK_POAN}\n"
        "Pilih menu di bawah untuk memulai:"
    )
    await update.message.reply_text(
        msg,
        parse_mode='Markdown',
        reply_markup=get_main_keyboard()
    )

async def menu_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk command /menu"""
    msg = "📋 *MENU UTAMA*\n"
    msg += "Pilih menu yang Anda inginkan:"
    await update.message.reply_text(
        msg,
        parse_mode='Markdown',
        reply_markup=get_main_keyboard()
    )

# ==========================================
# CALLBACK QUERY HANDLERS - MAIN MENU
# ==========================================

async def button_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk button callback"""
    query = update.callback_query
    
    # Answer callback query dengan timeout handling
    try:
        await query.answer()
    except Exception as e:
        logger.warning(f"Failed to answer callback query: {e}")
    
    data = query.data
    
    try:
        if data == "sudah_bongkar":
            msg = "📦 *BARANG SUDAH BONGKAR*\n"
            msg += "Pilih menu:"
            await query.edit_message_text(
                msg,
                parse_mode='Markdown',
                reply_markup=get_sudah_bongkar_keyboard()
            )
        elif data == "belum_bongkar":
            msg = "🚚 *BARANG BELUM BONGKAR*\n"
            msg += "Pilih kategori pengiriman:"
            await query.edit_message_text(
                msg,
                parse_mode='Markdown',
                reply_markup=get_belum_bongkar_keyboard()
            )
        elif data == "back_main":
            msg = "📋 *MENU UTAMA*\n"
            msg += "Pilih menu:"
            await query.edit_message_text(
                msg,
                parse_mode='Markdown',
                reply_markup=get_main_keyboard()
            )
        elif data == "cina_semua":
            await handle_semua_barang_cina(update, context)
        elif data == "semua_barang":
            await handle_semua_barang(update, context)
        elif data == "check_poan":
            msg = "✅ *CHECK POan*\n"
            msg += "Pilih status POan:"
            await query.edit_message_text(
                msg,
                parse_mode='Markdown',
                reply_markup=get_check_poan_keyboard()
            )
        elif data == "kategori_container":
            await handle_kategori_container(update, context)
        elif data == "kategori_metro":
            await handle_kategori_metro(update, context)
        elif data.startswith("container_detail_"):
            await handle_container_detail(update, context)
        elif data.startswith("metro_detail_"):
            await handle_metro_detail(update, context)
        elif data.startswith("poan_"):
            await handle_poan_status(update, context)
        elif data.startswith("view_poan_"):
            await handle_view_poan(update, context)
        elif data == 'estimasi_dashboard':
            await handle_estimasi_dashboard(update, context)
        elif data == 'estimasi_belum_bongkar':
            await handle_estimasi_belum_bongkar(update, context)
        elif data.startswith('estimasi_detail_'):
            await handle_estimasi_detail(update, context)
    except Exception as e:
        logger.error(f"Error in button_callback for data '{data}': {e}")
        try:
            await query.message.reply_text(
                "❌ Terjadi kesalahan. Silakan coba lagi atau gunakan /menu untuk kembali ke menu utama."
            )
        except:
            pass

# ==========================================
# HANDLER ESTIMASI KEDATANGAN
# ==========================================

async def handle_estimasi_dashboard(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk dashboard estimasi kedatangan"""
    query = update.callback_query
    
    try:
        await query.answer()
    except Exception as e:
        logger.warning(f"Failed to answer callback query: {e}")
    
    try:
        estimasi_list = get_estimasi_data()
        
        if not estimasi_list:
            await query.edit_message_text(
                "📅 Tidak ada data estimasi kedatangan.",
                reply_markup=get_main_keyboard()
            )
            return
        
        # Kategorikan berdasarkan timeframe
        categories = categorize_by_timeframe(estimasi_list)
        
        # Group by date
        grouped_estimasi = group_estimasi_by_date(estimasi_list)
        
        msg = "📅 *ESTIMASI KEDATANGAN*\n"
        msg += f"Total: {len(estimasi_list)} item\n\n"
        
        # Summary
        msg += f"🔴 1 Minggu: {len(categories['week_1'])} item\n"
        msg += f"🟠 2 Minggu: {len(categories['week_2'])} item\n"
        msg += f"🟡 3 Minggu: {len(categories['week_3'])} item\n"
        msg += f"🟢 1 Bulan: {len(categories['month_1'])} item\n"
        
        if categories['later']:
            msg += f"⚪ >1 Bulan: {len(categories['later'])} item\n"
        
        msg += "=" * 34 + "\n"
        msg += f"Tanggal Hari ini : {format_hari_ini()}\n"
        msg += "=" * 34 + "\n\n"
        
        msg += "*ESTIMASI TERDEKAT:*\n\n"
        
        # Tampilkan maksimal 10 grup terdekat
        for idx, group in enumerate(grouped_estimasi[:10], 1):
            msg += format_estimasi_message_new(group, idx)
            msg += "\n"
            
            # Cek panjang pesan untuk menghindari limit Telegram
            if len(msg) > 3500:
                remaining_items = sum(len(g['items']) for g in grouped_estimasi[idx:])
                msg += f"\n_...dan {remaining_items} item lainnya_"
                break
        
        if len(grouped_estimasi) > 10 and len(msg) <= 3500:
            remaining_items = sum(len(g['items']) for g in grouped_estimasi[10:])
            msg += f"\n_...dan {remaining_items} item lainnya_"
        
        # Buat keyboard
        keyboard = [
            [InlineKeyboardButton("🔍 Lihat Detail Semua", callback_data='estimasi_detail_all')],
            [InlineKeyboardButton("🔙 Kembali", callback_data='back_main')],
        ]
        
        await query.edit_message_text(
            msg,
            parse_mode='Markdown',
            reply_markup=InlineKeyboardMarkup(keyboard)
        )
    except Exception as e:
        logger.error(f"Error in handle_estimasi_dashboard: {e}")
        try:
            await query.message.reply_text(
                "❌ Terjadi kesalahan saat mengambil data estimasi. Silakan coba lagi."
            )
        except:
            pass

async def handle_estimasi_belum_bongkar(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk melihat estimasi dari menu Barang Belum Bongkar"""
    query = update.callback_query
    
    try:
        await query.answer()
    except Exception as e:
        logger.warning(f"Failed to answer callback query: {e}")
    
    try:
        estimasi_list = get_estimasi_data()
        
        if not estimasi_list:
            await query.edit_message_text(
                "📅 Tidak ada data estimasi kedatangan.",
                reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Kembali", callback_data='belum_bongkar')]])
            )
            return
        
        # Kategorikan berdasarkan timeframe
        categories = categorize_by_timeframe(estimasi_list)
        
        # Group by date
        grouped_estimasi = group_estimasi_by_date(estimasi_list)
        
        msg = "📅 *ESTIMASI KEDATANGAN*\n"
        msg += f"Total: {len(estimasi_list)} item\n\n"
        
        # Summary
        msg += f"🔴 1 Minggu: {len(categories['week_1'])} item\n"
        msg += f"🟠 2 Minggu: {len(categories['week_2'])} item\n"
        msg += f"🟡 3 Minggu: {len(categories['week_3'])} item\n"
        msg += f"🟢 1 Bulan: {len(categories['month_1'])} item\n"
        
        if categories['later']:
            msg += f"⚪ >1 Bulan: {len(categories['later'])} item\n"
        
        msg += "=" * 34 + "\n"
        msg += f"Tanggal Hari ini : {format_hari_ini()}\n"
        msg += "=" * 34 + "\n\n"
        
        msg += "*ESTIMASI TERDEKAT:*\n\n"
        
        # Tampilkan maksimal 10 grup terdekat
        for idx, group in enumerate(grouped_estimasi[:10], 1):
            msg += format_estimasi_message_new(group, idx)
            msg += "\n"
        
        if len(grouped_estimasi) > 10:
            remaining_items = sum(len(g['items']) for g in grouped_estimasi[10:])
            msg += f"\n_...dan {remaining_items} item lainnya_"
        
        keyboard = [
            [InlineKeyboardButton("🔙 Kembali", callback_data='belum_bongkar')],
        ]
        
        await query.edit_message_text(
            msg,
            parse_mode='Markdown',
            reply_markup=InlineKeyboardMarkup(keyboard)
        )
    except Exception as e:
        logger.error(f"Error in handle_estimasi_belum_bongkar: {e}")
        try:
            await query.message.reply_text(
                "❌ Terjadi kesalahan saat mengambil data estimasi. Silakan coba lagi."
            )
        except:
            pass

async def handle_estimasi_detail(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk melihat detail estimasi semua item"""
    query = update.callback_query
    
    try:
        await query.answer()
    except Exception as e:
        logger.warning(f"Failed to answer callback query: {e}")
    
    try:
        estimasi_list = get_estimasi_data()
        
        if not estimasi_list:
            await query.edit_message_text(
                "📅 Tidak ada data estimasi kedatangan.",
                reply_markup=get_main_keyboard()
            )
            return
        
        # Group by date
        grouped_estimasi = group_estimasi_by_date(estimasi_list)
        
        # Buat pesan detail lengkap
        msg = "📅 *DETAIL ESTIMASI KEDATANGAN*\n"
        msg += f"Total: {len(estimasi_list)} item\n\n"
        msg += "=" * 34 + "\n"
        msg += f"Tanggal Hari ini : {format_hari_ini()}\n"
        msg += "=" * 34 + "\n\n"
        
        for idx, group in enumerate(grouped_estimasi, 1):
            msg += format_estimasi_message_new(group, idx)
            msg += "\n"
            
            # Telegram memiliki limit panjang pesan
            if len(msg) > 3500:
                remaining_items = sum(len(g['items']) for g in grouped_estimasi[idx:])
                msg += f"\n_...dan {remaining_items} item lainnya_"
                break
        
        keyboard = [
            [InlineKeyboardButton("🔙 Kembali", callback_data='estimasi_dashboard')],
        ]
        
        await query.edit_message_text(
            msg,
            parse_mode='Markdown',
            reply_markup=InlineKeyboardMarkup(keyboard)
        )
    except Exception as e:
        logger.error(f"Error in handle_estimasi_detail: {e}")
        try:
            await query.message.reply_text(
                "❌ Terjadi kesalahan saat mengambil data estimasi. Silakan coba lagi."
            )
        except:
            pass

# ==========================================
# BARANG SUDAH BONGKAR - HANDLERS
# (Lanjutan dari inventory_bot(7).py - terlalu panjang, akan dilanjutkan di bagian berikutnya)
# ==========================================

# NOTE: File ini terlalu panjang untuk ditampilkan semuanya dalam satu response
# Silakan gunakan bagian berikutnya untuk melengkapi handler-handler yang tersisa
# atau saya dapat membuat file terpisah untuk handler-handler tersebut

async def handle_belum_bongkar_sb(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    data = get_sudah_bongkar_data()

    belum_bongkar_list = []

    for idx, row in enumerate(data):
        packing_list = row[2] if len(row) > 2 else ''
        finish = row[6] if len(row) > 6 else ''

        if packing_list and (not finish or finish.strip() == ''):
            actual_row = HEADER_ROW_SUDAH_BONGKAR + 1 + idx
            belum_bongkar_list.append({
                'row': actual_row,
                'packing_list': packing_list
            })

    if not belum_bongkar_list:
        await query.edit_message_text(
            "✅ Tidak ada barang Belum Bongkar.",
            reply_markup=get_sudah_bongkar_keyboard()
        )
        return ConversationHandler.END

    msg = "📦 *BELUM BONGKAR*\n"
    for i, item in enumerate(belum_bongkar_list, 1):
        msg += f"{i}. {item['packing_list']}\n"

    msg += "\n💡 Pilih nomor untuk Proses Check:"
    await query.edit_message_text(
        msg,
        parse_mode="Markdown"
    )

    context.user_data['belum_bongkar_list'] = belum_bongkar_list
    context.user_data['current_action'] = 'belum_bongkar_sb'
    return WAITING_NUMBER

async def handle_proses_check(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk Proses Check"""
    query = update.callback_query
    data = get_sudah_bongkar_data()
    if not data:
        await query.edit_message_text(
            "❌ Gagal mengambil data.",
            reply_markup=get_sudah_bongkar_keyboard()
        )
        return ConversationHandler.END
    
    proses_check_list = []
    # Kolom G (FINISH) = index 6
    # Kolom C (PACKING LIST) = index 2
    for idx, row in enumerate(data):
        if len(row) > 6:
            finish = row[6]  # Kolom G
            packing_list = row[2] if len(row) > 2 else ''  # Kolom C
            if finish == 'Proses Check' and packing_list:
                actual_row = HEADER_ROW_SUDAH_BONGKAR + 1 + idx  # Baris actual di sheet
                proses_check_list.append({
                    'row': actual_row,
                    'packing_list': packing_list
                })
    
    if not proses_check_list:
        keyboard = [[InlineKeyboardButton("🔙 Back", callback_data="sudah_bongkar")]]
        await query.edit_message_text(
            "✅ Tidak ada barang dalam Proses Check.",
            reply_markup=InlineKeyboardMarkup(keyboard)
        )
        return ConversationHandler.END
    
    msg = "🔍 *PROSES CHECK*\n"
    for idx, item in enumerate(proses_check_list, 1):
        msg += f"{idx}. {item['packing_list']}\n"
    msg += "\n💡 Masukkan nomor untuk update (atau /cancel untuk batal):"
    keyboard = [[InlineKeyboardButton("🔙 Back", callback_data="sudah_bongkar")]]
    await query.edit_message_text(
        msg,
        parse_mode='Markdown',
        reply_markup=InlineKeyboardMarkup(keyboard)
    )
    context.user_data['proses_check_list'] = proses_check_list
    context.user_data['current_action'] = 'proses_check'
    return WAITING_NUMBER

async def handle_proses_receipt(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk Proses Receipt"""
    query = update.callback_query
    data = get_sudah_bongkar_data()
    if not data:
        await query.edit_message_text(
            "❌ Gagal mengambil data.",
            reply_markup=get_sudah_bongkar_keyboard()
        )
        return ConversationHandler.END
    
    proses_receipt_list = []
    # Kolom H (PL STE TOKO) = index 7
    # Kolom C (PACKING LIST) = index 2
    for idx, row in enumerate(data):
        if len(row) > 7:
            pl_ste = row[7]  # Kolom H
            packing_list = row[2] if len(row) > 2 else ''  # Kolom C
            # Yang belum ada STE-MLN atau masih kosong
            if packing_list and pl_ste and 'STE-MLN' not in pl_ste and pl_ste.strip() != '':
                actual_row = HEADER_ROW_SUDAH_BONGKAR + 1 + idx
                proses_receipt_list.append({
                    'row': actual_row,
                    'packing_list': packing_list
                })
    
    if not proses_receipt_list:
        keyboard = [[InlineKeyboardButton("🔙 Back", callback_data="sudah_bongkar")]]
        await query.edit_message_text(
            "✅ Tidak ada barang dalam Proses Receipt.",
            reply_markup=InlineKeyboardMarkup(keyboard)
        )
        return ConversationHandler.END
    
    msg = "📝 *PROSES RECEIPT*\n"
    for idx, item in enumerate(proses_receipt_list, 1):
        msg += f"{idx}. {item['packing_list']}\n"
    msg += "\n💡 Masukkan nomor untuk update (atau /cancel untuk batal):"
    keyboard = [[InlineKeyboardButton("🔙 Back", callback_data="sudah_bongkar")]]
    await query.edit_message_text(
        msg,
        parse_mode='Markdown',
        reply_markup=InlineKeyboardMarkup(keyboard)
    )
    context.user_data['proses_receipt_list'] = proses_receipt_list
    context.user_data['current_action'] = 'proses_receipt'
    return WAITING_NUMBER

async def handle_belum_turun(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk Barang Belum Turun"""
    query = update.callback_query
    data = get_sudah_bongkar_data()
    if not data:
        await query.edit_message_text(
            "❌ Gagal mengambil data.",
            reply_markup=get_sudah_bongkar_keyboard()
        )
        return ConversationHandler.END
    
    belum_turun_list = []
    # Kolom I (PINDAH KE STORE TOKO BARU) = index 8
    # Kolom C (PACKING LIST) = index 2
    for idx, row in enumerate(data):
        if len(row) > 8:
            pindah_toko = row[8]  # Kolom I
            packing_list = row[2] if len(row) > 2 else ''  # Kolom C
            if pindah_toko == 'Belum Turun' and packing_list:
                actual_row = HEADER_ROW_SUDAH_BONGKAR + 1 + idx
                belum_turun_list.append({
                    'row': actual_row,
                    'packing_list': packing_list
                })
    
    if not belum_turun_list:
        keyboard = [[InlineKeyboardButton("🔙 Back", callback_data="sudah_bongkar")]]
        await query.edit_message_text(
            "✅ Tidak ada barang yang Belum Turun.",
            reply_markup=InlineKeyboardMarkup(keyboard)
        )
        return ConversationHandler.END
    
    msg = "⏳ *BARANG BELUM TURUN*\n"
    for idx, item in enumerate(belum_turun_list, 1):
        msg += f"{idx}. {item['packing_list']}\n"
    msg += "\n💡 Masukkan nomor untuk update (atau /cancel untuk batal):"
    keyboard = [[InlineKeyboardButton("🔙 Back", callback_data="sudah_bongkar")]]
    await query.edit_message_text(
        msg,
        parse_mode='Markdown',
        reply_markup=InlineKeyboardMarkup(keyboard)
    )
    context.user_data['belum_turun_list'] = belum_turun_list
    context.user_data['current_action'] = 'belum_turun'
    return WAITING_NUMBER

async def handle_semua_barang(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk Semua Barang Di Gudang (dengan kategori detail)"""
    query = update.callback_query

    data = get_sudah_bongkar_data(force_refresh=True)
    if not data:
        await query.edit_message_text(
            "❌ Gagal mengambil data.",
            reply_markup=get_sudah_bongkar_keyboard()
        )
        return

    belum_bongkar = []
    proses_check = []
    proses_receipt = []
    belum_turun = []

    for row in data:
        if len(row) < 9:
            continue

        packing_list = row[2].strip() if len(row) > 2 else ''
        koli = row[3].strip() if len(row) > 3 else '0'

        start = row[5].strip() if len(row) > 5 else ''
        finish = row[6].strip() if len(row) > 6 else ''
        pl_ste = row[7].strip() if len(row) > 7 else ''
        pindah = row[8].strip() if len(row) > 8 else ''

        if not packing_list:
            continue

        # Belum Bongkar
        if start == 'Belum Bongkar':
            belum_bongkar.append(f"  • {packing_list} -> {koli} Koli")

        # Proses Check
        if finish == 'Proses Check':
            proses_check.append(f"  • {packing_list} -> {koli} Koli")

        # Proses Receipt
        if pl_ste == 'Proses Receipt':
            proses_receipt.append(f"  • {packing_list} -> {koli} Koli")

        # Belum Turun
        if pindah == 'Belum Turun':
            belum_turun.append(f"  • {packing_list} -> {koli} Koli")

    msg = "📦 *SEMUA BARANG DI GUDANG*\n"

    def block(title, items):
        if not items:
            return ""
        text = "\n==========\n"
        text += f"*{title}*\n"
        text += "==========\n"
        text += "\n".join(items)
        return text

    msg += block("Belum Bongkar", belum_bongkar)
    msg += block("Proses Check", proses_check)
    msg += block("Proses Receipt", proses_receipt)
    msg += block("Belum Turun", belum_turun)

    if not (belum_bongkar or proses_check or proses_receipt or belum_turun):
        msg += "\n✅ Tidak ada barang di gudang."

    keyboard = [[InlineKeyboardButton("🔙 Back", callback_data="sudah_bongkar")]]
    await query.edit_message_text(
        msg,
        parse_mode='Markdown',
        reply_markup=InlineKeyboardMarkup(keyboard)
    )

async def handle_poan_status(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk POan ADA/TIDAK ADA"""
    query = update.callback_query
    status = 'ADA' if query.data == 'poan_ada' else 'TIDAK ADA'
    data = get_check_poan_data()
    if not data:
        await query.edit_message_text(
            "❌ Gagal mengambil data.",
            reply_markup=get_sudah_bongkar_keyboard()
        )
        return
    
    poan_list = []
    # Asumsikan struktur sama dengan Barang Sudah Bongkar
    # Kolom C = PACKING LIST (index 2)
    # Kolom F = POan (index 5)
    # Kolom J = MARKINGAN (index 9)
    for idx, row in enumerate(data):
        if len(row) > 9:
            markingan = row[9]  # Kolom J
            packing_list = row[2] if len(row) > 2 else ''  # Kolom C
            poan = row[5] if len(row) > 5 else ''  # Kolom F
            if markingan == status and packing_list:
                poan_list.append({
                    'packing_list': packing_list,
                    'poan': poan
                })
    
    if not poan_list:
        keyboard = [[InlineKeyboardButton("🔙 Back", callback_data="check_poan")]]
        await query.edit_message_text(
            f"✅ Tidak ada barang dengan POan {status}.",
            reply_markup=InlineKeyboardMarkup(keyboard)
        )
        return
    
    msg = f"📋 *POAN {status}*\n"
    keyboard = []
    for idx, item in enumerate(poan_list, 1):
        msg += f"{idx}. {item['packing_list']}\n"
        if status == 'ADA':
            keyboard.append([InlineKeyboardButton(
                f"{idx}. {item['packing_list'][:30]}...",
                callback_data=f"view_poan_{idx-1}"
            )])
    keyboard.append([InlineKeyboardButton("🔙 Back", callback_data="check_poan")])
    
    if status == 'ADA':
        msg += "\n💡 Klik packing list untuk melihat detail POan:"
    context.user_data['poan_list'] = poan_list
    await query.edit_message_text(
        msg,
        parse_mode='Markdown',
        reply_markup=InlineKeyboardMarkup(keyboard)
    )

async def handle_view_poan(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk melihat detail POan"""
    query = update.callback_query
    idx = int(query.data.split('_')[2])
    poan_list = context.user_data.get('poan_list', [])
    if idx >= len(poan_list):
        await query.answer("Data tidak ditemukan!")
        return
    
    item = poan_list[idx]
    msg = f"📋 *DETAIL POAN*\n"
    msg += f"*Packing List:* {item['packing_list']}\n"
    msg += f"*List POan:*\n{item['poan']}"
    keyboard = [[InlineKeyboardButton("🔙 Back", callback_data="poan_ada")]]
    await query.edit_message_text(
        msg,
        parse_mode='Markdown',
        reply_markup=InlineKeyboardMarkup(keyboard)
    )

# ==========================================
# BARANG BELUM BONGKAR - HANDLERS
# ==========================================
async def handle_semua_barang_cina(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    data = get_belum_bongkar_data()

    if not data:
        await query.edit_message_text(
            "❌ Gagal mengambil data.",
            reply_markup=get_belum_bongkar_keyboard()
        )
        return

    container = []
    container_c = {}
    metro_air = []
    metro_sea = []

    total_container = 0
    total_c = {}
    total_air = 0
    total_sea = 0

    for row in data:
        if len(row) < 5:
            continue

        pl = row[2].strip()
        koli = parse_float(row[3])
        marking = row[4].strip()

        if not pl:
            continue

        # ===== CONTAINER UMUM =====
        if marking == 'CONTAINER':
            container.append(f"  • {pl} -> {int(koli)} Koli")
            total_container += koli

        # ===== Cxx =====
        elif re.match(r'^C\d+$', marking):
            if marking not in container_c:
                container_c[marking] = []
                total_c[marking] = 0
            container_c[marking].append(f"  • {pl} -> {int(koli)} Koli")
            total_c[marking] += koli

        # ===== METRO AIR =====
        elif 'METRO' in marking and 'AIR' in marking:
            metro_air.append(f"  • {pl} -> {int(koli)} Koli")
            total_air += koli

        # ===== METRO SEA =====
        elif 'METRO' in marking and 'SEA' in marking:
            metro_sea.append(f"  • {pl} -> {int(koli)} Koli")
            total_sea += koli

    msg = "🇨🇳 *SEMUA BARANG DI CINA*\n"

    def block(title, total, items):
        if not items:
            return ""
        text = "\n==========\n"
        text += f"*{title}*\n"
        text += f"Total Kolian : {int(total)}\n"
        text += "==========\n"
        text += "\n".join(items)
        text += "\n=========="
        return text

    # ===== CONTAINER =====
    msg += block("Container", total_container, container)

    # ===== Cxx =====
    for c in sorted(container_c.keys()):
        msg += block(c, total_c[c], container_c[c])

    # ===== METRO =====
    if metro_air or metro_sea:
        msg += "\n\n=====\n*Metro*\n====="

    msg += block("UDARA (AIR)", total_air, metro_air)
    msg += block("LAUT (SEA)", total_sea, metro_sea)

    keyboard = [[InlineKeyboardButton("🔙 Back", callback_data="belum_bongkar")]]

    await query.edit_message_text(
        msg,
        parse_mode='Markdown',
        reply_markup=InlineKeyboardMarkup(keyboard)
    )

async def handle_kategori_container(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk kategori Container"""
    query = update.callback_query
    data = get_belum_bongkar_data()
    if not data:
        await query.edit_message_text(
            "❌ Gagal mengambil data.",
            reply_markup=get_belum_bongkar_keyboard()
        )
        return
    
    container_groups = {}
    # Kolom C = PACKING LIST (index 2)
    # Kolom D = KOLI (index 3)
    # Kolom E = PENGIRIMAN (index 4)
    for idx, row in enumerate(data):
        if len(row) > 4:
            pengiriman = row[4]  # Kolom E
            packing_list = row[2] if len(row) > 2 else ''  # Kolom C
            koli = parse_float(row[3] if len(row) > 3 else 0)  # Kolom D
            if not packing_list:
                continue
            # Filter container: C38, C39, CONTAINER
            if pengiriman == 'CONTAINER' or re.match(r'^C\d+$', pengiriman):
                if pengiriman not in container_groups:
                    container_groups[pengiriman] = {
                        'total': 0,
                        'items': []
                    }
                actual_row = HEADER_ROW_BELUM_BONGKAR + 1 + idx
                container_groups[pengiriman]['total'] += koli
                container_groups[pengiriman]['items'].append({
                    'row': actual_row,
                    'packing_list': packing_list,
                    'koli': int(koli),
                    'row_data': row  # Simpan seluruh data row
                })
    
    if not container_groups:
        keyboard = [[InlineKeyboardButton("🔙 Back", callback_data="belum_bongkar")]]
        await query.edit_message_text(
            "✅ Tidak ada container dalam pengiriman.",
            reply_markup=InlineKeyboardMarkup(keyboard)
        )
        return
    
    msg = "🚢 *KATEGORI CONTAINER*\n"
    msg += "Pilih container:"
    keyboard = []
    for container_name in sorted(container_groups.keys()):
        total = int(container_groups[container_name]['total'])
        keyboard.append([InlineKeyboardButton(
            f"{container_name} ({total} Koli)",
            callback_data=f"container_detail_{container_name}"
        )])
    keyboard.append([InlineKeyboardButton("🔙 Back", callback_data="belum_bongkar")])
    
    context.user_data['container_groups'] = container_groups
    await query.edit_message_text(
        msg,
        parse_mode='Markdown',
        reply_markup=InlineKeyboardMarkup(keyboard)
    )

async def handle_container_detail(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk detail container"""
    query = update.callback_query
    container_name = query.data.replace('container_detail_', '')
    container_groups = context.user_data.get('container_groups', {})
    if container_name not in container_groups:
        await query.answer("Data tidak ditemukan!")
        return
    
    container = container_groups[container_name]
    total = int(container['total'])
    msg = "==================\n"
    msg += f"*{container_name}*\n"
    msg += f"Total: {total} Koli\n"
    msg += "==================\n"
    for item in container['items']:
        msg += f"• {item['packing_list']} → {item['koli']} Koli\n"
    msg += "=================="
    keyboard = [
        [InlineKeyboardButton("✅ Sudah Bongkar", callback_data=f"bongkar_container_{container_name}")],
        [InlineKeyboardButton("🔙 Back", callback_data="kategori_container")]
    ]
    await query.edit_message_text(
        msg,
        parse_mode='Markdown',
        reply_markup=InlineKeyboardMarkup(keyboard)
    )

async def handle_bongkar_container_start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk mulai bongkar container"""
    query = update.callback_query
    container_name = query.data.replace('bongkar_container_', '')
    context.user_data['bongkar_type'] = 'container'
    context.user_data['bongkar_container'] = container_name
    context.user_data['current_action'] = 'bongkar_container'
    await query.edit_message_text(
        f"📅 Masukkan tanggal bongkar untuk *{container_name}*\n"
        f"Format: DD/MM/YYYY atau DD-MM-YYYY\n"
        f"Contoh: 24/01/2026\n"
        f"Ketik /cancel untuk membatalkan.",
        parse_mode='Markdown'
    )
    return WAITING_DATE

async def handle_kategori_metro(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk kategori Metro"""
    query = update.callback_query
    data = get_belum_bongkar_data()
    if not data:
        await query.edit_message_text(
            "❌ Gagal mengambil data.",
            reply_markup=get_belum_bongkar_keyboard()
        )
        return
    
    metro_groups = {}
    for idx, row in enumerate(data):
        if len(row) > 4:
            pengiriman = row[4]  # Kolom E
            packing_list = row[2] if len(row) > 2 else ''  # Kolom C
            koli = parse_float(row[3] if len(row) > 3 else 0)  # Kolom D
            if not packing_list:
                continue
            # Filter METRO
            if 'METRO' in pengiriman:
                # Extract kode (MLL, MLJ, XP, dll) dari packing list
                kode = packing_list.split()[0] if packing_list else 'Unknown'
                if kode not in metro_groups:
                    metro_groups[kode] = {
                        'total': 0,
                        'items': []
                    }
                actual_row = HEADER_ROW_BELUM_BONGKAR + 1 + idx
                metro_groups[kode]['total'] += koli
                metro_groups[kode]['items'].append({
                    'row': actual_row,
                    'packing_list': packing_list,
                    'koli': int(koli),
                    'pengiriman': pengiriman,
                    'row_data': row
                })
    
    if not metro_groups:
        keyboard = [[InlineKeyboardButton("🔙 Back", callback_data="belum_bongkar")]]
        await query.edit_message_text(
            "✅ Tidak ada metro dalam pengiriman.",
            reply_markup=InlineKeyboardMarkup(keyboard)
        )
        return
    
    msg = "🚚 *KATEGORI METRO*\n"
    msg += "Pilih kode:"
    keyboard = []
    for kode in sorted(metro_groups.keys()):
        total = int(metro_groups[kode]['total'])
        keyboard.append([InlineKeyboardButton(
            f"{kode} ({total} Koli)",
            callback_data=f"metro_detail_{kode}"
        )])
    keyboard.append([InlineKeyboardButton("🔙 Back", callback_data="belum_bongkar")])
    
    context.user_data['metro_groups'] = metro_groups
    await query.edit_message_text(
        msg,
        parse_mode='Markdown',
        reply_markup=InlineKeyboardMarkup(keyboard)
    )

async def handle_metro_detail(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk detail metro"""
    query = update.callback_query
    kode = query.data.replace('metro_detail_', '')
    metro_groups = context.user_data.get('metro_groups', {})
    if kode not in metro_groups:
        await query.answer("Data tidak ditemukan!")
        return
    
    metro = metro_groups[kode]
    total = int(metro['total'])
    msg = "==================\n"
    msg += f"*{kode}*\n"
    msg += f"Total: {total} Koli\n"
    msg += "==================\n"
    keyboard = []
    for idx, item in enumerate(metro['items']):
        msg += f"• {item['packing_list']} → {item['koli']} Koli\n"
        keyboard.append([InlineKeyboardButton(
            f"{item['packing_list'][:40]}",
            callback_data=f"bongkar_metro_{kode}_{idx}"
        )])
    msg += "=================="
    keyboard.append([InlineKeyboardButton("🔙 Back", callback_data="kategori_metro")])
    
    context.user_data['current_metro_kode'] = kode
    await query.edit_message_text(
        msg,
        parse_mode='Markdown',
        reply_markup=InlineKeyboardMarkup(keyboard)
    )

async def handle_bongkar_metro_start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk mulai bongkar metro"""
    query = update.callback_query
    parts = query.data.split('_')
    kode = parts[2]
    idx = int(parts[3])
    metro_groups = context.user_data.get('metro_groups', {})
    if kode not in metro_groups or idx >= len(metro_groups[kode]['items']):
        await query.answer("Data tidak ditemukan!")
        return
    
    item = metro_groups[kode]['items'][idx]
    context.user_data['bongkar_type'] = 'metro'
    context.user_data['bongkar_metro_item'] = item
    context.user_data['current_action'] = 'bongkar_metro'
    await query.edit_message_text(
        f"📅 Masukkan tanggal bongkar untuk:\n"
        f"*{item['packing_list']}*\n"
        f"Format: DD/MM/YYYY atau DD-MM-YYYY\n"
        f"Contoh: 24/01/2026\n"
        f"Ketik /cancel untuk membatalkan.",
        parse_mode='Markdown'
    )
    return WAITING_DATE

# ==========================================
# PENAMBAHAN PL BARU - HANDLERS
# ==========================================
async def handle_tambah_pl_baru_start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk mulai menambah PL baru"""
    query = update.callback_query
    context.user_data['current_action'] = 'tambah_pl_baru'
    await query.edit_message_text(
        "➕ *PENAMBAHAN PL BARU*\n\n"
        "📝 Masukkan *Nama PACKING LIST*:\n"
        "Contoh: MLL 001-025\n\n"
        "Ketik /cancel untuk membatalkan.",
        parse_mode='Markdown'
    )
    return WAITING_PL_NAME

async def handle_pl_name_input(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk input nama packing list"""
    text = update.message.text.strip()
    
    if not text:
        await update.message.reply_text(
            "❌ Nama PACKING LIST tidak boleh kosong!\n"
            "Silakan masukkan nama PACKING LIST:",
            reply_markup=get_main_keyboard()
        )
        return WAITING_PL_NAME
    
    # Simpan nama PL
    context.user_data['new_pl_name'] = text
    
    await update.message.reply_text(
        f"✅ PACKING LIST: *{text}*\n\n"
        f"📦 Masukkan jumlah *KOLI*:\n"
        f"Contoh: 25",
        parse_mode='Markdown'
    )
    return WAITING_KOLI

async def handle_koli_input(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk input KOLI"""
    text = update.message.text.strip()
    
    # Validasi angka
    try:
        koli = int(text)
        if koli <= 0:
            raise ValueError
    except ValueError:
        await update.message.reply_text(
            "❌ KOLI harus berupa angka positif!\n"
            "Silakan masukkan jumlah KOLI:",
            reply_markup=get_main_keyboard()
        )
        return WAITING_KOLI
    
    # Simpan KOLI
    context.user_data['new_pl_koli'] = koli
    
    await update.message.reply_text(
        f"✅ KOLI: *{koli}*\n\n"
        f"🏷️ Pilih *MARKING*:",
        parse_mode='Markdown',
        reply_markup=get_marking_keyboard()
    )
    return WAITING_MARKING

async def handle_marking_selection(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk pilihan marking"""
    query = update.callback_query
    await query.answer()
    
    marking_map = {
        'marking_1': 'METRO/HART-MLL/AIR',
        'marking_2': 'METRO/HART-MLL/SEA',
        'marking_3': 'METRO/HART-MLT/AIR',
        'marking_4': 'METRO/HART-MLT/SEA',
        'marking_5': 'METRO/HART-MLJ/AIR',
        'marking_6': 'METRO/HART-MLJ/SEA',
        'marking_7': 'METRO/HART-XP/AIR',
        'marking_8': 'METRO/HART-XP/SEA',
    }
    
    if query.data == 'marking_9':
        # Pilihan CONTAINER - minta input manual
        context.user_data['new_pl_marking_type'] = 'CONTAINER'
        await query.edit_message_text(
            "✅ MARKING: *CONTAINER*\n\n"
            "📝 Masukkan kode CONTAINER:\n"
            "Contoh: C05, C38, C39\n"
            "Atau ketik: Konfirmasi\n\n"
            "Ketik /cancel untuk membatalkan.",
            parse_mode='Markdown'
        )
        return WAITING_CONTAINER_CODE
    elif query.data in marking_map:
        # Pilihan 1-8
        marking = marking_map[query.data]
        context.user_data['new_pl_marking'] = marking
        
        await query.edit_message_text(
            f"✅ MARKING: *{marking}*\n\n"
            f"📅 Masukkan *TG NOTA*:\n"
            f"Format: DD/MM/YYYY atau DD-MM-YYYY\n"
            f"Contoh: 28/01/2026\n\n"
            f"Ketik /cancel untuk membatalkan.",
            parse_mode='Markdown'
        )
        return WAITING_TG_NOTA

async def handle_container_code_input(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk input kode container"""
    text = update.message.text.strip()
    
    if not text:
        await update.message.reply_text(
            "❌ Kode container tidak boleh kosong!\n"
            "Silakan masukkan kode CONTAINER:",
            reply_markup=get_main_keyboard()
        )
        return WAITING_CONTAINER_CODE
    
    # Jika user ketik "Konfirmasi", marking jadi "CONTAINER"
    if text.lower() == 'konfirmasi':
        marking = 'CONTAINER'
    else:
        # Jika user input kode container (misal C05), marking jadi kode tersebut
        marking = text.upper()
    
    context.user_data['new_pl_marking'] = marking
    
    await update.message.reply_text(
        f"✅ MARKING: *{marking}*\n\n"
        f"📅 Masukkan *TG NOTA*:\n"
        f"Format: DD/MM/YYYY atau DD-MM-YYYY\n"
        f"Contoh: 28/01/2026",
        parse_mode='Markdown'
    )
    return WAITING_TG_NOTA

async def handle_tg_nota_input(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk input TG NOTA dan simpan ke sheet"""
    text = update.message.text.strip()
    
    # Parse dan format tanggal
    date_formatted = parse_date_input(text)
    
    if not date_formatted:
        await update.message.reply_text(
            "❌ Format tanggal salah!\n"
            "Gunakan DD/MM/YYYY atau DD-MM-YYYY\n"
            "Contoh: 28/01/2026",
            reply_markup=get_main_keyboard()
        )
        return WAITING_TG_NOTA
    
    # Ambil data yang sudah disimpan
    pl_name = context.user_data.get('new_pl_name', '')
    koli = context.user_data.get('new_pl_koli', 0)
    marking = context.user_data.get('new_pl_marking', '')
    
    # Buat row data untuk sheet Barang Belum Bongkar
    # Kolom: A=kosong, B=NO (auto), C=PACKING LIST, D=KOLI, E=MARKING, F=TG NOTA
    new_row = [
        '',           # B - NO (akan diisi otomatis oleh append_row_belum_bongkar)
        pl_name,      # C - PACKING LIST
        str(koli),    # D - KOLI
        marking,      # E - MARKING
        date_formatted  # F - TG NOTA
    ]
    
    # Simpan ke sheet
    if append_row_belum_bongkar(new_row):
        await update.message.reply_text(
            f"✅ *BERHASIL MENAMBAHKAN PL BARU!*\n\n"
            f"📝 PACKING LIST: {pl_name}\n"
            f"📦 KOLI: {koli}\n"
            f"🏷️ MARKING: {marking}\n"
            f"📅 TG NOTA: {date_formatted}",
            parse_mode='Markdown',
            reply_markup=get_main_keyboard()
        )
    else:
        await update.message.reply_text(
            "❌ Gagal menambahkan data ke spreadsheet.\n"
            "Silakan coba lagi.",
            reply_markup=get_main_keyboard()
        )
    
    # Clear user data
    context.user_data.pop('new_pl_name', None)
    context.user_data.pop('new_pl_koli', None)
    context.user_data.pop('new_pl_marking', None)
    context.user_data.pop('new_pl_marking_type', None)
    
    return ConversationHandler.END

# ==========================================
# CONVERSATION HANDLERS
# ==========================================
async def handle_number_input(update: Update, context: ContextTypes.DEFAULT_TYPE):
    text = update.message.text.strip()
    if not text.isdigit():
        await update.message.reply_text("❌ Mohon masukkan nomor yang valid!")
        return WAITING_NUMBER

    number = int(text)
    current_action = context.user_data.get('current_action')

    if current_action == 'proses_check':
        proses_list = context.user_data.get('proses_check_list', [])
        if 1 <= number <= len(proses_list):
            item = proses_list[number - 1]
            context.user_data['selected_item'] = item
            await update.message.reply_text(
                f"📅 Masukkan tanggal selesai check untuk:\n"
                f"*{item['packing_list']}*",
                parse_mode="Markdown"
            )
            return WAITING_DATE
        else:
            await update.message.reply_text("❌ Nomor tidak valid!")
            return WAITING_NUMBER

    elif current_action == 'proses_receipt':
        proses_list = context.user_data.get('proses_receipt_list', [])
        if 1 <= number <= len(proses_list):
            item = proses_list[number - 1]
            context.user_data['selected_item'] = item
            await update.message.reply_text(
                f"📝 Masukkan nomor STE-MLN untuk:\n"
                f"*{item['packing_list']}*",
                parse_mode="Markdown"
            )
            return WAITING_STE
        else:
            await update.message.reply_text("❌ Nomor tidak valid!")
            return WAITING_NUMBER

    elif current_action == 'belum_bongkar_sb':
        data_list = context.user_data.get('belum_bongkar_list', [])
        if 1 <= number <= len(data_list):
            item = data_list[number - 1]
            context.user_data['selected_item'] = item
            await update.message.reply_text(
                f"📅 Masukkan tanggal Proses Check untuk:\n"
                f"*{item['packing_list']}*",
                parse_mode="Markdown"
            )
            return WAITING_DATE
        else:
            await update.message.reply_text("❌ Nomor tidak valid!")
            return WAITING_NUMBER
    
    elif current_action == 'belum_turun':
        belum_list = context.user_data.get('belum_turun_list', [])
        if 1 <= number <= len(belum_list):
            item = belum_list[number - 1]
            context.user_data['selected_item'] = item
            await update.message.reply_text(
                f"✅ Anda memilih: *{item['packing_list']}*\n"
                f"📅 Masukkan tanggal turun toko:\n"
                f"Format: DD/MM/YYYY atau DD-MM-YYYY\n"
                f"Contoh: 24/01/2026",
                parse_mode='Markdown'
            )
            return WAITING_DATE
        else:
            await update.message.reply_text("❌ Nomor tidak valid!")
            return WAITING_NUMBER

async def handle_date_input(update: Update, context: ContextTypes.DEFAULT_TYPE):
    text = update.message.text.strip()
    current_action = context.user_data.get('current_action')

    # Parse dan format tanggal ke bahasa Indonesia
    date_formatted = parse_date_input(text)
    
    if not date_formatted:
        await update.message.reply_text(
            "❌ Format tanggal salah!\nGunakan DD/MM/YYYY atau DD-MM-YYYY\n"
            "Contoh: 12/01/2026",
            reply_markup=get_main_keyboard()
        )
        return WAITING_DATE

    if current_action == 'proses_check':
        item = context.user_data['selected_item']
        row_num = item['row']

        if update_cell_sudah_bongkar(row_num, 'G', date_formatted):
            # otomatis masuk receipt
            update_cell_sudah_bongkar(row_num, 'H', 'Proses Receipt')

            await update.message.reply_text(
                f"✅ *Proses Check selesai*\n"
                f"Packing List: {item['packing_list']}\n"
                f"Tanggal: {date_formatted}",
                parse_mode="Markdown",
                reply_markup=get_main_keyboard()
            )
        else:
            await update.message.reply_text("❌ Gagal update data.")
        return ConversationHandler.END

    elif current_action == 'belum_bongkar_sb':
        item = context.user_data['selected_item']
        row_num = item['row']

        # Update kolom F (START) dengan tanggal dan kolom G (FINISH) dengan "Proses Check"
        success_f = update_cell_sudah_bongkar(row_num, 'F', date_formatted)
        success_g = update_cell_sudah_bongkar(row_num, 'G', 'Proses Check')
        
        if success_f and success_g:
            await update.message.reply_text(
                f"✅ *Masuk Proses Check*\n"
                f"Packing List: {item['packing_list']}\n"
                f"Tanggal: {date_formatted}",
                parse_mode="Markdown",
                reply_markup=get_main_keyboard()
            )
        else:
            await update.message.reply_text("❌ Gagal update data.")
        return ConversationHandler.END
    
    elif current_action == 'belum_turun':
        item = context.user_data.get('selected_item')
        row_num = item['row']
        # Update kolom I (PINDAH KE STORE TOKO BARU)
        if update_cell_sudah_bongkar(row_num, 'I', date_formatted):
            await update.message.reply_text(
                f"✅ *Berhasil update Barang Sudah Turun!*\n"
                f"Packing List: {item['packing_list']}\n"
                f"Tanggal: {date_formatted}",
                parse_mode='Markdown',
                reply_markup=get_main_keyboard()
            )
        else:
            await update.message.reply_text(
                "❌ Gagal update data. Coba lagi.",
                reply_markup=get_main_keyboard()
            )
        return ConversationHandler.END
    
    elif current_action == 'bongkar_container':
        container_name = context.user_data.get('bongkar_container')
        container_groups = context.user_data.get('container_groups', {})
        if container_name in container_groups:
            items = container_groups[container_name]['items']
            
            # Simpan data untuk digunakan nanti
            context.user_data['date_formatted'] = date_formatted
            context.user_data['remaining_items'] = items.copy()  # Salin list items
            context.user_data['processed_items'] = []  # List untuk item yang sudah diproses
            
            # Jika ada lebih dari 1 packing list, tampilkan list untuk dipilih
            if len(items) > 1:
                # Tampilkan list packing list dengan nomor
                msg = f"📦 *{container_name}*\n"
                msg += f"Tanggal Bongkar: {date_formatted}\n\n"
                msg += "Pilih nomor Packing List:\n\n"
                
                for idx, item in enumerate(items, 1):
                    msg += f"{idx}. {item['packing_list']} ({item['koli']} Koli)\n"
                
                msg += "\n💡 Ketik nomor packing list yang ingin diproses"
                
                await update.message.reply_text(
                    msg,
                    parse_mode='Markdown'
                )
                return WAITING_PL_SELECTION
            else:
                # Jika hanya 1 packing list, langsung tampilkan pilihan markingan
                item = items[0]
                context.user_data['current_pl_item'] = item
                
                keyboard = [
                    [InlineKeyboardButton("✅ ADA", callback_data="markingan_ada")],
                    [InlineKeyboardButton("❌ TIDAK ADA", callback_data="markingan_tidak_ada")],
                    [InlineKeyboardButton("🔙 Batal", callback_data="cancel_markingan")]
                ]
                reply_markup = InlineKeyboardMarkup(keyboard)
                
                await update.message.reply_text(
                    f"📦 *{container_name}*\n"
                    f"Packing List: {item['packing_list']}\n"
                    f"Koli: {item['koli']}\n\n"
                    f"Apakah barang ada markingan?",
                    parse_mode='Markdown',
                    reply_markup=reply_markup
                )
                return WAITING_MARKINGAN_CHOICE
    
    elif current_action == 'bongkar_metro':
        item = context.user_data.get('bongkar_metro_item')
        
        # Simpan data untuk digunakan nanti
        context.user_data['date_formatted'] = date_formatted
        context.user_data['current_metro_item'] = item
        
        # Tampilkan pilihan markingan
        keyboard = [
            [InlineKeyboardButton("✅ ADA", callback_data="markingan_metro_ada")],
            [InlineKeyboardButton("❌ TIDAK ADA", callback_data="markingan_metro_tidak_ada")],
            [InlineKeyboardButton("🔙 Batal", callback_data="cancel_markingan")]
        ]
        reply_markup = InlineKeyboardMarkup(keyboard)
        
        await update.message.reply_text(
            f"📦 *Metro*\n"
            f"Packing List: {item['packing_list']}\n"
            f"Koli: {item.get('koli', 0)}\n\n"
            f"Apakah barang ada markingan?",
            parse_mode='Markdown',
            reply_markup=reply_markup
        )
        return WAITING_MARKINGAN_CHOICE

async def handle_ste_input(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk input nomor STE"""
    text = update.message.text.strip()
    item = context.user_data.get('selected_item')
    row_num = item['row']
    # Update kolom H (PL STE TOKO)
    if update_cell_sudah_bongkar(row_num, 'H', text):
        update_cell_sudah_bongkar(row_num, 'I', 'Belum Turun')
        await update.message.reply_text(
            f"✅ *Berhasil update Proses Receipt!*\n"
            f"Packing List: {item['packing_list']}\n"
            f"Nomor STE: {text}",
            parse_mode='Markdown',
            reply_markup=get_main_keyboard()
        )
    else:
        await update.message.reply_text(
            "❌ Gagal update data. Coba lagi.",
            reply_markup=get_main_keyboard()
        )
    return ConversationHandler.END

async def handle_pl_selection(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk input nomor packing list yang dipilih"""
    text = update.message.text.strip()
    
    # Validasi input adalah angka
    if not text.isdigit():
        await update.message.reply_text(
            "❌ Masukkan nomor yang valid!\n"
            "Contoh: 1, 2, 3"
        )
        return WAITING_PL_SELECTION
    
    pl_number = int(text)
    remaining_items = context.user_data.get('remaining_items', [])
    
    # Validasi nomor dalam range
    if pl_number < 1 or pl_number > len(remaining_items):
        await update.message.reply_text(
            f"❌ Nomor tidak valid! Pilih antara 1-{len(remaining_items)}"
        )
        return WAITING_PL_SELECTION
    
    # Ambil item yang dipilih (index dimulai dari 0)
    selected_item = remaining_items[pl_number - 1]
    context.user_data['current_pl_item'] = selected_item
    context.user_data['current_pl_index'] = pl_number - 1
    
    container_name = context.user_data.get('bongkar_container')
    
    # Tampilkan pilihan markingan untuk packing list yang dipilih
    keyboard = [
        [InlineKeyboardButton("✅ ADA", callback_data="markingan_ada")],
        [InlineKeyboardButton("❌ TIDAK ADA", callback_data="markingan_tidak_ada")],
        [InlineKeyboardButton("🔙 Batal", callback_data="cancel_markingan")]
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)
    
    await update.message.reply_text(
        f"📦 *{container_name}*\n"
        f"Packing List: {selected_item['packing_list']}\n"
        f"Koli: {selected_item['koli']}\n\n"
        f"Apakah barang ada markingan?",
        parse_mode='Markdown',
        reply_markup=reply_markup
    )
    
    return WAITING_MARKINGAN_CHOICE

async def handle_markingan_choice(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk pilihan markingan (ADA/TIDAK ADA)"""
    query = update.callback_query
    await query.answer()
    
    choice = query.data
    
    if choice == "cancel_markingan":
        await query.edit_message_text(
            "❌ Operasi dibatalkan.",
            reply_markup=get_main_keyboard()
        )
        return ConversationHandler.END
    
    # Cek apakah ini pilihan untuk metro
    if choice.startswith("markingan_metro_"):
        markingan_value = "ADA" if choice == "markingan_metro_ada" else "TIDAK ADA"
        
        # Ambil data metro
        metro_item = context.user_data.get('current_metro_item')
        date_formatted = context.user_data.get('date_formatted')
        
        if metro_item:
            row_data = metro_item['row_data']
            
            # Buat row baru untuk Sudah Bongkar
            new_row = [
                '',  # A - NO (diisi otomatis)
                '',  # B - NO (diisi otomatis)
                row_data[2] if len(row_data) > 2 else '',  # B - PACKING LIST
                row_data[3] if len(row_data) > 3 else '',  # C - KOLI
                date_formatted,  # D - TGL BONGKAR
                'Belum Bongkar',  # E - START
                '',  # F - FINISH
                '',  # G - PL STE TOKO
                '',  # H - PINDAH KE STORE TOKO
                markingan_value  # I - MARKINGAN
            ]
            
            # Append ke Sudah Bongkar
            if append_row_sudah_bongkar(new_row):
                # Hapus dari Belum Bongkar
                if delete_row_belum_bongkar(metro_item['row']):
                    # Reorder nomor di Belum Bongkar
                    reorder_belum_bongkar_numbers()
                    await query.edit_message_text(
                        f"✅ *Berhasil memindahkan!*\n"
                        f"Packing List: {metro_item['packing_list']}\n"
                        f"Tanggal Bongkar: {date_formatted}\n"
                        f"Markingan: {markingan_value}",
                        parse_mode='Markdown',
                        reply_markup=get_main_keyboard()
                    )
                else:
                    await query.edit_message_text(
                        "⚠️ Data ditambahkan ke Sudah Bongkar, tapi gagal hapus dari Belum Bongkar.",
                        reply_markup=get_main_keyboard()
                    )
            else:
                await query.edit_message_text(
                    "❌ Gagal memindahkan data. Coba lagi.",
                    reply_markup=get_main_keyboard()
                )
        else:
            await query.edit_message_text(
                "❌ Terjadi kesalahan. Data tidak ditemukan.",
                reply_markup=get_main_keyboard()
            )
        
        return ConversationHandler.END
    
    # Tentukan nilai markingan berdasarkan pilihan (untuk container)
    markingan_value = "ADA" if choice == "markingan_ada" else "TIDAK ADA"
    
    # Ambil data yang disimpan
    current_item = context.user_data.get('current_pl_item')
    current_index = context.user_data.get('current_pl_index')
    remaining_items = context.user_data.get('remaining_items', [])
    processed_items = context.user_data.get('processed_items', [])
    date_formatted = context.user_data.get('date_formatted')
    container_name = context.user_data.get('bongkar_container')
    
    if current_item:
        row_data = current_item['row_data']
        
        # Buat row baru untuk Sudah Bongkar dengan nilai markingan yang dipilih
        new_row = [
            '',  # A - NO (diisi otomatis)
            '',  # B - NO (diisi otomatis)
            row_data[2] if len(row_data) > 2 else '',  # B - PACKING LIST
            row_data[3] if len(row_data) > 3 else '',  # C - KOLI
            date_formatted,  # D - TGL BONGKAR
            'Belum Bongkar',  # E - START
            '',  # F - FINISH
            '',  # G - PL STE TOKO
            '',  # H - PINDAH KE STORE TOKO
            markingan_value  # I - MARKINGAN (ADA atau TIDAK ADA)
        ]
        
        # Append ke Sudah Bongkar
        if append_row_sudah_bongkar(new_row):
            # Hapus dari Belum Bongkar
            if delete_row_belum_bongkar(current_item['row']):
                # Tandai item sebagai sudah diproses
                processed_items.append({
                    'item': current_item,
                    'markingan': markingan_value
                })
                
                # Hapus item dari remaining_items
                remaining_items.pop(current_index)
                context.user_data['remaining_items'] = remaining_items
                context.user_data['processed_items'] = processed_items
                
                # Update row numbers untuk item yang tersisa
                # Karena kita hapus row, row number item selanjutnya bergeser ke atas
                for item in remaining_items:
                    if item['row'] > current_item['row']:
                        item['row'] -= 1
                
                # Cek apakah masih ada item yang tersisa
                if len(remaining_items) > 0:
                    # Tampilkan list packing list yang tersisa
                    msg = f"✅ *Berhasil memproses:*\n"
                    msg += f"Packing List: {current_item['packing_list']}\n"
                    msg += f"Markingan: {markingan_value}\n\n"
                    msg += "=" * 30 + "\n\n"
                    msg += f"📦 *{container_name}*\n"
                    msg += f"Sisa Packing List: {len(remaining_items)}\n\n"
                    msg += "Pilih nomor Packing List:\n\n"
                    
                    for idx, item in enumerate(remaining_items, 1):
                        msg += f"{idx}. {item['packing_list']} ({item['koli']} Koli)\n"
                    
                    msg += "\n💡 Ketik nomor packing list yang ingin diproses"
                    
                    await query.edit_message_text(
                        msg,
                        parse_mode='Markdown'
                    )
                    return WAITING_PL_SELECTION
                else:
                    # Semua item sudah diproses
                    # Reorder nomor di Belum Bongkar
                    reorder_belum_bongkar_numbers()
                    
                    msg = f"✅ *Semua Packing List Berhasil Dipindahkan!*\n\n"
                    msg += f"📦 Container: {container_name}\n"
                    msg += f"Total Item: {len(processed_items)}\n"
                    msg += f"Tanggal Bongkar: {date_formatted}\n\n"
                    msg += "Detail:\n"
                    
                    for idx, proc in enumerate(processed_items, 1):
                        msg += f"{idx}. {proc['item']['packing_list']} - {proc['markingan']}\n"
                    
                    await query.edit_message_text(
                        msg,
                        parse_mode='Markdown',
                        reply_markup=get_main_keyboard()
                    )
                    return ConversationHandler.END
            else:
                await query.edit_message_text(
                    "❌ Gagal menghapus dari Belum Bongkar.",
                    reply_markup=get_main_keyboard()
                )
                return ConversationHandler.END
        else:
            await query.edit_message_text(
                "❌ Gagal menambahkan ke Sudah Bongkar.",
                reply_markup=get_main_keyboard()
            )
            return ConversationHandler.END
    else:
        await query.edit_message_text(
            "❌ Terjadi kesalahan. Data tidak ditemukan.",
            reply_markup=get_main_keyboard()
        )
        return ConversationHandler.END

async def cancel(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk cancel conversation"""
    await update.message.reply_text(
        "❌ Operasi dibatalkan.",
        reply_markup=get_main_keyboard()
    )
    return ConversationHandler.END

# ==========================================
# ERROR HANDLER
# ==========================================

async def error_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Global error handler untuk bot"""
    logger.error(f"Exception while handling an update: {context.error}")
    
    # Jika ada update object dan message, coba kirim pesan error ke user
    try:
        if update and update.effective_message:
            await update.effective_message.reply_text(
                "❌ Terjadi kesalahan. Silakan coba lagi atau gunakan /menu untuk kembali ke menu utama."
            )
    except Exception as e:
        logger.error(f"Failed to send error message to user: {e}")

# ==========================================
# MAIN FUNCTION
# ==========================================

def main():
    """Main function"""
    logger.info("🚀 Starting Inventory Management Bot (COMBINED VERSION)...")
    logger.info("📝 FITUR GABUNGAN:")
    logger.info("   - Semua fungsi dari inventory_bot(7).py")
    logger.info("   - Container dengan kode sama digabungkan")
    logger.info("   - Estimasi dari TG NOTA paling awal")
    logger.info("   - Format tanggal estimasi bahasa Indonesia")
    logger.info("   - Format output estimasi yang lebih jelas")
    logger.info("   - Item dengan estimasi sama digabung dalam 1 nomor urut")
    logger.info("   - Barang hari ini diprioritaskan paling atas")
    logger.info("   - Error handling yang lebih baik")
    
    # Test Google Sheets connection
    spreadsheet = get_spreadsheet()
    if not spreadsheet:
        logger.error("❌ Failed to connect to Google Sheets. Exiting...")
        logger.error("=" * 50)
        logger.error("TROUBLESHOOTING:")
        logger.error("1. Pastikan credentials.json ada di /root/")
        logger.error("2. Pastikan SPREADSHEET_ID atau SPREADSHEET_NAME benar")
        logger.error("3. Pastikan spreadsheet di-share dengan service account email")
        logger.error("4. Cek email service account di credentials.json")
        logger.error("=" * 50)
        return
    
    if USE_SPREADSHEET_ID:
        logger.info(f"✅ Connected to spreadsheet ID: {SPREADSHEET_ID}")
    else:
        logger.info(f"✅ Connected to spreadsheet: {SPREADSHEET_NAME}")
    
    # Build application dengan konfigurasi timeout yang lebih baik
    application = (
        Application.builder()
        .token(TELEGRAM_TOKEN)
        .connect_timeout(30)
        .read_timeout(30)
        .write_timeout(30)
        .pool_timeout(30)
        .build()
    )
    
    # Conversation handler
    conv_handler = ConversationHandler(
        entry_points=[
            CallbackQueryHandler(handle_belum_bongkar_sb, pattern='^belum_bongkar_sb$'),
            CallbackQueryHandler(handle_proses_check, pattern='^proses_check$'),
            CallbackQueryHandler(handle_proses_receipt, pattern='^proses_receipt$'),
            CallbackQueryHandler(handle_belum_turun, pattern='^belum_turun$'),
            CallbackQueryHandler(handle_bongkar_container_start, pattern='^bongkar_container_'),
            CallbackQueryHandler(handle_bongkar_metro_start, pattern='^bongkar_metro_'),
            CallbackQueryHandler(handle_tambah_pl_baru_start, pattern='^tambah_pl_baru$'),
        ],
        states={
            WAITING_NUMBER: [MessageHandler(filters.TEXT & ~filters.COMMAND, handle_number_input)],
            WAITING_DATE: [MessageHandler(filters.TEXT & ~filters.COMMAND, handle_date_input)],
            WAITING_STE: [MessageHandler(filters.TEXT & ~filters.COMMAND, handle_ste_input)],
            WAITING_PL_NAME: [MessageHandler(filters.TEXT & ~filters.COMMAND, handle_pl_name_input)],
            WAITING_KOLI: [MessageHandler(filters.TEXT & ~filters.COMMAND, handle_koli_input)],
            WAITING_MARKING: [CallbackQueryHandler(handle_marking_selection, pattern='^marking_')],
            WAITING_TG_NOTA: [MessageHandler(filters.TEXT & ~filters.COMMAND, handle_tg_nota_input)],
            WAITING_CONTAINER_CODE: [MessageHandler(filters.TEXT & ~filters.COMMAND, handle_container_code_input)],
            WAITING_MARKINGAN_CHOICE: [CallbackQueryHandler(handle_markingan_choice, pattern='^(markingan_|cancel_markingan)')],
            WAITING_PL_SELECTION: [MessageHandler(filters.TEXT & ~filters.COMMAND, handle_pl_selection)],
        },
        fallbacks=[CommandHandler('cancel', cancel)],
        allow_reentry=True,
    )
    
    # Add handlers
    application.add_handler(CommandHandler("start", start))
    application.add_handler(CommandHandler("menu", menu_command))
    application.add_handler(conv_handler)
    application.add_handler(CallbackQueryHandler(button_callback))
    
    # Add global error handler
    application.add_error_handler(error_handler)
    
    logger.info("✅ Bot started successfully!")
    logger.info(f"📊 Monitoring sheets: {SHEET_SUDAH_BONGKAR}, {SHEET_BELUM_BONGKAR}, {SHEET_CHECK_POAN}")
    application.run_polling(allowed_updates=Update.ALL_TYPES)

if __name__ == '__main__':
    main()