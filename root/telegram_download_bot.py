#!/usr/bin/env python3
"""
Bot Telegram untuk download file dengan aria2
Versi Enhanced dengan Queue System & Auto-retry
"""

import os
import asyncio
import aiohttp
import subprocess
import json
import re
from pathlib import Path
from datetime import datetime
from collections import deque
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, ReplyKeyboardMarkup, KeyboardButton
from telegram.ext import (
    Application,
    CommandHandler,
    MessageHandler,
    CallbackQueryHandler,
    ContextTypes,
    filters,
    ConversationHandler,
)

# Konfigurasi
TELEGRAM_BOT_TOKEN = "8213688071:AAEogqCAr52QLG6g8PYal9hI12D2Xo9as4s"
BASE_DOWNLOAD_PATH = "/mnt/sdb1"
ARIA2_RPC_URL = "http://localhost:6800/jsonrpc"
ARIA2_RPC_SECRET = ""

# Queue Configuration
MAX_CONCURRENT_DOWNLOADS = 2
MAX_RETRY_ATTEMPTS = 3

# States untuk conversation
WAITING_FOLDER, WAITING_FILENAME, WAITING_CONFIRMATION = range(3)

# Dictionary untuk menyimpan data sementara user
user_data = {}

# Dictionary untuk menyimpan status download yang sedang berjalan
active_downloads = {}

# Queue system
download_queue = deque()
active_download_count = 0
queue_lock = asyncio.Lock()


def get_main_keyboard():
    """Buat keyboard menu utama"""
    keyboard = [
        [KeyboardButton("📊 Status Download"), KeyboardButton("📁 Lihat Folder")],
        [KeyboardButton("📋 Lihat Antrian"), KeyboardButton("🔄 Refresh Status")],
        [KeyboardButton("ℹ️ Help")]
    ]
    return ReplyKeyboardMarkup(keyboard, resize_keyboard=True)


def categorize_speed(speed_bps: float) -> dict:
    """Kategorikan kecepatan download dan berikan emoji + komentar"""
    speed_mbps = speed_bps / (1024 * 1024)
    
    if speed_mbps < 0.5:
        return {
            'category': 'Sangat Lambat',
            'emoji': '🐌',
            'color': '🔴',
            'comment': 'Koneksi sangat lambat. Cek jaringan Anda.'
        }
    elif speed_mbps < 2:
        return {
            'category': 'Lambat',
            'emoji': '🚶',
            'color': '🟠',
            'comment': 'Kecepatan di bawah rata-rata.'
        }
    elif speed_mbps < 5:
        return {
            'category': 'Sedang',
            'emoji': '🚴',
            'color': '🟡',
            'comment': 'Kecepatan normal untuk file berukuran sedang.'
        }
    elif speed_mbps < 10:
        return {
            'category': 'Cepat',
            'emoji': '🚗',
            'color': '🟢',
            'comment': 'Kecepatan bagus! Download akan cepat selesai.'
        }
    else:
        return {
            'category': 'Sangat Cepat',
            'emoji': '🚀',
            'color': '🔵',
            'comment': 'Kecepatan luar biasa! Koneksi premium.'
        }


def calculate_eta(remaining_bytes: int, speed_bps: float) -> str:
    """Hitung estimasi waktu selesai"""
    if speed_bps <= 0:
        return "Menghitung..."
    
    eta_seconds = remaining_bytes / speed_bps
    
    if eta_seconds < 60:
        return f"~{int(eta_seconds)} detik"
    elif eta_seconds < 3600:
        minutes = int(eta_seconds / 60)
        seconds = int(eta_seconds % 60)
        return f"~{minutes}m {seconds}s"
    else:
        hours = int(eta_seconds / 3600)
        minutes = int((eta_seconds % 3600) / 60)
        return f"~{hours}h {minutes}m"


def sanitize_filename(filename: str) -> str:
    """Bersihkan nama file dari karakter yang tidak valid"""
    # Hapus karakter yang tidak diperbolehkan
    filename = re.sub(r'[<>:"/\\|?*]', '_', filename)
    filename = filename.strip()
    # Ganti multiple spaces dengan single space
    filename = re.sub(r'\s+', ' ', filename)
    # Hilangkan underscore yang tidak perlu
    filename = filename.replace('_ ', ' ').replace(' _', ' ')
    return filename


def get_filename_from_url(url: str) -> str:
    """Ekstrak nama file dari URL"""
    from urllib.parse import urlparse, unquote
    parsed = urlparse(url)
    path = unquote(parsed.path)
    filename = os.path.basename(path)
    
    if not filename or '.' not in filename:
        filename = f"download_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
    
    return sanitize_filename(filename)


async def aria2_rpc_call(method: str, params: list = None):
    """Panggil Aria2 RPC"""
    if params is None:
        params = []
    
    if ARIA2_RPC_SECRET:
        params.insert(0, f"token:{ARIA2_RPC_SECRET}")
    
    payload = {
        "jsonrpc": "2.0",
        "method": method,
        "id": "telegram_bot",
        "params": params
    }
    
    try:
        async with aiohttp.ClientSession() as session:
            async with session.post(ARIA2_RPC_URL, json=payload, timeout=aiohttp.ClientTimeout(total=10)) as response:
                if response.status == 200:
                    result = await response.json()
                    return result.get('result')
                else:
                    return None
    except Exception as e:
        print(f"Aria2 RPC Error: {e}")
        return None


async def check_aria2_connection():
    """Cek koneksi ke aria2"""
    version = await aria2_rpc_call("aria2.getVersion")
    return version is not None


async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk command /start"""
    aria2_status = "✅ Connected" if await check_aria2_connection() else "❌ Not Connected"
    
    await update.message.reply_text(
        "🤖 *Selamat datang di Bot Download Manager!*\n\n"
        "📥 Kirim link untuk download file\n"
        "📊 Gunakan menu di bawah untuk navigasi\n\n"
        "━━━━━━━━━━━━━━━━━━━━━━━\n"
        "*Fitur Utama:*\n"
        "✅ Download dengan Aria2 engine\n"
        "✅ Queue system (Max 2 concurrent)\n"
        "✅ Auto-retry 3x on error\n"
        "✅ Pause/Resume/Stop control\n"
        "✅ Progress tracking real-time\n"
        "✅ Speed monitoring & ETA\n"
        "✅ Notifikasi download selesai\n"
        "✅ Auto-resume pada error\n"
        "━━━━━━━━━━━━━━━━━━━━━━━\n\n"
        f"🔌 Aria2 Status: {aria2_status}\n"
        f"📦 Max Concurrent: {MAX_CONCURRENT_DOWNLOADS}\n"
        f"🔄 Max Retry: {MAX_RETRY_ATTEMPTS}x",
        parse_mode="Markdown",
        reply_markup=get_main_keyboard()
    )


async def help_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk command /help"""
    await update.message.reply_text(
        "📖 *PANDUAN PENGGUNAAN*\n\n"
        "━━━━━━━━━━━━━━━━━━━━━━━\n"
        "*🎯 Cara Download:*\n\n"
        "1️⃣ Kirim URL file yang ingin didownload\n"
        "2️⃣ Pilih folder dari inline keyboard:\n"
        "   • media/movies\n"
        "   • media/tvshows\n"
        "   • media/drakor\n"
        "3️⃣ Bot akan menampilkan nama file default\n"
        "4️⃣ Pilih: Gunakan nama default atau ubah nama\n"
        "5️⃣ Klik tombol *✅ Iya* untuk konfirmasi\n"
        "6️⃣ Download dimulai otomatis!\n\n"
        "━━━━━━━━━━━━━━━━━━━━━━━\n"
        "*🎛 Control Download:*\n\n"
        "⏸ *Pause* - Jeda download sementara\n"
        "▶️ *Resume* - Lanjutkan download\n"
        "⏹ *Stop* - Hentikan & hapus download\n\n"
        "━━━━━━━━━━━━━━━━━━━━━━━\n"
        "*📊 Menu Keyboard:*\n\n"
        "• *Status Download* - Cek progress\n"
        "• *Lihat Antrian* - Cek queue\n"
        "• *Lihat Folder* - List folder\n"
        "• *Refresh Status* - Update progress\n\n"
        "━━━━━━━━━━━━━━━━━━━━━━━\n"
        "*💡 Sistem Queue & Retry:*\n\n"
        f"📦 Max concurrent: {MAX_CONCURRENT_DOWNLOADS} download\n"
        "📋 Download berlebih akan masuk antrian\n"
        f"🔄 Auto-retry: {MAX_RETRY_ATTEMPTS}x on error/timeout\n"
        "♻️ Auto-resume aria2 (forceResume)\n"
        "🧹 Auto-cleanup setelah selesai\n\n"
        "━━━━━━━━━━━━━━━━━━━━━━━",
        parse_mode="Markdown",
        reply_markup=get_main_keyboard()
    )


async def handle_keyboard_buttons(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk button keyboard menu"""
    text = update.message.text
    
    if text == "📊 Status Download" or text == "🔄 Refresh Status":
        await download_status(update, context)
    elif text == "📁 Lihat Folder":
        await show_folders(update, context)
    elif text == "📋 Lihat Antrian":
        await show_queue(update, context)
    elif text == "ℹ️ Help":
        await help_command(update, context)


async def show_folders(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Tampilkan folder yang tersedia"""
    try:
        base_path = Path(BASE_DOWNLOAD_PATH)
        
        if not base_path.exists():
            await update.message.reply_text(
                f"⚠️ Base path belum ada: `{BASE_DOWNLOAD_PATH}`",
                parse_mode="Markdown",
                reply_markup=get_main_keyboard()
            )
            return
        
        folders = [f for f in base_path.iterdir() if f.is_dir()]
        
        if not folders:
            await update.message.reply_text(
                "📂 *Folder tersedia:*\n\n"
                "Belum ada folder. Folder akan dibuat otomatis saat download.\n\n"
                f"📁 Base path: `{BASE_DOWNLOAD_PATH}`",
                parse_mode="Markdown",
                reply_markup=get_main_keyboard()
            )
            return
        
        folder_list = "📂 *DAFTAR FOLDER*\n\n━━━━━━━━━━━━━━━━━━━━━━━\n"
        for folder in sorted(folders):
            file_count = len([f for f in folder.iterdir() if f.is_file()])
            total_size = sum(f.stat().st_size for f in folder.rglob('*') if f.is_file())
            
            folder_list += f"\n📁 *{folder.name}*\n"
            folder_list += f"├ Path: `{folder}`\n"
            folder_list += f"├ Files: `{file_count}` file(s)\n"
            folder_list += f"└ Size: `{format_bytes(total_size)}`\n"
        
        folder_list += "\n━━━━━━━━━━━━━━━━━━━━━━━"
        
        await update.message.reply_text(
            folder_list,
            parse_mode="Markdown",
            reply_markup=get_main_keyboard()
        )
        
    except Exception as e:
        await update.message.reply_text(
            f"❌ Error: `{str(e)}`",
            parse_mode="Markdown",
            reply_markup=get_main_keyboard()
        )


async def show_queue(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Tampilkan antrian download"""
    global active_download_count
    
    user_id = update.effective_user.id
    user_active = sum(1 for d in active_downloads.values() if d['user_id'] == user_id and d['status'] == 'downloading')
    user_queued = sum(1 for q in download_queue if q['user_id'] == user_id)
    
    queue_text = "📋 *STATUS ANTRIAN DOWNLOAD*\n\n"
    queue_text += "━━━━━━━━━━━━━━━━━━━━━━━\n"
    queue_text += f"🔄 Active: {active_download_count}/{MAX_CONCURRENT_DOWNLOADS}\n"
    queue_text += f"📦 Queue: {len(download_queue)} waiting\n"
    queue_text += "━━━━━━━━━━━━━━━━━━━━━━━\n\n"
    
    queue_text += f"*Your Downloads:*\n"
    queue_text += f"▶️ Active: {user_active}\n"
    queue_text += f"⏳ Queued: {user_queued}\n\n"
    
    if download_queue:
        queue_text += "━━━━━━━━━━━━━━━━━━━━━━━\n"
        queue_text += "*Dalam Antrian:*\n\n"
        for idx, item in enumerate(list(download_queue)[:5], 1):
            queue_text += f"{idx}. `{item['filename'][:30]}...`\n"
            queue_text += f"   📁 {item['folder']}\n\n"
        
        if len(download_queue) > 5:
            queue_text += f"... dan {len(download_queue) - 5} lainnya\n"
    else:
        queue_text += "✅ Tidak ada antrian"
    
    await update.message.reply_text(
        queue_text,
        parse_mode="Markdown",
        reply_markup=get_main_keyboard()
    )


def is_valid_url(url: str) -> bool:
    """Validasi URL"""
    return url.startswith(('http://', 'https://', 'ftp://', 'magnet:'))


async def handle_url(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk URL yang dikirim user"""
    url = update.message.text.strip()
    user_id = update.effective_user.id
    
    if not is_valid_url(url):
        await update.message.reply_text(
            "❌ URL tidak valid! Pastikan dimulai dengan http://, https://, ftp://, atau magnet:",
            reply_markup=get_main_keyboard()
        )
        return ConversationHandler.END
    
    if not await check_aria2_connection():
        await update.message.reply_text(
            "❌ *Aria2 tidak terhubung!*\n\n"
            "⚠️ Pastikan Aria2 RPC sedang berjalan.\n\n"
            "Jalankan perintah:\n"
            "`aria2c --enable-rpc --rpc-listen-all`",
            parse_mode="Markdown",
            reply_markup=get_main_keyboard()
        )
        return ConversationHandler.END
    
    # Simpan URL di user_data
    user_data[user_id] = {'url': url}
    
    # Buat inline keyboard untuk pilihan folder
    keyboard = [
        [InlineKeyboardButton("🎬 media/movies", callback_data="folder_media/movies")],
        [InlineKeyboardButton("📺 media/tvshows", callback_data="folder_media/tvshows")],
        [InlineKeyboardButton("🎭 media/drakor", callback_data="folder_media/drakor")],
        [InlineKeyboardButton("❌ Batal", callback_data="folder_cancel")]
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)
    
    await update.message.reply_text(
        f"🔗 *Link Diterima!*\n\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"`{url[:100]}{'...' if len(url) > 100 else ''}`\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━\n\n"
        "📂 *Pilih folder untuk menyimpan file:*",
        parse_mode="Markdown",
        reply_markup=reply_markup
    )
    
    return WAITING_FOLDER


async def handle_folder_choice(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk pilihan folder dari inline keyboard"""
    query = update.callback_query
    await query.answer()
    
    user_id = update.effective_user.id
    
    if user_id not in user_data:
        await query.edit_message_text("❌ Sesi expired! Silakan kirim URL lagi.")
        await context.bot.send_message(
            chat_id=update.effective_chat.id,
            text="Gunakan menu di bawah untuk navigasi:",
            reply_markup=get_main_keyboard()
        )
        return ConversationHandler.END
    
    if query.data == "folder_cancel":
        await query.edit_message_text(
            "❌ *Download dibatalkan!*\n\n"
            "Silakan kirim URL lagi jika ingin mencoba lagi.",
            parse_mode="Markdown"
        )
        del user_data[user_id]
        await context.bot.send_message(
            chat_id=update.effective_chat.id,
            text="Gunakan menu di bawah untuk navigasi:",
            reply_markup=get_main_keyboard()
        )
        return ConversationHandler.END
    
    # Extract folder name dari callback data
    folder_name = query.data.replace("folder_", "")
    folder_path = os.path.join(BASE_DOWNLOAD_PATH, folder_name)
    
    # Simpan folder info
    user_data[user_id]['folder_name'] = folder_name
    user_data[user_id]['folder_path'] = folder_path
    
    # Cek apakah folder sudah ada
    folder_exists = os.path.exists(folder_path)
    status_icon = "✅" if folder_exists else "🆕"
    status_text = "Folder sudah ada" if folder_exists else "Folder akan dibuat otomatis"
    
    # Ekstrak nama file dari URL
    suggested_filename = get_filename_from_url(user_data[user_id]['url'])
    user_data[user_id]['suggested_filename'] = suggested_filename
    
    # Buat keyboard untuk nama file
    keyboard = [
        [InlineKeyboardButton("✅ Gunakan Nama Ini", callback_data="filename_default")],
        [InlineKeyboardButton("✏️ Ubah Nama File", callback_data="filename_custom")],
        [InlineKeyboardButton("❌ Batal", callback_data="filename_cancel")]
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)
    
    await query.edit_message_text(
        f"📋 *KONFIRMASI FOLDER & NAMA FILE*\n\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"📁 Folder: `{folder_name}`\n"
        f"📂 Full: `{folder_path}`\n"
        f"{status_icon} Status: {status_text}\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━\n\n"
        f"📄 *Nama File (terdeteksi):*\n"
        f"`{suggested_filename}`\n\n"
        f"❓ *Apakah Anda ingin menggunakan nama file ini?*",
        reply_markup=reply_markup,
        parse_mode="Markdown"
    )
    
    return WAITING_FILENAME


async def handle_filename_choice(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk pilihan nama file"""
    query = update.callback_query
    await query.answer()
    
    user_id = update.effective_user.id
    
    if user_id not in user_data:
        await query.edit_message_text("❌ Sesi expired! Silakan kirim URL lagi.")
        await context.bot.send_message(
            chat_id=update.effective_chat.id,
            text="Gunakan menu di bawah untuk navigasi:",
            reply_markup=get_main_keyboard()
        )
        return ConversationHandler.END
    
    if query.data == "filename_cancel":
        await query.edit_message_text(
            "❌ *Download dibatalkan!*\n\n"
            "Silakan kirim URL lagi jika ingin mencoba lagi.",
            parse_mode="Markdown"
        )
        del user_data[user_id]
        await context.bot.send_message(
            chat_id=update.effective_chat.id,
            text="Gunakan menu di bawah untuk navigasi:",
            reply_markup=get_main_keyboard()
        )
        return ConversationHandler.END
    
    if query.data == "filename_default":
        user_data[user_id]['filename'] = user_data[user_id]['suggested_filename']
        return await show_final_confirmation(query, context, user_id)
    
    elif query.data == "filename_custom":
        await query.edit_message_text(
            "✏️ *UBAH NAMA FILE*\n\n"
            "━━━━━━━━━━━━━━━━━━━━━━━\n"
            f"📝 Nama saat ini: `{user_data[user_id]['suggested_filename']}`\n"
            "━━━━━━━━━━━━━━━━━━━━━━━\n\n"
            "💬 Ketik nama file baru:\n\n"
            "✅ Contoh:\n"
            "• `My-Video.mp4`\n"
            "• `Episode-01-1080p.mkv`\n"
            "• `Document-Final.pdf`\n\n"
            "⚠️ Sertakan ekstensi file (`.mp4`, `.mkv`, dll)\n\n"
            "❌ Ketik /cancel untuk membatalkan",
            parse_mode="Markdown"
        )
        return WAITING_FILENAME


async def handle_custom_filename(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk input nama file custom"""
    user_id = update.effective_user.id
    custom_filename = update.message.text.strip()
    
    custom_filename = sanitize_filename(custom_filename)
    
    if not custom_filename:
        await update.message.reply_text(
            "❌ *Nama file tidak valid!*\n\n"
            "Silakan ketik nama file yang valid:",
            parse_mode="Markdown"
        )
        return WAITING_FILENAME
    
    user_data[user_id]['filename'] = custom_filename
    
    return await show_final_confirmation_message(update, context, user_id)


async def show_final_confirmation(query, context, user_id):
    """Tampilkan konfirmasi final (dari callback)"""
    folder_name = user_data[user_id]['folder_name']
    folder_path = user_data[user_id]['folder_path']
    filename = user_data[user_id]['filename']
    
    keyboard = [
        [
            InlineKeyboardButton("✅ Iya, Download!", callback_data="final_yes"),
            InlineKeyboardButton("❌ Batal", callback_data="final_no")
        ]
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)
    
    await query.edit_message_text(
        f"🎯 *KONFIRMASI AKHIR*\n\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"📁 Folder: `{folder_name}`\n"
        f"📄 Nama File: `{filename}`\n"
        f"📂 Path Lengkap:\n`{os.path.join(folder_path, filename)}`\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━\n\n"
        f"❓ *Lanjutkan download?*",
        reply_markup=reply_markup,
        parse_mode="Markdown"
    )
    
    return WAITING_CONFIRMATION


async def show_final_confirmation_message(update, context, user_id):
    """Tampilkan konfirmasi final (dari message)"""
    folder_name = user_data[user_id]['folder_name']
    folder_path = user_data[user_id]['folder_path']
    filename = user_data[user_id]['filename']
    
    keyboard = [
        [
            InlineKeyboardButton("✅ Iya, Download!", callback_data="final_yes"),
            InlineKeyboardButton("❌ Batal", callback_data="final_no")
        ]
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)
    
    await update.message.reply_text(
        f"🎯 *KONFIRMASI AKHIR*\n\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"📁 Folder: `{folder_name}`\n"
        f"📄 Nama File: `{filename}`\n"
        f"📂 Path Lengkap:\n`{os.path.join(folder_path, filename)}`\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━\n\n"
        f"❓ *Lanjutkan download?*",
        reply_markup=reply_markup,
        parse_mode="Markdown"
    )
    
    return WAITING_CONFIRMATION


async def handle_final_confirmation(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk konfirmasi final"""
    query = update.callback_query
    await query.answer()
    
    user_id = update.effective_user.id
    
    if user_id not in user_data:
        await query.edit_message_text("❌ Sesi expired! Silakan kirim URL lagi.")
        await context.bot.send_message(
            chat_id=update.effective_chat.id,
            text="Gunakan menu di bawah untuk navigasi:",
            reply_markup=get_main_keyboard()
        )
        return ConversationHandler.END
    
    if query.data == "final_no":
        await query.edit_message_text(
            "❌ *Download dibatalkan!*\n\n"
            "Silakan kirim URL lagi jika ingin mencoba lagi.",
            parse_mode="Markdown"
        )
        del user_data[user_id]
        await context.bot.send_message(
            chat_id=update.effective_chat.id,
            text="Gunakan menu di bawah untuk navigasi:",
            reply_markup=get_main_keyboard()
        )
        return ConversationHandler.END
    
    url = user_data[user_id]['url']
    folder_name = user_data[user_id]['folder_name']
    folder_path = user_data[user_id]['folder_path']
    filename = user_data[user_id]['filename']
    
    await query.edit_message_text(
        f"✅ *Konfirmasi Diterima!*\n\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"📦 Menambahkan ke queue...\n"
        f"📁 Folder: `{folder_name}`\n"
        f"📄 File: `{filename}`\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━",
        parse_mode="Markdown"
    )
    
    del user_data[user_id]
    
    # Tambahkan ke queue
    await add_to_queue(context.bot, update.effective_chat.id, url, folder_path, folder_name, filename, user_id)
    
    await context.bot.send_message(
        chat_id=update.effective_chat.id,
        text="🎛 Gunakan menu di bawah:",
        reply_markup=get_main_keyboard()
    )
    
    return ConversationHandler.END


async def add_to_queue(bot, chat_id, url: str, folder_path: str, folder_name: str, filename: str, user_id: int):
    """Tambahkan download ke queue"""
    global active_download_count
    
    download_info = {
        'bot': bot,
        'chat_id': chat_id,
        'url': url,
        'folder_path': folder_path,
        'folder_name': folder_name,
        'filename': filename,
        'user_id': user_id
    }
    
    async with queue_lock:
        if active_download_count < MAX_CONCURRENT_DOWNLOADS:
            # Langsung download
            active_download_count += 1
            await bot.send_message(
                chat_id=chat_id,
                text=f"▶️ *Download dimulai!*\n\n"
                     f"📄 {filename}\n"
                     f"📊 Slot: {active_download_count}/{MAX_CONCURRENT_DOWNLOADS}",
                parse_mode="Markdown"
            )
            asyncio.create_task(download_with_aria2(**download_info))
        else:
            # Masuk queue
            download_queue.append(download_info)
            position = len(download_queue)
            await bot.send_message(
                chat_id=chat_id,
                text=f"⏳ *Download ditambahkan ke antrian*\n\n"
                     f"📄 {filename}\n"
                     f"📋 Posisi: #{position}\n"
                     f"⏰ Menunggu slot tersedia...",
                parse_mode="Markdown",
                reply_markup=get_main_keyboard()
            )


async def process_queue():
    """Proses queue untuk memulai download berikutnya"""
    global active_download_count
    
    async with queue_lock:
        if download_queue and active_download_count < MAX_CONCURRENT_DOWNLOADS:
            download_info = download_queue.popleft()
            active_download_count += 1
            
            await download_info['bot'].send_message(
                chat_id=download_info['chat_id'],
                text=f"▶️ *Download dimulai dari antrian!*\n\n"
                     f"📄 {download_info['filename']}\n"
                     f"📊 Slot: {active_download_count}/{MAX_CONCURRENT_DOWNLOADS}",
                parse_mode="Markdown"
            )
            
            asyncio.create_task(download_with_aria2(**download_info))


def get_download_control_keyboard(download_id: str, status: str):
    """Buat keyboard control untuk download"""
    if status == 'downloading':
        keyboard = [
            [
                InlineKeyboardButton("⏸ Pause", callback_data=f"ctrl_pause_{download_id}"),
                InlineKeyboardButton("⏹ Stop", callback_data=f"ctrl_stop_{download_id}")
            ]
        ]
    elif status == 'paused':
        keyboard = [
            [
                InlineKeyboardButton("▶️ Resume", callback_data=f"ctrl_resume_{download_id}"),
                InlineKeyboardButton("⏹ Stop", callback_data=f"ctrl_stop_{download_id}")
            ]
        ]
    else:
        return None
    
    return InlineKeyboardMarkup(keyboard)


async def handle_download_control(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk control download (pause/resume/stop)"""
    query = update.callback_query
    await query.answer()
    
    data_parts = query.data.split('_')
    action = data_parts[1]
    download_id = '_'.join(data_parts[2:])
    
    if download_id not in active_downloads:
        await query.edit_message_text("❌ Download tidak ditemukan atau sudah selesai.")
        return
    
    download = active_downloads[download_id]
    gid = download.get('gid')
    
    if action == 'pause':
        result = await aria2_rpc_call("aria2.pause", [gid])
        if result:
            download['status'] = 'paused'
            await query.edit_message_text(
                f"⏸ *Download dijeda*\n\n"
                f"📄 {download['filename']}\n"
                f"📊 Progress: {download['progress']:.1f}%\n\n"
                f"💡 Gunakan tombol Resume untuk melanjutkan",
                parse_mode="Markdown",
                reply_markup=get_download_control_keyboard(download_id, 'paused')
            )
        else:
            await query.answer("❌ Gagal menjeda download", show_alert=True)
    
    elif action == 'resume':
        result = await aria2_rpc_call("aria2.unpause", [gid])
        if result:
            download['status'] = 'downloading'
            await query.edit_message_text(
                f"▶️ *Download dilanjutkan*\n\n"
                f"📄 {download['filename']}\n"
                f"📊 Progress: {download['progress']:.1f}%",
                parse_mode="Markdown",
                reply_markup=get_download_control_keyboard(download_id, 'downloading')
            )
        else:
            await query.answer("❌ Gagal melanjutkan download", show_alert=True)
    
    elif action == 'stop':
        result = await aria2_rpc_call("aria2.remove", [gid])
        if result:
            download['status'] = 'stopped'
            await query.edit_message_text(
                f"⏹ *Download dihentikan*\n\n"
                f"📄 {download['filename']}\n"
                f"📊 Progress: {download['progress']:.1f}%\n\n"
                f"❌ Download dibatalkan dan dihapus",
                parse_mode="Markdown"
            )
            
            # Cleanup dan proses queue
            global active_download_count
            active_download_count -= 1
            del active_downloads[download_id]
            await process_queue()
        else:
            await query.answer("❌ Gagal menghentikan download", show_alert=True)


async def download_with_aria2(bot, chat_id, url: str, folder_path: str, folder_name: str, filename: str, user_id: int):
    """Download file menggunakan Aria2 dengan retry mechanism"""
    global active_download_count
    download_id = f"{user_id}_{int(datetime.now().timestamp() * 1000)}"
    retry_count = 0
    gid = None
    
    try:
        # Buat folder jika belum ada
        Path(folder_path).mkdir(parents=True, exist_ok=True)
        
        while retry_count <= MAX_RETRY_ATTEMPTS:
            try:
                # Tambahkan download ke aria2
                options = {
                    "dir": folder_path,
                    "out": filename,
                    "max-connection-per-server": "16",
                    "split": "16",
                    "min-split-size": "1M",
                    "continue": "true",
                    "always-resume": "true",
                    "auto-file-renaming": "false",
                    "allow-overwrite": "false"
                }
                
                gid = await aria2_rpc_call("aria2.addUri", [[url], options])
                
                if not gid:
                    raise Exception("Gagal menambahkan download ke Aria2")
                
                # Simpan info download
                active_downloads[download_id] = {
                    'gid': gid,
                    'filename': filename,
                    'folder': folder_name,
                    'size': 0,
                    'downloaded': 0,
                    'progress': 0,
                    'status': 'downloading',
                    'start_time': datetime.now(),
                    'user_id': user_id,
                    'speed': 0,
                    'eta': 'Menghitung...',
                    'retry_count': retry_count,
                    'url': url,
                    'folder_path': folder_path
                }
                
                # Kirim notifikasi awal
                await bot.send_message(
                    chat_id=chat_id,
                    text=f"🚀 *Download dimulai!*\n\n"
                         f"━━━━━━━━━━━━━━━━━━━━━━━\n"
                         f"📄 File: `{filename}`\n"
                         f"📁 Folder: `{folder_name}`\n"
                         f"🔗 URL: `{url[:50]}...`\n"
                         f"━━━━━━━━━━━━━━━━━━━━━━━\n\n"
                         f"⏳ Menginisialisasi download...",
                    parse_mode="Markdown"
                )
                
                # Monitor progress
                last_update = 0
                last_message_id = None
                stalled_count = 0
                last_completed = 0
                no_status_count = 0
                
                while True:
                    await asyncio.sleep(3)
                    
                    # Get status dari aria2
                    status = await aria2_rpc_call("aria2.tellStatus", [gid])
                    
                    if not status:
                        no_status_count += 1
                        if no_status_count > 5:  # 15 detik tidak ada status
                            raise Exception("Gagal mendapatkan status dari Aria2")
                        continue
                    
                    no_status_count = 0
                    aria_status = status.get('status')
                    total_length = int(status.get('totalLength', 0))
                    completed_length = int(status.get('completedLength', 0))
                    download_speed = int(status.get('downloadSpeed', 0))
                    
                    # Deteksi stalled download
                    if completed_length == last_completed and download_speed == 0 and aria_status == 'active':
                        stalled_count += 1
                        if stalled_count > 20:  # 60 detik tidak ada progress
                            raise Exception("Download timeout (tidak ada progress)")
                    else:
                        stalled_count = 0
                    
                    last_completed = completed_length
                    
                    # Update info
                    if total_length > 0:
                        progress = (completed_length / total_length) * 100
                        remaining = total_length - completed_length
                        eta = calculate_eta(remaining, download_speed)
                        
                        active_downloads[download_id]['size'] = total_length
                        active_downloads[download_id]['downloaded'] = completed_length
                        active_downloads[download_id]['progress'] = progress
                        active_downloads[download_id]['speed'] = download_speed
                        active_downloads[download_id]['eta'] = eta
                        
                        # Update message setiap 15%
                        if progress - last_update >= 15 or (last_update == 0 and progress > 0):
                            last_update = progress
                            progress_bar = create_progress_bar(progress)
                            speed_info = categorize_speed(download_speed)
                            
                            control_keyboard = get_download_control_keyboard(download_id, 'downloading')
                            
                            try:
                                msg = await bot.send_message(
                                    chat_id=chat_id,
                                    text=f"⬇ *DOWNLOADING*\n\n"
                                         f"━━━━━━━━━━━━━━━━━━━━━━━\n"
                                         f"📄 File: `{filename[:40]}...`\n"
                                         f"📁 Folder: `{folder_name}`\n"
                                         f"📊 Total: `{format_bytes(total_length)}`\n"
                                         f"🔄 Retry: {retry_count}/{MAX_RETRY_ATTEMPTS}\n"
                                         f"━━━━━━━━━━━━━━━━━━━━━━━\n\n"
                                         f"{progress_bar}\n"
                                         f"📈 Progress: `{progress:.1f}%`\n"
                                         f"💾 Downloaded: `{format_bytes(completed_length)}`\n\n"
                                         f"⚡ Speed: `{format_bytes(download_speed)}/s`\n"
                                         f"{speed_info['color']} Status: {speed_info['emoji']} *{speed_info['category']}*\n"
                                         f"💬 {speed_info['comment']}\n\n"
                                         f"⏱ ETA: *{eta}*",
                                    parse_mode="Markdown",
                                    reply_markup=control_keyboard
                                )
                                last_message_id = msg.message_id
                            except Exception as e:
                                print(f"Error sending progress update: {e}")
                    
                    # Cek status
                    if aria_status == 'complete':
                        active_downloads[download_id]['status'] = 'completed'
                        active_downloads[download_id]['progress'] = 100
                        
                        # Hitung statistik akhir
                        elapsed_time = (datetime.now() - active_downloads[download_id]['start_time']).total_seconds()
                        avg_speed = total_length / elapsed_time if elapsed_time > 0 else 0
                        speed_info = categorize_speed(avg_speed)
                        
                        # Notifikasi selesai
                        await bot.send_message(
                            chat_id=chat_id,
                            text=f"🎉 *DOWNLOAD SELESAI!*\n\n"
                                 f"━━━━━━━━━━━━━━━━━━━━━━━\n"
                                 f"✅ Status: *Berhasil*\n"
                                 f"━━━━━━━━━━━━━━━━━━━━━━━\n\n"
                                 f"📄 *File Info:*\n"
                                 f"├ Name: `{filename}`\n"
                                 f"├ Size: `{format_bytes(total_length)}`\n"
                                 f"├ Folder: `{folder_name}`\n"
                                 f"└ Path: `{os.path.join(folder_path, filename)}`\n\n"
                                 f"📊 *Download Stats:*\n"
                                 f"├ Avg Speed: `{format_bytes(avg_speed)}/s`\n"
                                 f"├ {speed_info['color']} Rating: {speed_info['emoji']} *{speed_info['category']}*\n"
                                 f"├ Duration: `{format_time(elapsed_time)}`\n"
                                 f"├ Retries: {retry_count}/{MAX_RETRY_ATTEMPTS}\n"
                                 f"└ Comment: {speed_info['comment']}\n\n"
                                 f"━━━━━━━━━━━━━━━━━━━━━━━\n"
                                 f"💡 File tersimpan dan siap digunakan!\n"
                                 f"🚀 Powered by Aria2",
                            parse_mode="Markdown",
                            reply_markup=get_main_keyboard()
                        )
                        
                        # Cleanup dan proses queue
                        active_download_count -= 1
                        
                        # Hapus dari aria2
                        try:
                            await aria2_rpc_call("aria2.removeDownloadResult", [gid])
                        except:
                            pass
                        
                        await asyncio.sleep(300)  # Hapus setelah 5 menit
                        if download_id in active_downloads:
                            del active_downloads[download_id]
                        
                        await process_queue()
                        return
                    
                    elif aria_status == 'error':
                        error_message = status.get('errorMessage', 'Unknown error')
                        completed = int(status.get('completedLength', 0))
                        
                        print(f"Download error: {error_message}, completed: {completed}")
                        
                        # Jika ada progress, coba resume
                        if completed > 0 and retry_count < MAX_RETRY_ATTEMPTS:
                            # Coba forceResume
                            try:
                                await bot.send_message(
                                    chat_id=chat_id,
                                    text=f"⚠️ *Download Error!*\n"
                                         f"🔄 Mencoba auto-resume...",
                                    parse_mode="Markdown"
                                )
                                
                                await aria2_rpc_call("aria2.forceResume", [gid])
                                await asyncio.sleep(3)
                                
                                new_status = await aria2_rpc_call("aria2.tellStatus", [gid])
                                if new_status and new_status.get("status") == "active":
                                    await bot.send_message(
                                        chat_id=chat_id,
                                        text=f"🟢 *Auto-resume berhasil!*\n"
                                             f"Melanjutkan dari `{format_bytes(completed)}`",
                                        parse_mode="Markdown"
                                    )
                                    continue
                            except Exception as e:
                                print(f"ForceResume failed: {e}")
                        
                        # Jika forceResume gagal, throw exception untuk retry
                        raise Exception(f"Download error: {error_message}")
                    
                    elif aria_status == 'paused':
                        # Wait jika di-pause manual
                        active_downloads[download_id]['status'] = 'paused'
                        await asyncio.sleep(3)
                        continue
                    
                    elif aria_status == 'removed':
                        # Download dihentikan manual
                        raise Exception("Download dihentikan oleh user")
            
            except Exception as e:
                error_str = str(e)
                print(f"Download exception: {error_str}")
                
                retry_count += 1
                
                # Hapus download lama dari aria2
                try:
                    if gid:
                        await aria2_rpc_call("aria2.forceRemove", [gid])
                        await aria2_rpc_call("aria2.removeDownloadResult", [gid])
                except Exception as cleanup_error:
                    print(f"Cleanup error: {cleanup_error}")
                
                if retry_count <= MAX_RETRY_ATTEMPTS:
                    await bot.send_message(
                        chat_id=chat_id,
                        text=f"⚠️ *Download Error!*\n\n"
                             f"❌ Error: `{error_str[:100]}`\n"
                             f"🔄 Retry {retry_count}/{MAX_RETRY_ATTEMPTS}\n\n"
                             f"⏳ Mencoba lagi dalam 5 detik...",
                        parse_mode="Markdown"
                    )
                    
                    await asyncio.sleep(5)
                    continue
                else:
                    # Retry habis, gagal total
                    raise e
        
    except Exception as e:
        error_message = str(e)
        print(f"Download failed completely: {error_message}")
        
        if download_id in active_downloads:
            active_downloads[download_id]['status'] = 'failed'
        
        await bot.send_message(
            chat_id=chat_id,
            text=f"❌ *DOWNLOAD GAGAL!*\n\n"
                 f"━━━━━━━━━━━━━━━━━━━━━━━\n"
                 f"📄 File: `{filename[:40]}...`\n"
                 f"🔄 Retry: {retry_count}/{MAX_RETRY_ATTEMPTS}\n"
                 f"━━━━━━━━━━━━━━━━━━━━━━━\n\n"
                 f"❌ Error: `{error_message[:150]}`\n\n"
                 f"💡 Semua percobaan retry telah habis.\n"
                 f"Silakan coba download ulang.",
            parse_mode="Markdown",
            reply_markup=get_main_keyboard()
        )
        
        # Cleanup
        active_download_count -= 1
        
        # Hapus dari aria2
        try:
            if gid:
                await aria2_rpc_call("aria2.forceRemove", [gid])
                await aria2_rpc_call("aria2.removeDownloadResult", [gid])
        except:
            pass
        
        if download_id in active_downloads:
            del active_downloads[download_id]
        
        await process_queue()


async def download_status(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Tampilkan status download yang sedang berjalan"""
    user_id = update.effective_user.id
    
    user_downloads = {k: v for k, v in active_downloads.items() if v['user_id'] == user_id}
    
    if not user_downloads:
        await update.message.reply_text(
            "🔭 *TIDAK ADA DOWNLOAD AKTIF*\n\n"
            "━━━━━━━━━━━━━━━━━━━━━━━\n"
            "Belum ada download yang sedang berjalan.\n\n"
            "💡 Kirim URL untuk memulai download baru!",
            parse_mode="Markdown",
            reply_markup=get_main_keyboard()
        )
        return
    
    status_text = "📊 *STATUS DOWNLOAD AKTIF*\n\n━━━━━━━━━━━━━━━━━━━━━━━\n"
    
    for download_id, info in user_downloads.items():
        progress_bar = create_progress_bar(info['progress'])
        elapsed_time = (datetime.now() - info['start_time']).total_seconds()
        
        status_icons = {
            'downloading': '⬇',
            'completed': '✅',
            'failed': '❌',
            'paused': '⏸',
            'stopped': '⏹'
        }
        status_emoji = status_icons.get(info['status'], '❓')
        
        status_text += f"\n{status_emoji} *{info['filename'][:30]}...*\n"
        status_text += f"📁 Folder: `{info['folder']}`\n"
        
        if info['size'] > 0:
            status_text += f"📊 Size: `{format_bytes(info['size'])}`\n"
            status_text += f"{progress_bar}\n"
            status_text += f"📈 Progress: `{info['progress']:.1f}%`\n"
            status_text += f"💾 Downloaded: `{format_bytes(info['downloaded'])}`\n"
            
            if info['status'] == 'downloading':
                speed_info = categorize_speed(info.get('speed', 0))
                status_text += f"⚡ Speed: `{format_bytes(info.get('speed', 0))}/s`\n"
                status_text += f"{speed_info['color']} {speed_info['emoji']} {speed_info['category']}\n"
                status_text += f"⏱ ETA: {info.get('eta', 'Menghitung...')}\n"
            
            status_text += f"🔄 Retry: {info.get('retry_count', 0)}/{MAX_RETRY_ATTEMPTS}\n"
        
        status_text += f"⏲ Elapsed: `{format_time(elapsed_time)}`\n"
        status_text += f"Status: `{info['status']}`\n"
        status_text += "━━━━━━━━━━━━━━━━━━━━━━━\n"
    
    await update.message.reply_text(
        status_text,
        parse_mode="Markdown",
        reply_markup=get_main_keyboard()
    )


async def cancel(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Cancel conversation"""
    user_id = update.effective_user.id
    if user_id in user_data:
        del user_data[user_id]
    
    await update.message.reply_text(
        "❌ *Proses dibatalkan!*\n\n"
        "Kirim URL lagi jika ingin memulai download baru.",
        parse_mode="Markdown",
        reply_markup=get_main_keyboard()
    )
    return ConversationHandler.END


def create_progress_bar(progress: float, length: int = 20) -> str:
    """Buat progress bar visual"""
    filled = int(length * progress / 100)
    bar = '█' * filled + '░' * (length - filled)
    return f"[{bar}]"


def format_bytes(bytes_size: int) -> str:
    """Format ukuran file ke human readable"""
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if bytes_size < 1024.0:
            return f"{bytes_size:.2f} {unit}"
        bytes_size /= 1024.0
    return f"{bytes_size:.2f} PB"


def format_time(seconds: float) -> str:
    """Format waktu ke human readable"""
    if seconds < 60:
        return f"{int(seconds)}s"
    elif seconds < 3600:
        minutes = int(seconds / 60)
        secs = int(seconds % 60)
        return f"{minutes}m {secs}s"
    else:
        hours = int(seconds / 3600)
        minutes = int((seconds % 3600) / 60)
        return f"{hours}h {minutes}m"


def main():
    """Main function untuk menjalankan bot"""
    Path(BASE_DOWNLOAD_PATH).mkdir(parents=True, exist_ok=True)
    
    application = Application.builder().token(TELEGRAM_BOT_TOKEN).build()
    
    # Conversation handler untuk proses download
    conv_handler = ConversationHandler(
        entry_points=[
            MessageHandler(filters.TEXT & ~filters.COMMAND & filters.Regex(r'^(https?://|ftp://|magnet:)'), handle_url)
        ],
        states={
            WAITING_FOLDER: [
                CallbackQueryHandler(handle_folder_choice, pattern="^folder_")
            ],
            WAITING_FILENAME: [
                CallbackQueryHandler(handle_filename_choice, pattern="^filename_"),
                MessageHandler(filters.TEXT & ~filters.COMMAND, handle_custom_filename)
            ],
            WAITING_CONFIRMATION: [
                CallbackQueryHandler(handle_final_confirmation, pattern="^final_")
            ],
        },
        fallbacks=[CommandHandler("cancel", cancel)],
    )
    
    # Register handlers
    application.add_handler(CommandHandler("start", start))
    application.add_handler(CommandHandler("help", help_command))
    application.add_handler(CommandHandler("cancel", cancel))
    application.add_handler(conv_handler)
    
    # Handler untuk download control
    application.add_handler(CallbackQueryHandler(handle_download_control, pattern="^ctrl_"))
    
    # Handler untuk keyboard buttons
    application.add_handler(MessageHandler(
        filters.TEXT & ~filters.COMMAND & ~filters.Regex(r'^(https?://|ftp://|magnet:)'),
        handle_keyboard_buttons
    ))
    
    print("🤖 Bot started with enhanced queue system...")
    print(f"📁 Base download path: {BASE_DOWNLOAD_PATH}")
    print(f"🔌 Aria2 RPC URL: {ARIA2_RPC_URL}")
    print(f"📦 Max concurrent downloads: {MAX_CONCURRENT_DOWNLOADS}")
    print(f"🔄 Max retry attempts: {MAX_RETRY_ATTEMPTS}")
    application.run_polling(allowed_updates=Update.ALL_TYPES)


if __name__ == "__main__":
    main()