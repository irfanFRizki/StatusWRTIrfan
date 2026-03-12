#!/usr/bin/env python3
"""
Telegram Bot Perawatan Motor v2
Untuk monitoring jadwal service motor Honda PCX (Irfan) dan BEAT (Anita)
"""
import json
import os
import sys
import logging
from datetime import datetime, timedelta
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import (
    Application,
    CommandHandler,
    CallbackQueryHandler,
    MessageHandler,
    filters,
    ContextTypes,
    ConversationHandler
)

# ============== KONSTANTA ==============
# Gunakan path absolut agar work di CLI maupun init.d
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_FILE = os.path.join(SCRIPT_DIR, 'data_motor.json')
LOG_FILE = os.path.join(SCRIPT_DIR, 'bot_debug.log')

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)
logger.info(f"Script started from: {SCRIPT_DIR}")
logger.info(f"Data file: {DATA_FILE}")

# Konfigurasi jadwal perawatan per motor (dalam km)
MAINTENANCE_SCHEDULE = {
    'PCX': {
        'oli_mesin': 2500,
        'oli_samping': 5000,
        'rem': 8000,
        'vbelt': 24000,
        'tangki_liter': 8.1,
        'bar_penuh': 9,
        'liter_per_bar': 0.85  # rata-rata 0.8-0.9
    },
    'BEAT': {
        'oli_mesin': 2000,
        'oli_samping': 4000,
        'rem': 6000,
        'vbelt': 20000,
        'tangki_liter': 4.1,
        'bar_penuh': 6,
        'liter_per_bar': 0.65  # rata-rata 0.6-0.7
    }
}

# Harga bensin default (bisa diubah)
DEFAULT_FUEL_PRICES = {
    'pertalite': 10000,
    'pertamax': 12750
}

# States untuk conversation handler
(WAITING_INITIAL_KM, WAITING_KM, WAITING_PRICE, WAITING_KM_PURCHASE,
 WAITING_PAJAK_DATE, WAITING_PAJAK_NOMINAL, WAITING_FUEL_AMOUNT,
 WAITING_FUEL_KM, WAITING_FUEL_BAR, WAITING_FUEL_PRICE_PERTALITE,
 WAITING_FUEL_PRICE_PERTAMAX, WAITING_CHECK_FUEL_KM) = range(12)

# ============== FUNGSI UTILITAS ==============

def load_data():
    """Load data dari file JSON"""
    logger.info(f"Loading data from: {DATA_FILE}")
    if os.path.exists(DATA_FILE):
        try:
            with open(DATA_FILE, 'r') as f:
                data = json.load(f)
            logger.info(f"Data loaded successfully. Users: {list(data.keys())}")
            return data
        except Exception as e:
            logger.error(f"Error loading data: {e}")
    
    # Default data structure
    logger.info("Creating default data structure")
    return {
        "IRFAN": {
            "motor": "PCX",
            "initial_km": 0,
            "oli_mesin": {"last_km": 0, "last_date": "", "price": 0},
            "oli_samping": {"last_km": 0, "last_date": "", "price": 0},
            "rem_depan": {"last_km": 0, "last_date": "", "price": 0},
            "rem_belakang": {"last_km": 0, "last_date": "", "price": 0},
            "vbelt": {"last_km": 0, "last_date": "", "price": 0},
            "pajak": {"due_date": "", "payments": []},
            "bensin": {
                "fuel_prices": DEFAULT_FUEL_PRICES.copy(),
                "purchases": []
            }
        },
        "ANITA": {
            "motor": "BEAT",
            "initial_km": 0,
            "oli_mesin": {"last_km": 0, "last_date": "", "price": 0},
            "oli_samping": {"last_km": 0, "last_date": "", "price": 0},
            "rem_depan": {"last_km": 0, "last_date": "", "price": 0},
            "rem_belakang": {"last_km": 0, "last_date": "", "price": 0},
            "vbelt": {"last_km": 0, "last_date": "", "price": 0},
            "pajak": {"due_date": "", "payments": []},
            "bensin": {
                "fuel_prices": DEFAULT_FUEL_PRICES.copy(),
                "purchases": []
            }
        }
    }

def save_data(data):
    """Simpan data ke file JSON"""
    try:
        logger.info(f"Saving data to: {DATA_FILE}")
        with open(DATA_FILE, 'w') as f:
            json.dump(data, f, indent=2)
        logger.info("Data saved successfully")
    except Exception as e:
        logger.error(f"Error saving data: {e}")

def calculate_remaining(last_km, current_km, interval):
    """Hitung sisa km sampai service berikutnya"""
    if last_km == 0:
        return interval - current_km
    km_since_last = current_km - last_km
    remaining = interval - km_since_last
    return remaining

def get_pajak_info(due_date_str):
    """Hitung informasi pajak"""
    if not due_date_str:
        return None
    try:
        day, month = map(int, due_date_str.split('-'))
        today = datetime.now()
        # Coba tahun ini
        due_date = datetime(today.year, month, day)
        # Jika sudah lewat, pakai tahun depan
        if due_date < today:
            due_date = datetime(today.year + 1, month, day)
        diff = due_date - today
        months = diff.days // 30
        days = diff.days % 30
        bulan_name = [
            "Januari", "Februari", "Maret", "April", "Mei", "Juni",
            "Juli", "Agustus", "September", "Oktober", "November", "Desember"
        ]
        return {
            'date_text': f"{day} {bulan_name[month-1]}",
            'remaining_text': f"{months} bulan {days} hari lagi" if months > 0 else f"{diff.days} hari lagi",
            'is_urgent': diff.days <= 30
        }
    except Exception as e:
        logger.error(f"Error in get_pajak_info: {e}")
        return None

# ============== HANDLER FUNCTIONS ==============

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk /start command"""
    keyboard = [
        [InlineKeyboardButton("🏍️ IRFAN (PCX)", callback_data='user_IRFAN')],
        [InlineKeyboardButton("🛵 ANITA (BEAT)", callback_data='user_ANITA')]
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)
    await update.message.reply_text(
        "🔧 *Bot Perawatan Motor*\n\n"
        "Pilih motor:",
        parse_mode='Markdown',
        reply_markup=reply_markup
    )

async def user_selected(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler ketika user memilih motor"""
    query = update.callback_query
    await query.answer()
    user = query.data.split('_')[1]
    context.user_data['selected_user'] = user
    logger.info(f"User selected: {user}")
    data = load_data()
    motor = data[user]['motor']
    logger.info(f"Motor: {motor}, Initial KM: {data[user]['initial_km']}")
    
    # Cek apakah sudah ada initial km
    if data[user]['initial_km'] == 0:
        logger.info("No initial km found, asking for input")
        await query.edit_message_text(
            f"*Motor: {motor}* ({user})\n\n"
            "🆕 Belum ada data km spedometer awal.\n\n"
            "Masukkan km spedometer saat ini:",
            parse_mode='Markdown'
        )
        return WAITING_INITIAL_KM
    else:
        logger.info("Initial km exists, showing main menu")
        await show_main_menu(query, user, motor)
        return ConversationHandler.END

async def initial_km_received(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler ketika user input km awal pertama kali"""
    try:
        km = int(update.message.text.replace(',', '').replace('.', ''))
        user = context.user_data.get('selected_user', 'IRFAN')
        data = load_data()
        data[user]['initial_km'] = km
        save_data(data)
        keyboard = [[InlineKeyboardButton("✅ Lanjut ke Menu", callback_data=f'user_{user}')]]
        reply_markup = InlineKeyboardMarkup(keyboard)
        await update.message.reply_text(
            f"✅ *Km awal tersimpan: {km:,} km*\n\n"
            "Silakan lanjut ke menu untuk mulai mencatat perawatan.",
            parse_mode='Markdown',
            reply_markup=reply_markup
        )
        return ConversationHandler.END
    except ValueError:
        await update.message.reply_text(
            "❌ Input tidak valid. Masukkan angka saja.\n\n"
            "Contoh: 15000"
        )
        return WAITING_INITIAL_KM

async def show_main_menu(query_or_update, user, motor):
    """Tampilkan menu utama"""
    keyboard = [
        [InlineKeyboardButton("📊 STATUS", callback_data='menu_STATUS')],
        [InlineKeyboardButton("🛢️ OLI", callback_data='menu_OLI')],
        [InlineKeyboardButton("🔴 REM", callback_data='menu_REM')],
        [InlineKeyboardButton("⚙️ V-BELT", callback_data='menu_VBELT')],
        [InlineKeyboardButton("⛽ BENSIN", callback_data='menu_BENSIN')],
        [InlineKeyboardButton("📋 PAJAK MOTOR", callback_data='menu_PAJAK')],
        [InlineKeyboardButton("🔙 Kembali", callback_data='back_to_start')]
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)
    text = f"*Motor: {motor}* ({user})\n\nPilih menu:"
    
    if hasattr(query_or_update, 'edit_message_text'):
        await query_or_update.edit_message_text(text, parse_mode='Markdown', reply_markup=reply_markup)
    else:
        await query_or_update.message.reply_text(text, parse_mode='Markdown', reply_markup=reply_markup)

async def show_status(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Tampilkan status semua komponen"""
    query = update.callback_query
    await query.answer()
    user = context.user_data.get('selected_user', 'IRFAN')
    data = load_data()
    user_data = data[user]
    motor = user_data['motor']
    schedule = MAINTENANCE_SCHEDULE[motor]
    
    status_text = f"*📊 STATUS PERAWATAN - {motor}*\n\n"
    status_text += f"📍 Km Awal Motor: {user_data['initial_km']:,} km\n\n"
    
    # Status Oli Mesin
    oli_mesin = user_data['oli_mesin']
    if oli_mesin['last_km'] > 0:
        status_text += f"🛢️ *Oli Mesin:*\n"
        status_text += f"  Terakhir ganti: {oli_mesin['last_date']}\n"
        status_text += f"  Km: {oli_mesin['last_km']:,} km\n"
        status_text += f"  Harga: Rp {oli_mesin['price']:,}\n"
        status_text += f"  Service berikutnya: {oli_mesin['last_km'] + schedule['oli_mesin']:,} km\n\n"
    else:
        status_text += "🛢️ *Oli Mesin:* Belum ada data\n\n"
    
    # Status Oli Samping
    oli_samping = user_data['oli_samping']
    if oli_samping['last_km'] > 0:
        status_text += f"🛢️ *Oli Samping:*\n"
        status_text += f"  Terakhir ganti: {oli_samping['last_date']}\n"
        status_text += f"  Km: {oli_samping['last_km']:,} km\n"
        status_text += f"  Harga: Rp {oli_samping['price']:,}\n"
        status_text += f"  Service berikutnya: {oli_samping['last_km'] + schedule['oli_samping']:,} km\n\n"
    else:
        status_text += "🛢️ *Oli Samping:* Belum ada data\n\n"
    
    # Status Rem Depan
    rem_depan = user_data['rem_depan']
    if rem_depan['last_km'] > 0:
        status_text += f"🔴 *Rem Depan:*\n"
        status_text += f"  Terakhir ganti: {rem_depan['last_date']}\n"
        status_text += f"  Km: {rem_depan['last_km']:,} km\n"
        status_text += f"  Harga: Rp {rem_depan['price']:,}\n"
        status_text += f"  Service berikutnya: {rem_depan['last_km'] + schedule['rem']:,} km\n\n"
    else:
        status_text += "🔴 *Rem Depan:* Belum ada data\n\n"
    
    # Status Rem Belakang
    rem_belakang = user_data['rem_belakang']
    if rem_belakang['last_km'] > 0:
        status_text += f"🔴 *Rem Belakang:*\n"
        status_text += f"  Terakhir ganti: {rem_belakang['last_date']}\n"
        status_text += f"  Km: {rem_belakang['last_km']:,} km\n"
        status_text += f"  Harga: Rp {rem_belakang['price']:,}\n"
        status_text += f"  Service berikutnya: {rem_belakang['last_km'] + schedule['rem']:,} km\n\n"
    else:
        status_text += "🔴 *Rem Belakang:* Belum ada data\n\n"
    
    # Status V-Belt
    vbelt = user_data['vbelt']
    if vbelt['last_km'] > 0:
        status_text += f"⚙️ *V-Belt:*\n"
        status_text += f"  Terakhir ganti: {vbelt['last_date']}\n"
        status_text += f"  Km: {vbelt['last_km']:,} km\n"
        status_text += f"  Harga: Rp {vbelt['price']:,}\n"
        status_text += f"  Service berikutnya: {vbelt['last_km'] + schedule['vbelt']:,} km\n\n"
    else:
        status_text += "⚙️ *V-Belt:* Belum ada data\n\n"
    
    # Status Pajak
    pajak_info = get_pajak_info(user_data['pajak']['due_date'])
    if pajak_info:
        urgent = "⚠️ " if pajak_info['is_urgent'] else ""
        status_text += f"📋 *Pajak Motor:*\n"
        status_text += f"  {urgent}Jatuh tempo: {pajak_info['date_text']}\n"
        status_text += f"  Sisa waktu: {pajak_info['remaining_text']}\n\n"
        
        # Riwayat pembayaran terakhir
        payments = user_data['pajak']['payments']
        if payments:
            last_payment = payments[-1]
            status_text += f"  Terakhir bayar: {last_payment['date']}\n"
            status_text += f"  Nominal: Rp {last_payment['amount']:,}\n\n"
    else:
        status_text += "📋 *Pajak Motor:* Belum ada data\n\n"
    
    # Status Bensin
    if 'bensin' in user_data and user_data['bensin']['purchases']:
        status_text += "\n⛽ *Bensin:*\n"
        last_fuel = user_data['bensin']['purchases'][-1]
        fuel_name = "Pertalite" if last_fuel['fuel_type'] == 'pertalite' else "Pertamax"
        status_text += f"  Terakhir isi: {last_fuel['date']}\n"
        status_text += f"  Jenis: {fuel_name}\n"
        status_text += f"  Km: {last_fuel['km']:,} km\n"
        status_text += f"  Isi: {last_fuel['liters']:.2f}L (Rp {last_fuel['amount']:,})\n\n"
    else:
        status_text += "\n⛽ *Bensin:* Belum ada data\n\n"
    
    keyboard = [[InlineKeyboardButton("🔙 Kembali", callback_data=f'user_{user}')]]
    reply_markup = InlineKeyboardMarkup(keyboard)
    await query.edit_message_text(
        status_text,
        parse_mode='Markdown',
        reply_markup=reply_markup
    )

async def menu_oli_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk menu OLI"""
    query = update.callback_query
    await query.answer()
    keyboard = [
        [InlineKeyboardButton("🛢️ Cek Status Oli", callback_data='oli_CHECK')],
        [InlineKeyboardButton("🛒 Beli Oli Baru", callback_data='oli_BUY')],
        [InlineKeyboardButton("🔙 Kembali", callback_data='back_to_menu')]
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)
    await query.edit_message_text(
        "*🛢️ MENU OLI*\n\n"
        "Pilih aksi:",
        parse_mode='Markdown',
        reply_markup=reply_markup
    )

async def oli_check_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk cek status oli"""
    query = update.callback_query
    await query.answer()
    await query.edit_message_text(
        "*Cek Status Oli*\n\n"
        "Masukkan km spedometer saat ini:",
        parse_mode='Markdown'
    )
    context.user_data['oli_action'] = 'CHECK'
    return WAITING_KM

async def oli_buy_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk beli oli baru"""
    query = update.callback_query
    await query.answer()
    keyboard = [
        [InlineKeyboardButton("🛢️ Oli Mesin Saja", callback_data='oli_type_MESIN')],
        [InlineKeyboardButton("🛢️ Oli Mesin + Samping", callback_data='oli_type_BOTH')],
        [InlineKeyboardButton("🔙 Batal", callback_data='menu_OLI')]
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)
    await query.edit_message_text(
        "*Beli Oli Baru*\n\n"
        "Pilih jenis oli yang dibeli:",
        parse_mode='Markdown',
        reply_markup=reply_markup
    )

async def oli_type_selected(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler ketika pilih jenis oli"""
    query = update.callback_query
    await query.answer()
    oli_type = query.data.split('_')[2]
    context.user_data['oli_type'] = oli_type
    context.user_data['oli_action'] = 'BUY'
    type_text = "Oli Mesin Saja" if oli_type == 'MESIN' else "Oli Mesin + Samping"
    await query.edit_message_text(
        f"*Beli: {type_text}*\n\n"
        "Masukkan km spedometer saat ini:",
        parse_mode='Markdown'
    )
    return WAITING_KM

async def menu_rem_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk menu REM"""
    query = update.callback_query
    await query.answer()
    keyboard = [
        [InlineKeyboardButton("🔴 Cek Status Rem", callback_data='rem_CHECK')],
        [InlineKeyboardButton("🛒 Beli Rem Baru", callback_data='rem_BUY')],
        [InlineKeyboardButton("🔙 Kembali", callback_data='back_to_menu')]
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)
    await query.edit_message_text(
        "*🔴 MENU REM*\n\n"
        "Pilih aksi:",
        parse_mode='Markdown',
        reply_markup=reply_markup
    )

async def rem_check_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk cek status rem"""
    query = update.callback_query
    await query.answer()
    await query.edit_message_text(
        "*Cek Status Rem*\n\n"
        "Masukkan km spedometer saat ini:",
        parse_mode='Markdown'
    )
    context.user_data['rem_action'] = 'CHECK'
    return WAITING_KM

async def rem_buy_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk beli rem baru"""
    query = update.callback_query
    await query.answer()
    keyboard = [
        [InlineKeyboardButton("🔴 Rem Depan", callback_data='rem_type_DEPAN')],
        [InlineKeyboardButton("🔴 Rem Belakang", callback_data='rem_type_BELAKANG')],
        [InlineKeyboardButton("🔙 Batal", callback_data='menu_REM')]
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)
    await query.edit_message_text(
        "*Beli Rem Baru*\n\n"
        "Pilih jenis rem yang dibeli:",
        parse_mode='Markdown',
        reply_markup=reply_markup
    )

async def rem_type_selected(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler ketika pilih jenis rem"""
    query = update.callback_query
    await query.answer()
    rem_type = query.data.split('_')[2]
    context.user_data['rem_type'] = rem_type
    context.user_data['rem_action'] = 'BUY'
    type_text = "Rem Depan" if rem_type == 'DEPAN' else "Rem Belakang"
    await query.edit_message_text(
        f"*Beli: {type_text}*\n\n"
        "Masukkan km spedometer saat beli:",
        parse_mode='Markdown'
    )
    return WAITING_KM_PURCHASE

async def menu_vbelt_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk menu V-BELT"""
    query = update.callback_query
    await query.answer()
    keyboard = [
        [InlineKeyboardButton("⚙️ Cek Status V-Belt", callback_data='vbelt_CHECK')],
        [InlineKeyboardButton("🛒 Beli V-Belt Baru", callback_data='vbelt_BUY')],
        [InlineKeyboardButton("🔙 Kembali", callback_data='back_to_menu')]
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)
    await query.edit_message_text(
        "*⚙️ MENU V-BELT*\n\n"
        "Pilih aksi:",
        parse_mode='Markdown',
        reply_markup=reply_markup
    )

async def vbelt_check_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk cek status v-belt"""
    query = update.callback_query
    await query.answer()
    await query.edit_message_text(
        "*Cek Status V-Belt*\n\n"
        "Masukkan km spedometer saat ini:",
        parse_mode='Markdown'
    )
    context.user_data['vbelt_action'] = 'CHECK'
    return WAITING_KM

async def vbelt_buy_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk beli v-belt baru"""
    query = update.callback_query
    await query.answer()
    context.user_data['vbelt_action'] = 'BUY'
    await query.edit_message_text(
        "*Beli V-Belt Baru*\n\n"
        "Masukkan km spedometer saat beli:",
        parse_mode='Markdown'
    )
    return WAITING_KM_PURCHASE

async def km_received(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler ketika user input km untuk CEK status"""
    try:
        km = int(update.message.text.replace(',', '').replace('.', ''))
        context.user_data['current_km'] = km
        user = context.user_data.get('selected_user', 'IRFAN')
        data = load_data()
        motor = data[user]['motor']
        schedule = MAINTENANCE_SCHEDULE[motor]
        
        # Cek action type
        if 'oli_action' in context.user_data and context.user_data['oli_action'] == 'CHECK':
            # Cek status oli
            oli_mesin = data[user]['oli_mesin']
            oli_samping = data[user]['oli_samping']
            message = f"*Status Oli - Km: {km:,}*\n\n"
            
            if oli_mesin['last_km'] > 0:
                remaining_mesin = calculate_remaining(oli_mesin['last_km'], km, schedule['oli_mesin'])
                if remaining_mesin > 0:
                    message += f"🛢️ Oli Mesin: Masih {remaining_mesin:,} km lagi\n"
                else:
                    message += f"⚠️ Oli Mesin: Sudah telat {abs(remaining_mesin):,} km!\n"
            else:
                message += "🛢️ Oli Mesin: Belum ada data\n"
            
            if oli_samping['last_km'] > 0:
                remaining_samping = calculate_remaining(oli_samping['last_km'], km, schedule['oli_samping'])
                if remaining_samping > 0:
                    message += f"🛢️ Oli Samping: Masih {remaining_samping:,} km lagi\n"
                else:
                    message += f"⚠️ Oli Samping: Sudah telat {abs(remaining_samping):,} km!\n"
            else:
                message += "🛢️ Oli Samping: Belum ada data\n"
            
            keyboard = [[InlineKeyboardButton("🔙 Kembali", callback_data='menu_OLI')]]
        
        elif 'rem_action' in context.user_data and context.user_data['rem_action'] == 'CHECK':
            # Cek status rem
            rem_depan = data[user]['rem_depan']
            rem_belakang = data[user]['rem_belakang']
            message = f"*Status Rem - Km: {km:,}*\n\n"
            
            if rem_depan['last_km'] > 0:
                remaining = calculate_remaining(rem_depan['last_km'], km, schedule['rem'])
                if remaining > 0:
                    message += f"🔴 Rem Depan: Masih {remaining:,} km lagi\n"
                else:
                    message += f"⚠️ Rem Depan: Sudah telat {abs(remaining):,} km!\n"
            else:
                message += "🔴 Rem Depan: Belum ada data\n"
            
            if rem_belakang['last_km'] > 0:
                remaining = calculate_remaining(rem_belakang['last_km'], km, schedule['rem'])
                if remaining > 0:
                    message += f"🔴 Rem Belakang: Masih {remaining:,} km lagi\n"
                else:
                    message += f"⚠️ Rem Belakang: Sudah telat {abs(remaining):,} km!\n"
            else:
                message += "🔴 Rem Belakang: Belum ada data\n"
            
            keyboard = [[InlineKeyboardButton("🔙 Kembali", callback_data='menu_REM')]]
        
        elif 'vbelt_action' in context.user_data and context.user_data['vbelt_action'] == 'CHECK':
            # Cek status v-belt
            vbelt = data[user]['vbelt']
            message = f"*Status V-Belt - Km: {km:,}*\n\n"
            
            if vbelt['last_km'] > 0:
                remaining = calculate_remaining(vbelt['last_km'], km, schedule['vbelt'])
                if remaining > 0:
                    message += f"⚙️ V-Belt: Masih {remaining:,} km lagi\n"
                else:
                    message += f"⚠️ V-Belt: Sudah telat {abs(remaining):,} km!\n"
            else:
                message += "⚙️ V-Belt: Belum ada data\n"
            
            keyboard = [[InlineKeyboardButton("🔙 Kembali", callback_data='menu_VBELT')]]
        
        # Jika BUY, langsung ke input harga
        elif ('oli_action' in context.user_data and context.user_data['oli_action'] == 'BUY'):
            await update.message.reply_text(
                f"Km: {km:,}\n"
                "Masukkan harga oli (Rupiah):"
            )
            return WAITING_PRICE
        
        else:
            message = "Error: Aksi tidak dikenali"
            keyboard = [[InlineKeyboardButton("🔙 Kembali", callback_data=f'user_{user}')]]
        
        reply_markup = InlineKeyboardMarkup(keyboard)
        await update.message.reply_text(message, parse_mode='Markdown', reply_markup=reply_markup)
        return ConversationHandler.END
        
    except ValueError:
        await update.message.reply_text(
            "❌ Input tidak valid. Masukkan angka saja.\n\n"
            "Contoh: 15000"
        )
        return WAITING_KM

async def km_purchase_received(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler ketika user input km untuk PEMBELIAN"""
    try:
        km = int(update.message.text.replace(',', '').replace('.', ''))
        context.user_data['purchase_km'] = km
        await update.message.reply_text(
            f"Km: {km:,}\n"
            "Masukkan harga (Rupiah):"
        )
        return WAITING_PRICE
    except ValueError:
        await update.message.reply_text(
            "❌ Input tidak valid. Masukkan angka saja.\n\n"
            "Contoh: 15000"
        )
        return WAITING_KM_PURCHASE

async def price_received(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler ketika user input harga"""
    try:
        price = int(update.message.text.replace(',', '').replace('.', ''))
        user = context.user_data.get('selected_user', 'IRFAN')
        km = context.user_data.get('purchase_km', context.user_data.get('current_km', 0))
        data = load_data()
        motor = data[user]['motor']
        schedule = MAINTENANCE_SCHEDULE[motor]
        today = datetime.now().strftime("%d-%m-%Y")
        
        message = "✅ *Data tersimpan!*\n\n"
        message += f"Tanggal: {today}\n"
        message += f"Km: {km:,} km\n"
        message += f"Harga: Rp {price:,}\n\n"
        
        # Simpan data sesuai jenis
        if 'oli_action' in context.user_data and context.user_data['oli_action'] == 'BUY':
            oli_type = context.user_data.get('oli_type', 'MESIN')
            if oli_type == 'MESIN':
                data[user]['oli_mesin']['last_km'] = km
                data[user]['oli_mesin']['last_date'] = today
                data[user]['oli_mesin']['price'] = price
                message += f"Service berikutnya: {km + schedule['oli_mesin']:,} km"
            else:  # BOTH
                data[user]['oli_mesin']['last_km'] = km
                data[user]['oli_mesin']['last_date'] = today
                data[user]['oli_mesin']['price'] = price
                data[user]['oli_samping']['last_km'] = km
                data[user]['oli_samping']['last_date'] = today
                data[user]['oli_samping']['price'] = price
                message += f"Service Oli Mesin: {km + schedule['oli_mesin']:,} km\n"
                message += f"Service Oli Samping: {km + schedule['oli_samping']:,} km"
            callback_data = 'menu_OLI'
        
        elif 'rem_action' in context.user_data and context.user_data['rem_action'] == 'BUY':
            rem_type = context.user_data.get('rem_type', 'DEPAN')
            if rem_type == 'DEPAN':
                data[user]['rem_depan']['last_km'] = km
                data[user]['rem_depan']['last_date'] = today
                data[user]['rem_depan']['price'] = price
            else:
                data[user]['rem_belakang']['last_km'] = km
                data[user]['rem_belakang']['last_date'] = today
                data[user]['rem_belakang']['price'] = price
            message += f"Service berikutnya: {km + schedule['rem']:,} km"
            callback_data = 'menu_REM'
        
        elif 'vbelt_action' in context.user_data and context.user_data['vbelt_action'] == 'BUY':
            data[user]['vbelt']['last_km'] = km
            data[user]['vbelt']['last_date'] = today
            data[user]['vbelt']['price'] = price
            message += f"Service berikutnya: {km + schedule['vbelt']:,} km"
            callback_data = 'menu_VBELT'
        
        else:
            callback_data = f'user_{user}'
        
        save_data(data)
        keyboard = [[InlineKeyboardButton("🔙 Kembali", callback_data=callback_data)]]
        reply_markup = InlineKeyboardMarkup(keyboard)
        await update.message.reply_text(
            message,
            parse_mode='Markdown',
            reply_markup=reply_markup
        )
        return ConversationHandler.END
    except ValueError:
        await update.message.reply_text(
            "❌ Input tidak valid. Masukkan angka saja.\n\n"
            "Contoh: 85000"
        )
        return WAITING_PRICE

# ============== PAJAK HANDLERS ==============
async def menu_pajak(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk menu pajak"""
    query = update.callback_query
    await query.answer()
    user = context.user_data.get('selected_user', 'IRFAN')
    data = load_data()
    pajak_info = get_pajak_info(data[user]['pajak']['due_date'])
    
    if pajak_info:
        urgent = "⚠️ SEGERA! " if pajak_info['is_urgent'] else ""
        message = f"📋 *Pajak Motor*\n\n"
        message += f"{urgent}Jatuh tempo: {pajak_info['date_text']}\n"
        message += f"Sisa waktu: {pajak_info['remaining_text']}\n\n"
        
        # Riwayat pembayaran
        payments = data[user]['pajak']['payments']
        if payments:
            message += "*Riwayat Pembayaran:*\n"
            for i, payment in enumerate(payments[-3:], 1):  # Show last 3
                message += f"{i}. {payment['date']} - Rp {payment['amount']:,}\n"
        
        keyboard = [
            [InlineKeyboardButton("💰 Bayar Pajak", callback_data='pajak_PAY')],
            [InlineKeyboardButton("✏️ Ubah Tanggal JT", callback_data='pajak_EDIT')],
            [InlineKeyboardButton("🔙 Kembali", callback_data=f'user_{user}')]
        ]
    else:
        message = (
            "📋 *Pajak Motor*\n\n"
            "Belum ada data jatuh tempo pajak.\n\n"
            "Masukkan tanggal jatuh tempo pajak.\n"
            "Format: DD-MM\n"
            "Contoh: 25-07"
        )
        keyboard = [[InlineKeyboardButton("🔙 Batal", callback_data=f'user_{user}')]]
    
    reply_markup = InlineKeyboardMarkup(keyboard)
    await query.edit_message_text(message, parse_mode='Markdown', reply_markup=reply_markup)
    
    if pajak_info:
        return ConversationHandler.END
    else:
        return WAITING_PAJAK_DATE

async def pajak_pay_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk bayar pajak"""
    query = update.callback_query
    await query.answer()
    await query.edit_message_text(
        "*Bayar Pajak Motor*\n\n"
        "Masukkan nominal pembayaran pajak (Rupiah):"
    )
    return WAITING_PAJAK_NOMINAL

async def pajak_nominal_received(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler ketika user input nominal pajak"""
    try:
        amount = int(update.message.text.replace(',', '').replace('.', ''))
        user = context.user_data.get('selected_user', 'IRFAN')
        data = load_data()
        today = datetime.now().strftime("%d-%m-%Y")
        payment_record = {
            'date': today,
            'amount': amount
        }
        data[user]['pajak']['payments'].append(payment_record)
        save_data(data)
        keyboard = [[InlineKeyboardButton("🔙 Kembali", callback_data='menu_PAJAK')]]
        reply_markup = InlineKeyboardMarkup(keyboard)
        await update.message.reply_text(
            f"✅ *Pembayaran pajak tersimpan!*\n\n"
            f"Tanggal: {today}\n"
            f"Nominal: Rp {amount:,}",
            parse_mode='Markdown',
            reply_markup=reply_markup
        )
        return ConversationHandler.END
    except ValueError:
        await update.message.reply_text(
            "❌ Input tidak valid. Masukkan angka saja.\n\n"
            "Contoh: 250000"
        )
        return WAITING_PAJAK_NOMINAL

async def pajak_edit(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk edit tanggal pajak"""
    query = update.callback_query
    await query.answer()
    user = context.user_data.get('selected_user', 'IRFAN')
    keyboard = [[InlineKeyboardButton("🔙 Batal", callback_data='menu_PAJAK')]]
    reply_markup = InlineKeyboardMarkup(keyboard)
    await query.edit_message_text(
        "Masukkan tanggal jatuh tempo pajak.\n"
        "Format: DD-MM\n"
        "Contoh: 25-07",
        reply_markup=reply_markup
    )
    return WAITING_PAJAK_DATE

async def pajak_date_received(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler ketika user input tanggal pajak"""
    try:
        date_input = update.message.text.strip()
        # Validasi format
        day, month = map(int, date_input.split('-'))
        if not (1 <= day <= 31 and 1 <= month <= 12):
            raise ValueError
        
        user = context.user_data.get('selected_user', 'IRFAN')
        data = load_data()
        data[user]['pajak']['due_date'] = date_input
        save_data(data)
        pajak_info = get_pajak_info(date_input)
        keyboard = [[InlineKeyboardButton("🔙 Kembali", callback_data='menu_PAJAK')]]
        reply_markup = InlineKeyboardMarkup(keyboard)
        await update.message.reply_text(
            f"✅ *Tanggal pajak tersimpan!*\n\n"
            f"Jatuh tempo: {pajak_info['date_text']}\n"
            f"Sisa waktu: {pajak_info['remaining_text']}",
            parse_mode='Markdown',
            reply_markup=reply_markup
        )
        return ConversationHandler.END
    except Exception as e:
        logger.error(f"Error in pajak_date_received: {e}")
        await update.message.reply_text(
            "❌ Format tidak valid.\n\n"
            "Gunakan format: DD-MM\n"
            "Contoh: 25-07"
        )
        return WAITING_PAJAK_DATE

# ============== BENSIN HANDLERS ==============

async def menu_bensin_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk menu BENSIN"""
    query = update.callback_query
    await query.answer()
    user = context.user_data.get('selected_user', 'IRFAN')
    data = load_data()
    
    # Ensure bensin structure exists
    if 'bensin' not in data[user]:
        data[user]['bensin'] = {
            "fuel_prices": DEFAULT_FUEL_PRICES.copy(),
            "purchases": []
        }
        save_data(data)
    
    bensin_data = data[user]['bensin']
    pertalite = bensin_data['fuel_prices'].get('pertalite', 10000)
    pertamax = bensin_data['fuel_prices'].get('pertamax', 12750)
    
    keyboard = [
        [InlineKeyboardButton("⛽ Beli Bensin", callback_data='bensin_BUY')],
        [InlineKeyboardButton("📊 Cek Konsumsi", callback_data='bensin_CHECK')],
        [InlineKeyboardButton("📜 Riwayat Pembelian", callback_data='bensin_HISTORY')],
        [InlineKeyboardButton("💰 Setting Harga", callback_data='bensin_PRICE')],
        [InlineKeyboardButton("🔙 Kembali", callback_data='back_to_menu')]
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)
    text = (
        "*⛽ MENU BENSIN*\n\n"
        f"Harga saat ini:\n"
        f"• Pertalite: Rp {pertalite:,}/liter\n"
        f"• Pertamax: Rp {pertamax:,}/liter\n\n"
        "Pilih menu:"
    )
    await query.edit_message_text(text, parse_mode='Markdown', reply_markup=reply_markup)

async def bensin_buy_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk beli bensin"""
    query = update.callback_query
    await query.answer()
    keyboard = [
        [InlineKeyboardButton("⛽ Pertalite", callback_data='fuel_type_PERTALITE')],
        [InlineKeyboardButton("⛽ Pertamax", callback_data='fuel_type_PERTAMAX')],
        [InlineKeyboardButton("🔙 Batal", callback_data='menu_BENSIN')]
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)
    await query.edit_message_text(
        "*Beli Bensin*\n\n"
        "Pilih jenis bensin:",
        parse_mode='Markdown',
        reply_markup=reply_markup
    )

async def fuel_type_selected(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler ketika pilih jenis bensin"""
    query = update.callback_query
    await query.answer()
    fuel_type = query.data.split('_')[2]
    context.user_data['fuel_type'] = fuel_type
    user = context.user_data.get('selected_user', 'IRFAN')
    data = load_data()
    fuel_name = "Pertalite" if fuel_type == 'PERTALITE' else "Pertamax"
    price_per_liter = data[user]['bensin']['fuel_prices'][fuel_type.lower()]
    await query.edit_message_text(
        f"*Beli: {fuel_name}*\n\n"
        f"Harga: Rp {price_per_liter:,}/liter\n\n"
        "Masukkan nominal uang yang dibelanjakan (Rupiah):\n"
        "Contoh: 50000",
        parse_mode='Markdown'
    )
    return WAITING_FUEL_AMOUNT

async def fuel_amount_received(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler ketika user input nominal bensin"""
    try:
        amount = int(update.message.text.replace(',', '').replace('.', ''))
        user = context.user_data.get('selected_user', 'IRFAN')
        fuel_type = context.user_data.get('fuel_type', 'PERTALITE')
        data = load_data()
        price_per_liter = data[user]['bensin']['fuel_prices'][fuel_type.lower()]
        
        # Hitung liter
        liters = amount / price_per_liter
        context.user_data['fuel_amount'] = amount
        context.user_data['fuel_liters'] = liters
        fuel_name = "Pertalite" if fuel_type == 'PERTALITE' else "Pertamax"
        
        await update.message.reply_text(
            f"*Pembelian {fuel_name}*\n\n"
            f"Nominal: Rp {amount:,}\n"
            f"Mendapat: {liters:.2f} liter\n\n"
            "Masukkan km spedometer saat ini:",
            parse_mode='Markdown'
        )
        return WAITING_FUEL_KM
    except ValueError:
        await update.message.reply_text(
            "❌ Input tidak valid. Masukkan angka saja.\n\n"
            "Contoh: 50000"
        )
        return WAITING_FUEL_AMOUNT

async def fuel_km_received(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler ketika user input km saat beli bensin"""
    try:
        km = int(update.message.text.replace(',', '').replace('.', ''))
        context.user_data['fuel_km'] = km
        user = context.user_data.get('selected_user', 'IRFAN')
        data = load_data()
        motor = data[user]['motor']
        schedule = MAINTENANCE_SCHEDULE[motor]
        bar_penuh = schedule['bar_penuh']
        
        keyboard = []
        # Buat tombol untuk setiap bar
        for i in range(bar_penuh, 0, -1):
            keyboard.append([InlineKeyboardButton(f"{i} Bar", callback_data=f'fuel_bar_{i}')])
        keyboard.append([InlineKeyboardButton("0.5 Bar (Berkedip)", callback_data='fuel_bar_0.5')])
        keyboard.append([InlineKeyboardButton("🔙 Batal", callback_data='menu_BENSIN')])
        
        reply_markup = InlineKeyboardMarkup(keyboard)
        await update.message.reply_text(
            f"*Km saat beli: {km:,} km*\n\n"
            "Berapa bar bensin SEBELUM diisi?\n\n"
            "(Pilih sisa bar sebelum ngisi bensin)",
            parse_mode='Markdown',
            reply_markup=reply_markup
        )
        return ConversationHandler.END
    except ValueError:
        await update.message.reply_text(
            "❌ Input tidak valid. Masukkan angka saja.\n\n"
            "Contoh: 15000"
        )
        return WAITING_FUEL_KM

async def fuel_bar_selected(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler ketika user pilih bar bensin"""
    query = update.callback_query
    await query.answer()
    bar_before = float(query.data.split('_')[2])
    user = context.user_data.get('selected_user', 'IRFAN')
    fuel_type = context.user_data.get('fuel_type', 'PERTALITE')
    amount = context.user_data.get('fuel_amount', 0)
    liters = context.user_data.get('fuel_liters', 0)
    km = context.user_data.get('fuel_km', 0)
    data = load_data()
    motor = data[user]['motor']
    schedule = MAINTENANCE_SCHEDULE[motor]
    liter_per_bar = schedule['liter_per_bar']
    
    # Estimasi bar setelah diisi
    bar_added = liters / liter_per_bar
    bar_after = min(bar_before + bar_added, schedule['bar_penuh'])
    today = datetime.now().strftime("%d-%m-%Y")
    fuel_name = "Pertalite" if fuel_type == 'PERTALITE' else "Pertamax"
    
    purchase_record = {
        'date': today,
        'km': km,
        'fuel_type': fuel_type.lower(),
        'amount': amount,
        'liters': round(liters, 2),
        'bar_before': bar_before,
        'bar_after': round(bar_after, 1)
    }
    data[user]['bensin']['purchases'].append(purchase_record)
    save_data(data)
    
    keyboard = [[InlineKeyboardButton("🔙 Kembali", callback_data='menu_BENSIN')]]
    reply_markup = InlineKeyboardMarkup(keyboard)
    await query.edit_message_text(
        f"✅ *Pembelian Bensin Tersimpan!*\n\n"
        f"Tanggal: {today}\n"
        f"Km: {km:,} km\n"
        f"Jenis: {fuel_name}\n"
        f"Nominal: Rp {amount:,}\n"
        f"Mendapat: {liters:.2f} liter\n\n"
        f"📊 *Indikator Bensin:*\n"
        f"Sebelum: {bar_before} bar\n"
        f"Setelah: ±{bar_after:.1f} bar\n"
        f"(Estimasi naik ±{bar_added:.1f} bar)",
        parse_mode='Markdown',
        reply_markup=reply_markup
    )

async def bensin_check_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk cek konsumsi bensin"""
    query = update.callback_query
    await query.answer()
    user = context.user_data.get('selected_user', 'IRFAN')
    data = load_data()
    purchases = data[user]['bensin']['purchases']
    
    if not purchases:
        keyboard = [[InlineKeyboardButton("🔙 Kembali", callback_data='menu_BENSIN')]]
        reply_markup = InlineKeyboardMarkup(keyboard)
        await query.edit_message_text(
            "❌ Belum ada data pembelian bensin.\n\n"
            "Silakan beli bensin terlebih dahulu.",
            reply_markup=reply_markup
        )
        return ConversationHandler.END
    
    await query.edit_message_text(
        "*📊 Cek Konsumsi Bensin*\n\n"
        "Masukkan km spedometer saat ini:",
        parse_mode='Markdown'
    )
    return WAITING_CHECK_FUEL_KM

async def check_fuel_km_received(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler ketika user input km untuk cek konsumsi"""
    try:
        current_km = int(update.message.text.replace(',', '').replace('.', ''))
        context.user_data['check_fuel_km'] = current_km
        user = context.user_data.get('selected_user', 'IRFAN')
        data = load_data()
        motor = data[user]['motor']
        schedule = MAINTENANCE_SCHEDULE[motor]
        bar_penuh = schedule['bar_penuh']
        
        keyboard = []
        for i in range(bar_penuh, 0, -1):
            keyboard.append([InlineKeyboardButton(f"{i} Bar", callback_data=f'check_bar_{i}')])
        keyboard.append([InlineKeyboardButton("0.5 Bar (Berkedip)", callback_data='check_bar_0.5')])
        keyboard.append([InlineKeyboardButton("🔙 Batal", callback_data='menu_BENSIN')])
        
        reply_markup = InlineKeyboardMarkup(keyboard)
        await update.message.reply_text(
            f"*Km saat ini: {current_km:,} km*\n\n"
            "Berapa bar bensin yang tersisa sekarang?",
            parse_mode='Markdown',
            reply_markup=reply_markup
        )
        return ConversationHandler.END
    except ValueError:
        await update.message.reply_text(
            "❌ Input tidak valid. Masukkan angka saja.\n\n"
            "Contoh: 15500"
        )
        return WAITING_CHECK_FUEL_KM

async def check_bar_selected(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler ketika user pilih bar saat cek konsumsi"""
    query = update.callback_query
    await query.answer()
    current_bar = float(query.data.split('_')[2])
    current_km = context.user_data.get('check_fuel_km', 0)
    user = context.user_data.get('selected_user', 'IRFAN')
    data = load_data()
    motor = data[user]['motor']
    schedule = MAINTENANCE_SCHEDULE[motor]
    liter_per_bar = schedule['liter_per_bar']
    
    # Ambil pembelian terakhir
    purchases = data[user]['bensin']['purchases']
    last_purchase = purchases[-1]
    
    # Hitung jarak tempuh
    distance = current_km - last_purchase['km']
    liters_used = last_purchase['liters'] - (current_bar * liter_per_bar)
    
    # Hitung km/liter
    if liters_used > 0:
        km_per_liter = distance / liters_used
    else:
        km_per_liter = 0
    
    # Estimasi jarak yang bisa ditempuh dengan sisa bensin
    remaining_liters = current_bar * liter_per_bar
    estimated_range = remaining_liters * km_per_liter if km_per_liter > 0 else 0
    
    fuel_name = "Pertalite" if last_purchase['fuel_type'] == 'pertalite' else "Pertamax"
    
    keyboard = [[InlineKeyboardButton("🔙 Kembali", callback_data='menu_BENSIN')]]
    reply_markup = InlineKeyboardMarkup(keyboard)
    
    message = (
        f"*📊 ANALISA KONSUMSI BENSIN*\n\n"
        f"🏍️ Motor: {motor}\n\n"
        f"📅 *Pembelian Terakhir:*\n"
        f"Tanggal: {last_purchase['date']}\n"
        f"Km: {last_purchase['km']:,} km\n"
        f"Jenis: {fuel_name}\n"
        f"Isi: {last_purchase['liters']:.2f} liter\n"
        f"Nominal: Rp {last_purchase['amount']:,}\n\n"
        f"📍 *Kondisi Sekarang:*\n"
        f"Km: {current_km:,} km\n"
        f"Sisa bar: {current_bar} bar\n"
        f"Sisa bensin: ±{remaining_liters:.2f} liter\n\n"
        f"📏 *Perhitungan:*\n"
        f"Jarak tempuh: {distance:,} km\n"
    )
    
    if km_per_liter > 0:
        message += (
            f"Bensin terpakai: ±{liters_used:.2f} liter\n"
            f"Konsumsi: *{km_per_liter:.1f} km/liter*\n\n"
            f"🎯 *Estimasi:*\n"
            f"Dengan sisa {current_bar} bar (±{remaining_liters:.2f}L),\n"
            f"bisa tempuh ±{estimated_range:.0f} km lagi\n\n"
        )
        if current_bar <= 1:
            message += "⚠️ *Bensin hampir habis!* Segera isi."
        elif current_bar <= 2:
            message += "⚠️ Bensin sudah mulai menipis."
    else:
        message += "❌ Tidak bisa menghitung konsumsi.\n(Data tidak valid)"
    
    await query.edit_message_text(
        message,
        parse_mode='Markdown',
        reply_markup=reply_markup
    )

async def bensin_history_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk riwayat pembelian bensin"""
    query = update.callback_query
    await query.answer()
    user = context.user_data.get('selected_user', 'IRFAN')
    data = load_data()
    purchases = data[user]['bensin']['purchases']
    
    if not purchases:
        message = "❌ Belum ada riwayat pembelian bensin."
    else:
        message = "*📜 RIWAYAT PEMBELIAN BENSIN*\n\n"
        # Tampilkan 5 terakhir
        for i, purchase in enumerate(reversed(purchases[-5:]), 1):
            fuel_name = "Pertalite" if purchase['fuel_type'] == 'pertalite' else "Pertamax"
            message += (
                f"{i}. {purchase['date']}\n"
                f"   {fuel_name} - Rp {purchase['amount']:,}\n"
                f"   {purchase['liters']:.2f}L @ {purchase['km']:,} km\n"
                f"   Bar: {purchase['bar_before']} → {purchase['bar_after']}\n\n"
            )
        if len(purchases) > 5:
            message += f"_(Menampilkan 5 terakhir dari {len(purchases)} pembelian)_"
    
    keyboard = [[InlineKeyboardButton("🔙 Kembali", callback_data='menu_BENSIN')]]
    reply_markup = InlineKeyboardMarkup(keyboard)
    await query.edit_message_text(
        message,
        parse_mode='Markdown',
        reply_markup=reply_markup
    )

async def bensin_price_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk setting harga bensin"""
    query = update.callback_query
    await query.answer()
    user = context.user_data.get('selected_user', 'IRFAN')
    data = load_data()
    pertalite = data[user]['bensin']['fuel_prices']['pertalite']
    pertamax = data[user]['bensin']['fuel_prices']['pertamax']
    
    keyboard = [
        [InlineKeyboardButton(f"⛽ Pertalite (Rp {pertalite:,})", callback_data='price_PERTALITE')],
        [InlineKeyboardButton(f"⛽ Pertamax (Rp {pertamax:,})", callback_data='price_PERTAMAX')],
        [InlineKeyboardButton("🔙 Kembali", callback_data='menu_BENSIN')]
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)
    await query.edit_message_text(
        "*💰 Setting Harga Bensin*\n\n"
        "Pilih jenis bensin yang ingin diubah harganya:",
        parse_mode='Markdown',
        reply_markup=reply_markup
    )

async def price_fuel_selected(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler ketika pilih bensin untuk ubah harga"""
    query = update.callback_query
    await query.answer()
    fuel_type = query.data.split('_')[1]
    context.user_data['price_fuel_type'] = fuel_type
    fuel_name = "Pertalite" if fuel_type == 'PERTALITE' else "Pertamax"
    await query.edit_message_text(
        f"*Ubah Harga {fuel_name}*\n\n"
        "Masukkan harga baru per liter (Rupiah):\n"
        "Contoh: 10000",
        parse_mode='Markdown'
    )
    if fuel_type == 'PERTALITE':
        return WAITING_FUEL_PRICE_PERTALITE
    else:
        return WAITING_FUEL_PRICE_PERTAMAX

async def fuel_price_received(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler ketika user input harga bensin baru"""
    try:
        new_price = int(update.message.text.replace(',', '').replace('.', ''))
        user = context.user_data.get('selected_user', 'IRFAN')
        fuel_type = context.user_data.get('price_fuel_type', 'PERTALITE')
        data = load_data()
        data[user]['bensin']['fuel_prices'][fuel_type.lower()] = new_price
        save_data(data)
        fuel_name = "Pertalite" if fuel_type == 'PERTALITE' else "Pertamax"
        keyboard = [[InlineKeyboardButton("🔙 Kembali", callback_data='menu_BENSIN')]]
        reply_markup = InlineKeyboardMarkup(keyboard)
        await update.message.reply_text(
            f"✅ *Harga {fuel_name} diupdate!*\n\n"
            f"Harga baru: Rp {new_price:,}/liter",
            parse_mode='Markdown',
            reply_markup=reply_markup
        )
        return ConversationHandler.END
    except ValueError:
        await update.message.reply_text(
            "❌ Input tidak valid. Masukkan angka saja.\n\n"
            "Contoh: 10000"
        )
        fuel_type = context.user_data.get('price_fuel_type', 'PERTALITE')
        if fuel_type == 'PERTALITE':
            return WAITING_FUEL_PRICE_PERTALITE
        else:
            return WAITING_FUEL_PRICE_PERTAMAX

# ============== MENU NAVIGATION ==============

async def back_to_start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk tombol kembali ke menu awal"""
    query = update.callback_query
    await query.answer()
    keyboard = [
        [InlineKeyboardButton("🏍️ IRFAN (PCX)", callback_data='user_IRFAN')],
        [InlineKeyboardButton("🛵 ANITA (BEAT)", callback_data='user_ANITA')]
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)
    await query.edit_message_text(
        "🔧 *Bot Perawatan Motor*\n\n"
        "Pilih motor:",
        parse_mode='Markdown',
        reply_markup=reply_markup
    )

async def back_to_menu(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk kembali ke menu utama motor"""
    query = update.callback_query
    await query.answer()
    user = context.user_data.get('selected_user', 'IRFAN')
    data = load_data()
    motor = data[user]['motor']
    await show_main_menu(query, user, motor)

# ============== CANCEL HANDLER ==============

async def cancel(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Cancel conversation"""
    user = context.user_data.get('selected_user', 'IRFAN')
    keyboard = [[InlineKeyboardButton("🔙 Kembali ke Menu", callback_data=f'user_{user}')]]
    reply_markup = InlineKeyboardMarkup(keyboard)
    await update.message.reply_text(
        "Operasi dibatalkan.",
        reply_markup=reply_markup
    )
    return ConversationHandler.END

# ============== MAIN ==============

def main():
    """Main function"""
    # Ganti dengan token bot Anda
    TOKEN = "8375794847:AAG50hbBzBEQInd0zRL06DGJHSDlu9HoVfc"
    
    logger.info("="*50)
    logger.info("Motor Maintenance Bot Starting...")
    logger.info(f"Python version: {sys.version}")
    logger.info(f"Working directory: {os.getcwd()}")
    logger.info(f"Script location: {SCRIPT_DIR}")
    logger.info(f"Data file: {DATA_FILE}")
    logger.info(f"Log file: {LOG_FILE}")
    logger.info("="*50)
    
    # Buat aplikasi
    application = Application.builder().token(TOKEN).build()
    
    # Conversation handler untuk initial km
    initial_km_conv = ConversationHandler(
        entry_points=[CallbackQueryHandler(user_selected, pattern='^user_')],
        states={
            WAITING_INITIAL_KM: [MessageHandler(filters.TEXT & ~filters.COMMAND, initial_km_received)],
        },
        fallbacks=[CommandHandler('cancel', cancel)],
        allow_reentry=True,
        per_message=False
    )
    
    # Conversation handler untuk cek status (OLI/REM/VBELT)
    check_conv = ConversationHandler(
        entry_points=[
            CallbackQueryHandler(oli_check_handler, pattern='^oli_CHECK$'),
            CallbackQueryHandler(rem_check_handler, pattern='^rem_CHECK$'),
            CallbackQueryHandler(vbelt_check_handler, pattern='^vbelt_CHECK$'),
        ],
        states={
            WAITING_KM: [MessageHandler(filters.TEXT & ~filters.COMMAND, km_received)],
        },
        fallbacks=[CommandHandler('cancel', cancel)],
        allow_reentry=True,
        per_message=False
    )
    
    # Conversation handler untuk pembelian OLI
    oli_buy_conv = ConversationHandler(
        entry_points=[
            CallbackQueryHandler(oli_buy_handler, pattern='^oli_BUY$'),
            CallbackQueryHandler(oli_type_selected, pattern='^oli_type_'),
        ],
        states={
            WAITING_KM: [MessageHandler(filters.TEXT & ~filters.COMMAND, km_received)],
            WAITING_PRICE: [MessageHandler(filters.TEXT & ~filters.COMMAND, price_received)],
        },
        fallbacks=[CommandHandler('cancel', cancel)],
        allow_reentry=True,
        per_message=False
    )
    
    # Conversation handler untuk pembelian REM/VBELT
    purchase_conv = ConversationHandler(
        entry_points=[
            CallbackQueryHandler(rem_buy_handler, pattern='^rem_BUY$'),
            CallbackQueryHandler(vbelt_buy_handler, pattern='^vbelt_BUY$'),
            CallbackQueryHandler(rem_type_selected, pattern='^rem_type_'),
        ],
        states={
            WAITING_KM_PURCHASE: [MessageHandler(filters.TEXT & ~filters.COMMAND, km_purchase_received)],
            WAITING_PRICE: [MessageHandler(filters.TEXT & ~filters.COMMAND, price_received)],
        },
        fallbacks=[CommandHandler('cancel', cancel)],
        allow_reentry=True,
        per_message=False
    )
    
    # Conversation handler untuk PAJAK
    pajak_conv = ConversationHandler(
        entry_points=[
            CallbackQueryHandler(menu_pajak, pattern='^menu_PAJAK$'),
            CallbackQueryHandler(pajak_pay_handler, pattern='^pajak_PAY$'),
            CallbackQueryHandler(pajak_edit, pattern='^pajak_EDIT$'),
        ],
        states={
            WAITING_PAJAK_DATE: [MessageHandler(filters.TEXT & ~filters.COMMAND, pajak_date_received)],
            WAITING_PAJAK_NOMINAL: [MessageHandler(filters.TEXT & ~filters.COMMAND, pajak_nominal_received)],
        },
        fallbacks=[CommandHandler('cancel', cancel)],
        allow_reentry=True,
        per_message=False
    )
    
    # Conversation handler untuk BENSIN - Beli
    bensin_buy_conv = ConversationHandler(
        entry_points=[
            CallbackQueryHandler(bensin_buy_handler, pattern='^bensin_BUY$'),
            CallbackQueryHandler(fuel_type_selected, pattern='^fuel_type_'),
        ],
        states={
            WAITING_FUEL_AMOUNT: [MessageHandler(filters.TEXT & ~filters.COMMAND, fuel_amount_received)],
            WAITING_FUEL_KM: [MessageHandler(filters.TEXT & ~filters.COMMAND, fuel_km_received)],
        },
        fallbacks=[CommandHandler('cancel', cancel)],
        allow_reentry=True,
        per_message=False
    )
    
    # Conversation handler untuk BENSIN - Cek Konsumsi
    bensin_check_conv = ConversationHandler(
        entry_points=[
            CallbackQueryHandler(bensin_check_handler, pattern='^bensin_CHECK$'),
        ],
        states={
            WAITING_CHECK_FUEL_KM: [MessageHandler(filters.TEXT & ~filters.COMMAND, check_fuel_km_received)],
        },
        fallbacks=[CommandHandler('cancel', cancel)],
        allow_reentry=True,
        per_message=False
    )
    
    # Conversation handler untuk BENSIN - Setting Harga
    bensin_price_conv = ConversationHandler(
        entry_points=[
            CallbackQueryHandler(bensin_price_handler, pattern='^bensin_PRICE$'),
            CallbackQueryHandler(price_fuel_selected, pattern='^price_(PERTALITE|PERTAMAX)$'),
        ],
        states={
            WAITING_FUEL_PRICE_PERTALITE: [MessageHandler(filters.TEXT & ~filters.COMMAND, fuel_price_received)],
            WAITING_FUEL_PRICE_PERTAMAX: [MessageHandler(filters.TEXT & ~filters.COMMAND, fuel_price_received)],
        },
        fallbacks=[CommandHandler('cancel', cancel)],
        allow_reentry=True,
        per_message=False
    )
    
    # Register handlers
    application.add_handler(CommandHandler("start", start))
    application.add_handler(initial_km_conv)
    application.add_handler(check_conv)
    application.add_handler(oli_buy_conv)
    application.add_handler(purchase_conv)
    application.add_handler(pajak_conv)
    application.add_handler(bensin_buy_conv)
    application.add_handler(bensin_check_conv)
    application.add_handler(bensin_price_conv)
    
    # Menu handlers
    application.add_handler(CallbackQueryHandler(menu_oli_handler, pattern='^menu_OLI$'))
    application.add_handler(CallbackQueryHandler(menu_rem_handler, pattern='^menu_REM$'))
    application.add_handler(CallbackQueryHandler(menu_vbelt_handler, pattern='^menu_VBELT$'))
    application.add_handler(CallbackQueryHandler(menu_bensin_handler, pattern='^menu_BENSIN$'))
    application.add_handler(CallbackQueryHandler(menu_pajak, pattern='^menu_PAJAK$'))
    
    # Bensin handlers
    application.add_handler(CallbackQueryHandler(bensin_buy_handler, pattern='^bensin_BUY$'))
    application.add_handler(CallbackQueryHandler(bensin_check_handler, pattern='^bensin_CHECK$'))
    application.add_handler(CallbackQueryHandler(bensin_history_handler, pattern='^bensin_HISTORY$'))
    application.add_handler(CallbackQueryHandler(bensin_price_handler, pattern='^bensin_PRICE$'))
    application.add_handler(CallbackQueryHandler(fuel_bar_selected, pattern='^fuel_bar_'))
    application.add_handler(CallbackQueryHandler(check_bar_selected, pattern='^check_bar_'))
    
    # Other handlers
    application.add_handler(CallbackQueryHandler(show_status, pattern='^menu_STATUS$'))
    application.add_handler(CallbackQueryHandler(back_to_start, pattern='^back_to_start$'))
    application.add_handler(CallbackQueryHandler(back_to_menu, pattern='^back_to_menu$'))
    
    # Start bot
    logger.info("🤖 Bot started...")
    application.run_polling(allowed_updates=Update.ALL_TYPES)

if __name__ == '__main__':
    main()