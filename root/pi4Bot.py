#!/usr/bin/env python3
"""
OpenWRT Telegram Monitoring Bot untuk Raspberry Pi 4
Requirements: pip install python-telegram-bot requests psutil
"""

import asyncio
import logging
import subprocess
import json
import requests
from datetime import datetime
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, ReplyKeyboardMarkup, KeyboardButton
from telegram.ext import Application, CommandHandler, CallbackQueryHandler, ContextTypes, MessageHandler, filters

# ==================== KONFIGURASI ====================
BOT_TOKEN = "8416814394:AAGNQOYEketw20NxR7nA9LtKQr5cMk3boUU"  # Ganti dengan token bot Anda
ALLOWED_USERS = [5645537022]  # Ganti dengan Telegram User ID Anda
CGI_ONLINE_PATH = "/www/cgi-bin/online"  # Path ke script CGI online

# ==================== SETUP LOGGING ====================
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO
)
logger = logging.getLogger(__name__)

# ==================== FUNGSI UTILITAS ====================

def check_auth(user_id: int) -> bool:
    """Cek apakah user diizinkan menggunakan bot"""
    return user_id in ALLOWED_USERS

def run_command(command: str) -> str:
    """Jalankan command shell dan return output"""
    try:
        result = subprocess.run(
            command,
            shell=True,
            capture_output=True,
            text=True,
            timeout=30
        )
        return result.stdout.strip() if result.returncode == 0 else f"Error: {result.stderr.strip()}"
    except subprocess.TimeoutExpired:
        return "Error: Command timeout"
    except Exception as e:
        return f"Error: {str(e)}"

# ==================== FUNGSI MONITORING ====================

def get_cpu_ram_info() -> str:
    """Dapatkan info CPU dan RAM menggunakan sysinfo.sh"""
    try:
        # Cek apakah sysinfo.sh tersedia
        sysinfo_check = run_command("which sysinfo.sh")
        
        if sysinfo_check:
            # Gunakan sysinfo.sh
            result = run_command("sysinfo.sh")
            
            # Parse output sysinfo.sh
            lines = result.split('\n')
            cpu_temp = ""
            cpu_usage = ""
            load_avg = ""
            ram_used = ""
            ram_free = ""
            
            for line in lines:
                if "CPU Temp" in line:
                    cpu_temp = line.split(':')[1].strip()
                elif "CPU Usage" in line:
                    cpu_usage = line.split(':')[1].strip()
                elif "Load Avg" in line:
                    load_avg = line.split(':')[1].strip()
                elif "RAM Used" in line:
                    ram_used = line.split(':')[1].strip()
                elif "RAM Free" in line:
                    ram_free = line.split(':')[1].strip()
            
            return (
                f"🖥 <b>CPU & RAM Status</b>\n\n"
                f"🌡 Temperature: <code>{cpu_temp}</code>\n"
                f"📊 CPU Usage: <code>{cpu_usage}</code>\n"
                f"⚡ Load Average: <code>{load_avg}</code>\n"
                f"💾 RAM Used: <code>{ram_used}</code>\n"
                f"💾 RAM Free: <code>{ram_free}</code>"
            )
        else:
            # Fallback ke method manual
            # Temperature
            temp_raw = run_command("cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null")
            temp = float(temp_raw) / 1000 if temp_raw.replace('.','').isdigit() else 0
            
            # CPU Load
            load = run_command("cat /proc/loadavg").split()[:3]
            
            # CPU Usage dengan method yang benar
            cpu_usage = run_command("top -bn1 | grep 'CPU:' | sed 's/CPU://g' | awk '{print $1}'")
            if not cpu_usage or cpu_usage == "":
                cpu_usage = "N/A"
            
            # RAM Info
            mem_info = run_command("free | grep Mem")
            mem_parts = mem_info.split()
            if len(mem_parts) >= 4:
                total = int(mem_parts[1])
                used = int(mem_parts[2])
                free = int(mem_parts[3])
                
                # Convert ke MB
                total_mb = total // 1024
                used_mb = used // 1024
                free_mb = free // 1024
                usage_pct = int((used / total) * 100) if total > 0 else 0
                
                return (
                    f"🖥 <b>CPU & RAM Status</b>\n\n"
                    f"🌡 Temperature: <code>{temp:.0f}°C</code>\n"
                    f"📊 CPU Usage: <code>{cpu_usage}%</code>\n"
                    f"⚡ Load Average: <code>{' '.join(load)}</code>\n"
                    f"💾 RAM Used: <code>{usage_pct}% ({used_mb} MB / {total_mb} MB)</code>\n"
                    f"💾 RAM Free: <code>{free_mb} MB</code>"
                )
    except Exception as e:
        return f"Error: {str(e)}"
    
    return "Error: Unable to get system info"

def get_online_users() -> str:
    """Dapatkan daftar user online dari CGI script"""
    try:
        result = subprocess.run(
            ["bash", CGI_ONLINE_PATH],
            capture_output=True,
            text=True,
            timeout=10
        )
        
        if result.returncode != 0:
            return "Error: Failed to execute online script"
        
        # Parse JSON output (skip header "Content-type")
        output_lines = result.stdout.strip().split('\n')
        json_start = next((i for i, line in enumerate(output_lines) if line.strip().startswith('[')), -1)
        
        if json_start == -1:
            return "Error: Invalid output format"
        
        json_data = '\n'.join(output_lines[json_start:])
        devices = json.loads(json_data)
        
        if not devices:
            return "👥 <b>Online Users</b>\n\nTidak ada perangkat online"
        
        status_emoji = {
            "TERHUBUNG": "🟢",
            "TERHUBUNG TIDAK AKTIF": "🟡",
            "TIDAK DIKETAHUI": "🟠",
            "TIDAK TERHUBUNG": "🔴"
        }
        
        result_text = "👥 <b>Online Users</b>\n\n"
        for idx, device in enumerate(devices, 1):
            emoji = status_emoji.get(device['status'], '⚪')
            hostname = device['hostname'] if device['hostname'] != '*' else 'Unknown'
            result_text += (
                f"{idx}. {emoji} <b>{hostname}</b>\n"
                f"   IP: <code>{device['ip']}</code>\n"
                f"   MAC: <code>{device['mac']}</code>\n"
                f"   Status: {device['status']}\n\n"
            )
        
        return result_text
        
    except Exception as e:
        return f"Error: {str(e)}"

def get_vnstat_traffic() -> str:
    """Dapatkan statistik traffic dari vnstat JSON"""
    try:
        def format_bytes(bytes_val):
            """Format bytes ke KB, MB, GB"""
            if bytes_val < 1024:
                return f"{bytes_val} B"
            elif bytes_val < 1024 * 1024:
                return f"{bytes_val / 1024:.2f} KB"
            elif bytes_val < 1024 * 1024 * 1024:
                return f"{bytes_val / (1024 * 1024):.2f} MB"
            else:
                return f"{bytes_val / (1024 * 1024 * 1024):.2f} GB"
        
        result_text = "📊 <b>Traffic Statistics (eth1)</b>\n\n"
        
        # 1. Live traffic dari CGI
        try:
            cgi_result = subprocess.run(
                ["sh", "/www/cgi-bin/traffic"],
                capture_output=True,
                text=True,
                timeout=10
            )
            
            if cgi_result.returncode == 0:
                output_lines = cgi_result.stdout.strip().split('\n')
                json_start = next((i for i, line in enumerate(output_lines) if line.strip().startswith('{')), -1)
                
                if json_start != -1:
                    json_data = '\n'.join(output_lines[json_start:])
                    traffic_data = json.loads(json_data)
                    
                    if "error" not in traffic_data:
                        rx_bytes = int(traffic_data.get('rx', 0))
                        tx_bytes = int(traffic_data.get('tx', 0))
                        
                        result_text += (
                            f"📡 <b>Live (3 detik):</b>\n"
                            f"⬇️ RX: <code>{format_bytes(rx_bytes)}</code>\n"
                            f"⬆️ TX: <code>{format_bytes(tx_bytes)}</code>\n\n"
                        )
        except:
            pass
        
        # 2. Traffic hari ini dari vnstat JSON
        try:
            today_json = run_command("vnstat --json d -i eth1")
            today_data = json.loads(today_json)
            
            if today_data and 'interfaces' in today_data:
                days = today_data['interfaces'][0]['traffic']['day']
                # Ambil data hari terakhir (hari ini)
                if days:
                    last_day = days[-1]
                    rx = last_day['rx']
                    tx = last_day['tx']
                    
                    result_text += (
                        f"📅 <b>Hari ini:</b>\n"
                        f"⬇️ RX: <code>{format_bytes(rx)}</code>\n"
                        f"⬆️ TX: <code>{format_bytes(tx)}</code>\n"
                        f"📊 Total: <code>{format_bytes(rx + tx)}</code>\n\n"
                    )
        except:
            pass
        
        # 3. Traffic bulan ini dari vnstat JSON
        try:
            month_json = run_command("vnstat --json m -i eth1")
            month_data = json.loads(month_json)
            
            if month_data and 'interfaces' in month_data:
                months = month_data['interfaces'][0]['traffic']['month']
                # Ambil data bulan terakhir (bulan ini)
                if months:
                    last_month = months[-1]
                    rx = last_month['rx']
                    tx = last_month['tx']
                    
                    result_text += (
                        f"📈 <b>Bulan ini:</b>\n"
                        f"⬇️ RX: <code>{format_bytes(rx)}</code>\n"
                        f"⬆️ TX: <code>{format_bytes(tx)}</code>\n"
                        f"📊 Total: <code>{format_bytes(rx + tx)}</code>\n\n"
                    )
        except:
            pass
        
        # 4. Top 5 hari tertinggi
        try:
            top_json = run_command("vnstat --json t -i eth1")
            top_data = json.loads(top_json)
            
            if top_data and 'interfaces' in top_data:
                top_days = top_data['interfaces'][0]['traffic']['top'][:5]
                
                if top_days:
                    result_text += "🏆 <b>Top 5 Hari Tertinggi:</b>\n"
                    for idx, day in enumerate(top_days, 1):
                        date = f"{day['date']['year']}-{day['date']['month']:02d}-{day['date']['day']:02d}"
                        total = day['rx'] + day['tx']
                        result_text += f"{idx}. <code>{date}</code>: {format_bytes(total)}\n"
        except:
            pass
        
        if result_text == "📊 <b>Traffic Statistics (eth1)</b>\n\n":
            return "Error: Unable to get traffic data"
        
        return result_text.strip()
        
    except Exception as e:
        return f"Error: {str(e)}"

def get_my_ip() -> str:
    """Dapatkan IP public"""
    try:
        # Coba beberapa service
        services = [
            "https://api.ipify.org",
            "https://ifconfig.me",
            "https://icanhazip.com"
        ]
        
        for service in services:
            try:
                response = requests.get(service, timeout=5)
                if response.status_code == 200:
                    ip = response.text.strip()
                    
                    # Dapatkan info tambahan dari ipinfo.io
                    try:
                        info = requests.get(f"https://ipinfo.io/{ip}/json", timeout=5).json()
                        return (
                            f"🌍 <b>Public IP Information</b>\n\n"
                            f"IP: <code>{ip}</code>\n"
                            f"ISP: <code>{info.get('org', 'N/A')}</code>\n"
                            f"Location: <code>{info.get('city', 'N/A')}, {info.get('region', 'N/A')}</code>\n"
                            f"Country: <code>{info.get('country', 'N/A')}</code>"
                        )
                    except:
                        return f"🌍 <b>Public IP:</b> <code>{ip}</code>"
            except:
                continue
        
        return "Error: Unable to get public IP"
    except Exception as e:
        return f"Error: {str(e)}"

def ping_test(host: str = "8.8.8.8") -> str:
    """Test ping ke host"""
    try:
        result = run_command(f"ping -c 4 {host}")
        lines = result.split('\n')
        
        # Ambil statistik
        stats = [line for line in lines if 'min/avg/max' in line or 'packet loss' in line]
        
        return (
            f"🔍 <b>Ping Test ({host})</b>\n\n"
            f"<code>{chr(10).join(stats)}</code>"
        )
    except Exception as e:
        return f"Error: {str(e)}"

def speedtest() -> str:
    """Jalankan speedtest - support multiple tools"""
    try:
        # Method 1: Ookla Speedtest (Official - RECOMMENDED)
        # Check for speedtest-ookla or ookla binary
        check_ookla = run_command("test -f /usr/bin/speedtest-ookla && echo 'OK'")
        
        if check_ookla:
            result = run_command("timeout 60 /usr/bin/speedtest-ookla --accept-license --accept-gdpr --format=human 2>&1")
            
            if "timeout" in result.lower():
                return "⚡ <b>Speedtest</b>\n\nError: Test timeout (>60 detik)"
            
            if "Error" in result and len(result) < 100:
                # Try without format option
                result = run_command("timeout 60 /usr/bin/speedtest-ookla --accept-license --accept-gdpr 2>&1")
            
            if "Error" in result or result == "":
                return f"⚡ <b>Speedtest</b>\n\nError running speedtest:\n<code>{result[:200]}</code>"
            
            # Parse output Ookla
            lines = result.split('\n')
            server = ""
            ping = ""
            download = ""
            upload = ""
            
            for line in lines:
                if "Server:" in line:
                    server = line.split("Server:")[1].strip()
                elif "Latency:" in line or "Idle Latency:" in line:
                    parts = line.split(":")
                    if len(parts) > 1:
                        ping_text = parts[-1].strip()
                        # Extract just the number
                        ping = ping_text.split()[0] if ping_text else ""
                elif "Download:" in line:
                    download = line.split("Download:")[1].strip()
                elif "Upload:" in line:
                    upload = line.split("Upload:")[1].strip()
            
            result_text = f"⚡ <b>Speedtest Results</b>\n"
            result_text += f"<i>Powered by Ookla</i>\n\n"
            
            if server:
                result_text += f"🌐 Server: <code>{server}</code>\n"
            if ping:
                result_text += f"📶 Latency: <code>{ping} ms</code>\n"
            if download:
                result_text += f"⬇️ Download: <code>{download}</code>\n"
            if upload:
                result_text += f"⬆️ Upload: <code>{upload}</code>\n"
            
            if not (server or ping or download or upload):
                # Show raw output if parsing failed
                result_text += f"\n<code>{result[:500]}</code>"
            
            return result_text
        
        # Method 2: speedtest-cli (Python-based)
        check_cli = run_command("which speedtest-cli 2>/dev/null")
        
        if check_cli:
            result = run_command("timeout 60 speedtest-cli --simple 2>&1")
            
            if "timeout" in result.lower() or result == "":
                return "⚡ <b>Speedtest</b>\n\nError: Test timeout (>60 detik)"
            
            # Check for errors
            if "Error" in result or "Cannot" in result:
                return f"⚡ <b>Speedtest</b>\n\n<code>{result}</code>"
            
            # Parse output speedtest-cli
            lines = result.split('\n')
            ping = ""
            download = ""
            upload = ""
            
            for line in lines:
                if "Ping:" in line:
                    ping = line.split("Ping:")[1].strip()
                elif "Download:" in line:
                    download = line.split("Download:")[1].strip()
                elif "Upload:" in line:
                    upload = line.split("Upload:")[1].strip()
            
            result_text = f"⚡ <b>Speedtest Results</b>\n"
            result_text += f"<i>Powered by speedtest-cli</i>\n\n"
            result_text += f"📶 Ping: <code>{ping if ping else 'N/A'}</code>\n"
            result_text += f"⬇️ Download: <code>{download if download else 'N/A'}</code>\n"
            result_text += f"⬆️ Upload: <code>{upload if upload else 'N/A'}</code>"
            
            return result_text
        
        # Method 3: Check if /usr/bin/speedtest exists (could be either)
        check_any = run_command("test -f /usr/bin/speedtest && echo 'OK'")
        
        if check_any:
            # Try to detect which speedtest this is
            version_check = run_command("/usr/bin/speedtest --version 2>&1")
            
            # If it's Ookla
            if "Ookla" in version_check:
                result = run_command("timeout 60 /usr/bin/speedtest --accept-license --accept-gdpr 2>&1")
                
                if "timeout" in result.lower():
                    return "⚡ <b>Speedtest</b>\n\nError: Test timeout (>60 detik)"
                
                lines = result.split('\n')
                server = ""
                ping = ""
                download = ""
                upload = ""
                
                for line in lines:
                    if "Server:" in line:
                        server = line.split("Server:")[1].strip()
                    elif "Latency:" in line or "Idle Latency:" in line:
                        parts = line.split(":")
                        if len(parts) > 1:
                            ping = parts[-1].strip().split()[0]
                    elif "Download:" in line:
                        download = line.split("Download:")[1].strip()
                    elif "Upload:" in line:
                        upload = line.split("Upload:")[1].strip()
                
                result_text = f"⚡ <b>Speedtest Results</b>\n"
                result_text += f"<i>Powered by Ookla</i>\n\n"
                if server:
                    result_text += f"🌐 Server: <code>{server}</code>\n"
                if ping:
                    result_text += f"📶 Latency: <code>{ping} ms</code>\n"
                if download:
                    result_text += f"⬇️ Download: <code>{download}</code>\n"
                if upload:
                    result_text += f"⬆️ Upload: <code>{upload}</code>\n"
                
                return result_text
            
            # If it's speedtest-cli
            else:
                result = run_command("timeout 60 /usr/bin/speedtest --simple 2>&1")
                
                if "timeout" in result.lower():
                    return "⚡ <b>Speedtest</b>\n\nError: Test timeout (>60 detik)"
                
                lines = result.split('\n')
                ping = ""
                download = ""
                upload = ""
                
                for line in lines:
                    if "Ping:" in line:
                        ping = line.split("Ping:")[1].strip()
                    elif "Download:" in line:
                        download = line.split("Download:")[1].strip()
                    elif "Upload:" in line:
                        upload = line.split("Upload:")[1].strip()
                
                result_text = f"⚡ <b>Speedtest Results</b>\n"
                result_text += f"<i>Powered by speedtest-cli</i>\n\n"
                result_text += f"📶 Ping: <code>{ping if ping else 'N/A'}</code>\n"
                result_text += f"⬇️ Download: <code>{download if download else 'N/A'}</code>\n"
                result_text += f"⬆️ Upload: <code>{upload if upload else 'N/A'}</code>"
                
                return result_text
        
        # Method 4: Not installed
        return (
            "⚠️ <b>Speedtest Tool Not Found</b>\n\n"
            "<b>Install Options:</b>\n\n"
            "<b>Option 1 - Ookla Speedtest (Recommended):</b>\n"
            "<code>cd /tmp</code>\n"
            "<code>wget https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-aarch64.tgz -O speedtest.tgz</code>\n"
            "<code>tar -xzf speedtest.tgz</code>\n"
            "<code>mv speedtest /usr/bin/speedtest-ookla</code>\n"
            "<code>chmod +x /usr/bin/speedtest-ookla</code>\n\n"
            "<b>Option 2 - speedtest-cli (Python):</b>\n"
            "<code>opkg install python3-pip</code>\n"
            "<code>pip3 install speedtest-cli</code>\n\n"
            "<b>Manual test:</b>\n"
            "<code>/cmd wget -O /dev/null http://speedtest.tele2.net/10MB.zip</code>"
        )
        
    except Exception as e:
        return f"Error: {str(e)}"

def get_disk_info() -> str:
    """Dapatkan info disk usage"""
    try:
        result = "💿 <b>Disk Usage</b>\n\n"
        
        # List disk yang ingin dicek
        disks = [
            ("sda1", "sda1"),
            ("root", "root"),
            ("mmcblk0p3", "mmcblk0p3")
        ]
        
        found_disk = False
        
        for disk_name, disk_pattern in disks:
            disk_info = run_command(f"df -h | grep {disk_pattern}")
            
            if disk_info:
                parts = disk_info.split()
                if len(parts) >= 5:
                    # Format: Filesystem Size Used Avail Use% Mounted
                    size = parts[1]
                    used = parts[2]
                    free = parts[3]
                    usage = parts[4]
                    
                    result += (
                        f"<b>{disk_name}:</b>\n"
                        f"Size: <code>{size}</code>\n"
                        f"Used: <code>{used}</code>\n"
                        f"Free: <code>{free}</code>\n"
                        f"Usage: <code>{usage}</code>\n\n"
                    )
                    found_disk = True
        
        if not found_disk:
            result += "No disk found"
        
        return result.strip()
        
    except Exception as e:
        return f"Error: {str(e)}"

def leak_test() -> str:
    """Test untuk DNS/IP leak dengan multiple methods"""
    try:
        result_text = "🔒 <b>Leak Test</b>\n\n"
        
        # 1. Public IP
        try:
            public_ip = requests.get("https://api.ipify.org", timeout=5).text.strip()
            result_text += f"🌍 <b>Public IP:</b> <code>{public_ip}</code>\n\n"
        except:
            result_text += f"🌍 <b>Public IP:</b> Unable to fetch\n\n"
            public_ip = "unknown"
        
        # 2. DNS Leak Test - Manual method (tidak perlu dnsleaktest.sh)
        result_text += "🔍 <b>DNS Leak Test:</b>\n"
        
        # Test beberapa DNS resolver
        dns_tests = [
            ("whoami.akamai.net", "Akamai"),
            ("o-o.myaddr.l.google.com", "Google"),
            ("myip.opendns.com", "OpenDNS")
        ]
        
        result_text += "━━━━━━━━━━━━━━━━━━━━\n"
        
        for domain, name in dns_tests:
            # Get DNS response
            dns_result = run_command(f"nslookup {domain} 2>&1")
            
            # Extract IP dari response
            lines = dns_result.split('\n')
            resolved_ip = None
            
            for line in lines:
                if 'Address' in line and '127.0.0.1' not in line and '#53' not in line:
                    parts = line.split()
                    if len(parts) >= 2:
                        resolved_ip = parts[-1]
                        break
            
            if resolved_ip:
                result_text += f"• {name}: <code>{resolved_ip}</code>\n"
            else:
                result_text += f"• {name}: <i>Unable to resolve</i>\n"
        
        result_text += "━━━━━━━━━━━━━━━━━━━━\n\n"
        
        # Check DNS Server yang digunakan
        dns_server = run_command("cat /etc/resolv.conf | grep nameserver | head -1 | awk '{print $2}'")
        if dns_server:
            result_text += f"📡 <b>DNS Server:</b> <code>{dns_server}</code>\n\n"
        
        # 3. Check if using VPN/Proxy
        result_text += "🛡 <b>VPN/Proxy Detection:</b>\n"
        result_text += "━━━━━━━━━━━━━━━━━━━━\n"
        
        try:
            ip_info = requests.get(f"http://ip-api.com/json/{public_ip}", timeout=5).json()
            
            if ip_info.get("status") == "success":
                is_proxy = ip_info.get("proxy", False)
                is_hosting = ip_info.get("hosting", False)
                
                if is_proxy or is_hosting:
                    result_text += f"✅ <b>Status:</b> VPN/Proxy detected\n"
                else:
                    result_text += f"⚠️ <b>Status:</b> Direct connection\n"
                
                result_text += f"📍 <b>Location:</b> <code>{ip_info.get('city', 'N/A')}, {ip_info.get('country', 'N/A')}</code>\n"
                result_text += f"🏢 <b>ISP:</b> <code>{ip_info.get('isp', 'N/A')}</code>\n"
            else:
                result_text += f"ℹ️ Unable to detect\n"
        except:
            result_text += f"ℹ️ Unable to check VPN status\n"
        
        result_text += (
            f"\n💡 <b>Untuk test lengkap kunjungi:</b>\n"
            f"• https://ipleak.net\n"
            f"• https://dnsleaktest.com\n"
            f"• https://browserleaks.com/webrtc"
        )
        
        return result_text
        
    except Exception as e:
        return f"Error: {str(e)}"

def adblock_test() -> str:
    """Test apakah adblock berfungsi dengan berbagai metode"""
    try:
        result = "🛡 <b>AdBlock Test</b>\n\n"
        
        # Test domains yang umum diblokir
        test_domains = [
            ("ads.google.com", "Google Ads"),
            ("doubleclick.net", "DoubleClick"),
            ("googleadservices.com", "Google Ad Services"),
            ("googlesyndication.com", "Google Syndication"),
            ("facebook.com/ads", "Facebook Ads"),
            ("adservice.google.com", "Ad Service"),
            ("pagead2.googlesyndication.com", "Page Ads"),
            ("static.ads-twitter.com", "Twitter Ads")
        ]
        
        blocked = 0
        not_blocked = 0
        
        result += "<b>Testing Ad Domains:</b>\n"
        result += "━━━━━━━━━━━━━━━━━━━━\n"
        
        for domain, name in test_domains:
            # Method 1: Check DNS resolution
            dns_check = run_command(f"nslookup {domain.split('/')[0]} 2>&1")
            
            # Check if blocked (NXDOMAIN, 0.0.0.0, 127.0.0.1)
            is_blocked = False
            
            if "NXDOMAIN" in dns_check:
                is_blocked = True
            elif "0.0.0.0" in dns_check or "127.0.0.1" in dns_check:
                is_blocked = True
            elif "can't resolve" in dns_check.lower():
                is_blocked = True
            
            if is_blocked:
                result += f"✅ {name}\n"
                blocked += 1
            else:
                result += f"❌ {name}\n"
                not_blocked += 1
        
        result += "━━━━━━━━━━━━━━━━━━━━\n"
        
        # Calculate percentage
        total = blocked + not_blocked
        percentage = (blocked / total * 100) if total > 0 else 0
        
        result += f"\n📊 <b>Summary:</b>\n"
        result += f"Blocked: {blocked}/{total} ({percentage:.1f}%)\n"
        
        if percentage >= 80:
            result += "\n✅ <b>AdBlock: EXCELLENT</b>"
        elif percentage >= 50:
            result += "\n⚠️ <b>AdBlock: GOOD</b>"
        elif percentage >= 20:
            result += "\n⚠️ <b>AdBlock: FAIR</b>"
        else:
            result += "\n❌ <b>AdBlock: POOR</b>"
        
        result += (
            f"\n\n💡 <b>Untuk test lengkap:</b>\n"
            f"• https://d3ward.github.io/toolz/adblock.html\n"
            f"• https://blockads.fivefilters.org/\n"
            f"• https://adblock-tester.com/"
        )
        
        return result
        
    except Exception as e:
        return f"Error: {str(e)}"

def check_services() -> str:
    """Cek status service"""
    try:
        services = ["openclash", "nikki", "cloudflared"]
        result = "⚙️ <b>Services Status</b>\n\n"
        
        for service in services:
            # Gunakan service command seperti di CLI
            status = run_command(f"service {service} status 2>&1")
            
            # Parse status
            status_lower = status.lower()
            
            if "running" in status_lower:
                result += f"✅ <b>{service}:</b> RUNNING\n"
            elif "active with no instances" in status_lower:
                result += f"⚠️ <b>{service}:</b> ACTIVE (no instances)\n"
            elif "active" in status_lower:
                result += f"✅ <b>{service}:</b> ACTIVE\n"
            elif "inactive" in status_lower or "stopped" in status_lower:
                result += f"❌ <b>{service}:</b> STOPPED\n"
            elif "not found" in status_lower or "usage" in status_lower:
                result += f"❓ <b>{service}:</b> NOT INSTALLED\n"
            else:
                # Jika status tidak jelas, cek dengan ps
                ps_check = run_command(f"ps | grep {service} | grep -v grep")
                if ps_check:
                    result += f"✅ <b>{service}:</b> RUNNING\n"
                else:
                    result += f"❌ <b>{service}:</b> STOPPED\n"
        
        result += "\n💡 <i>Klik 'Service Control' untuk manage services</i>"
        
        return result
    except Exception as e:
        return f"Error: {str(e)}"

def get_container_info() -> str:
    """Dapatkan info container (Docker/Podman)"""
    try:
        result = "🐳 <b>Container Information</b>\n\n"
        
        # Check if docker exists
        docker_check = run_command("which docker")
        podman_check = run_command("which podman")
        
        if docker_check:
            # Get docker containers
            containers = run_command("docker ps -a --format '{{.Names}}|{{.Status}}|{{.Image}}'")
            
            if containers and "Error" not in containers:
                result += "<b>Docker Containers:</b>\n"
                for line in containers.split('\n'):
                    if line:
                        parts = line.split('|')
                        if len(parts) >= 3:
                            name = parts[0]
                            status = parts[1]
                            image = parts[2]
                            
                            status_emoji = "🟢" if "Up" in status else "🔴"
                            result += f"{status_emoji} <b>{name}</b>\n"
                            result += f"   Image: <code>{image}</code>\n"
                            result += f"   Status: <code>{status}</code>\n\n"
            else:
                result += "No Docker containers found\n\n"
        
        elif podman_check:
            # Get podman containers
            containers = run_command("podman ps -a --format '{{.Names}}|{{.Status}}|{{.Image}}'")
            
            if containers and "Error" not in containers:
                result += "<b>Podman Containers:</b>\n"
                for line in containers.split('\n'):
                    if line:
                        parts = line.split('|')
                        if len(parts) >= 3:
                            name = parts[0]
                            status = parts[1]
                            image = parts[2]
                            
                            status_emoji = "🟢" if "Up" in status else "🔴"
                            result += f"{status_emoji} <b>{name}</b>\n"
                            result += f"   Image: <code>{image}</code>\n"
                            result += f"   Status: <code>{status}</code>\n\n"
            else:
                result += "No Podman containers found\n\n"
        else:
            result += "❌ Docker/Podman not installed"
        
        return result
        
    except Exception as e:
        return f"Error: {str(e)}"

def service_control(service_name: str, action: str) -> str:
    """Control service (start, stop, restart)"""
    try:
        if action not in ["start", "stop", "restart"]:
            return "❌ Invalid action. Use: start, stop, restart"
        
        result = run_command(f"service {service_name} {action} 2>&1")
        
        # Wait a bit and check status
        import time
        time.sleep(2)
        
        status = run_command(f"service {service_name} status 2>&1")
        
        return (
            f"⚙️ <b>Service Control</b>\n\n"
            f"Service: <code>{service_name}</code>\n"
            f"Action: <code>{action}</code>\n\n"
            f"<b>Result:</b>\n<code>{result}</code>\n\n"
            f"<b>Current Status:</b>\n<code>{status}</code>"
        )
        
    except Exception as e:
        return f"Error: {str(e)}"

# ==================== KEYBOARD ====================

def get_main_keyboard() -> InlineKeyboardMarkup:
    """Buat keyboard inline utama"""
    keyboard = [
        [
            InlineKeyboardButton("🖥 CPU & RAM", callback_data="cpu_ram"),
            InlineKeyboardButton("👥 Online Users", callback_data="online_users")
        ],
        [
            InlineKeyboardButton("📊 Traffic", callback_data="traffic"),
            InlineKeyboardButton("🌍 My IP", callback_data="myip")
        ],
        [
            InlineKeyboardButton("🔍 Ping", callback_data="ping"),
            InlineKeyboardButton("⚡ Speedtest", callback_data="speedtest")
        ],
        [
            InlineKeyboardButton("💿 Disk", callback_data="disk"),
            InlineKeyboardButton("🔒 Leak Test", callback_data="leaktest")
        ],
        [
            InlineKeyboardButton("🛡 AdBlock", callback_data="adblock"),
            InlineKeyboardButton("⚙️ Services", callback_data="services")
        ],
        [
            InlineKeyboardButton("🐳 Containers", callback_data="containers"),
            InlineKeyboardButton("💻 Command", callback_data="command")
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

def get_services_keyboard() -> InlineKeyboardMarkup:
    """Keyboard untuk services dengan tombol Service Control"""
    keyboard = [
        [
            InlineKeyboardButton("🔧 Service Control", callback_data="service_control")
        ],
        [
            InlineKeyboardButton("🔙 Back to Menu", callback_data="back_to_menu")
        ]
    ]
    return InlineKeyboardMarkup(keyboard)

def get_service_control_keyboard() -> InlineKeyboardMarkup:
    """Keyboard untuk service control"""
    services = ["openclash", "nikki", "cloudflared"]
    keyboard = []
    
    for service in services:
        keyboard.append([
            InlineKeyboardButton(f"▶️ Start", callback_data=f"svc_start_{service}"),
            InlineKeyboardButton(f"{service}", callback_data=f"svc_info_{service}"),
            InlineKeyboardButton(f"⏹ Stop", callback_data=f"svc_stop_{service}")
        ])
        keyboard.append([
            InlineKeyboardButton(f"🔄 Restart {service}", callback_data=f"svc_restart_{service}")
        ])
    
    keyboard.append([
        InlineKeyboardButton("🔙 Back to Menu", callback_data="back_to_menu")
    ])
    
    return InlineKeyboardMarkup(keyboard)

def get_containers_keyboard() -> InlineKeyboardMarkup:
    """Keyboard untuk containers dengan tombol back"""
    keyboard = [
        [
            InlineKeyboardButton("🔙 Back to Menu", callback_data="back_to_menu")
        ]
    ]
    return InlineKeyboardMarkup(keyboard)

# ==================== HANDLER TELEGRAM ====================

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk /start"""
    user_id = update.effective_user.id
    
    if not check_auth(user_id):
        await update.message.reply_text("❌ Unauthorized access!")
        return
    
    welcome_text = (
        "🤖 <b>OpenWRT Monitoring Bot</b>\n\n"
        "Selamat datang di bot monitoring untuk Raspberry Pi 4 OpenWRT!\n\n"
        "Pilih menu di bawah untuk melihat informasi:"
    )
    
    await update.message.reply_text(
        welcome_text,
        reply_markup=get_main_keyboard(),
        parse_mode='HTML'
    )
    
    # Kirim reply keyboard
    await update.message.reply_text(
        "Gunakan tombol di bawah untuk navigasi cepat:",
        reply_markup=get_reply_keyboard()
    )

async def handle_keyboard_button(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk keyboard button (Menu, Help, Refresh)"""
    user_id = update.effective_user.id
    
    if not check_auth(user_id):
        return
    
    text = update.message.text
    
    if text == "📋 Menu":
        msg = "📋 <b>MENU UTAMA</b>\n\nPilih menu yang Anda inginkan:"
        await update.message.reply_text(
            msg,
            parse_mode='HTML',
            reply_markup=get_main_keyboard()
        )
    
    elif text == "ℹ️ Help":
        msg = get_help_text()
        await update.message.reply_text(
            msg,
            parse_mode='HTML'
        )
    
    elif text == "🔄 Refresh":
        msg = "🔄 <b>System Refreshed!</b>\n\nSilakan pilih menu untuk melihat data terbaru."
        await update.message.reply_text(
            msg,
            parse_mode='HTML',
            reply_markup=get_main_keyboard()
        )

def get_help_text():
    """Get help text"""
    return (
        "🤖 <b>PANDUAN MONITORING BOT</b>\n\n"
        "<b>MENU TERSEDIA:</b>\n"
        "• 🖥 CPU & RAM - Info CPU dan memory\n"
        "• 👥 Online Users - Daftar device online\n"
        "• 📊 Traffic - Statistik bandwidth\n"
        "• 🌍 My IP - Info IP public\n"
        "• 🔍 Ping - Test koneksi\n"
        "• ⚡ Speedtest - Test kecepatan internet\n"
        "• 💿 Disk - Info disk usage\n"
        "• 🔒 Leak Test - DNS/IP leak test\n"
        "• 🛡 AdBlock - Test adblock\n"
        "• ⚙️ Services - Status services\n"
        "• 🐳 Containers - Info Docker/Podman\n"
        "• 🔧 Service Control - Start/Stop/Restart services\n"
        "• 💻 Command - Jalankan command custom\n\n"
        "<b>TOMBOL NAVIGASI:</b>\n"
        "• 📋 Menu - Kembali ke menu utama\n"
        "• ℹ️ Help - Tampilkan panduan ini\n"
        "• 🔄 Refresh - Refresh data\n\n"
        "<b>CUSTOM COMMAND:</b>\n"
        "Format: <code>/cmd your_command</code>\n"
        "Contoh: <code>/cmd uptime</code>\n\n"
        "<b>TOOLS YANG DIBUTUHKAN:</b>\n"
        "• DNS Leak Test: dnsleaktest.sh ✅\n"
        "• Speedtest: speedtest-cli atau speedtest\n"
        "• AdBlock Test: Built-in DNS checker\n\n"
        "Semua tools akan memberikan instruksi instalasi jika belum tersedia."
    )

async def button_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk button callback"""
    query = update.callback_query
    user_id = query.from_user.id
    
    if not check_auth(user_id):
        await query.answer("❌ Unauthorized!")
        return
    
    await query.answer()
    
    callback_data = query.data
    
    # Handle back to menu
    if callback_data == "back_to_menu":
        await query.edit_message_text(
            text="📋 <b>MENU UTAMA</b>\n\nPilih menu yang Anda inginkan:",
            parse_mode='HTML',
            reply_markup=get_main_keyboard()
        )
        return
    
    # Handle service control callbacks
    if callback_data.startswith("svc_"):
        parts = callback_data.split("_")
        if len(parts) >= 3:
            action = parts[1]  # start, stop, restart, info
            service = "_".join(parts[2:])  # service name
            
            # If action is info, just show current status
            if action == "info":
                status = run_command(f"service {service} status 2>&1")
                
                msg = (
                    f"⚙️ <b>Service Info</b>\n\n"
                    f"Service: <code>{service}</code>\n\n"
                    f"<b>Current Status:</b>\n<code>{status}</code>"
                )
                
                await query.edit_message_text(
                    text=msg,
                    parse_mode='HTML',
                    reply_markup=get_service_control_keyboard()
                )
                return
            
            loading_msg = await query.edit_message_text("⏳ Processing...")
            result = service_control(service, action)
            
            await loading_msg.edit_text(
                result,
                parse_mode='HTML',
                reply_markup=get_service_control_keyboard()
            )
        return
    
    # Handle service control menu
    if callback_data == "service_control":
        msg = (
            "🔧 <b>SERVICE CONTROL</b>\n\n"
            "Pilih action untuk service:\n"
            "▶️ Start | ⏹ Stop | 🔄 Restart\n\n"
            "Klik nama service untuk melihat status."
        )
        await query.edit_message_text(
            text=msg,
            parse_mode='HTML',
            reply_markup=get_service_control_keyboard()
        )
        return
    
    # Show loading message
    loading_msg = await query.edit_message_text(text="⏳ Loading...")
    
    try:
        if callback_data == "cpu_ram":
            result = get_cpu_ram_info()
            keyboard = get_main_keyboard()
            
        elif callback_data == "online_users":
            result = get_online_users()
            keyboard = get_main_keyboard()
            
        elif callback_data == "traffic":
            result = get_vnstat_traffic()
            keyboard = get_main_keyboard()
            
        elif callback_data == "myip":
            result = get_my_ip()
            keyboard = get_main_keyboard()
            
        elif callback_data == "ping":
            result = ping_test()
            keyboard = get_main_keyboard()
            
        elif callback_data == "speedtest":
            result = speedtest()
            keyboard = get_main_keyboard()
            
        elif callback_data == "disk":
            result = get_disk_info()
            keyboard = get_main_keyboard()
            
        elif callback_data == "leaktest":
            result = leak_test()
            keyboard = get_main_keyboard()
            
        elif callback_data == "adblock":
            result = adblock_test()
            keyboard = get_main_keyboard()
            
        elif callback_data == "services":
            result = check_services()
            keyboard = get_services_keyboard()
            
        elif callback_data == "containers":
            result = get_container_info()
            keyboard = get_containers_keyboard()
            
        elif callback_data == "command":
            result = (
                "💻 <b>Command Mode</b>\n\n"
                "Kirim command dengan format:\n"
                "<code>/cmd your_command_here</code>\n\n"
                "Contoh:\n"
                "<code>/cmd uptime</code>\n"
                "<code>/cmd ip addr</code>"
            )
            await loading_msg.edit_text(result, parse_mode='HTML', reply_markup=get_main_keyboard())
            return
        else:
            result = "Unknown command"
            keyboard = get_main_keyboard()
        
        # Split message if too long
        if len(result) > 4000:
            chunks = [result[i:i+4000] for i in range(0, len(result), 4000)]
            await loading_msg.edit_text(
                text=chunks[0],
                parse_mode='HTML',
                reply_markup=keyboard
            )
            for chunk in chunks[1:]:
                await query.message.reply_text(
                    text=chunk,
                    parse_mode='HTML'
                )
        else:
            await loading_msg.edit_text(
                result,
                parse_mode='HTML',
                reply_markup=keyboard
            )
            
    except Exception as e:
        logger.error(f"Error in button_callback: {e}")
        error_msg = f"❌ Terjadi kesalahan: {str(e)}"
        await loading_msg.edit_text(
            text=error_msg,
            parse_mode='HTML',
            reply_markup=get_main_keyboard()
        )

async def cmd_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk custom command"""
    user_id = update.effective_user.id
    
    if not check_auth(user_id):
        await update.message.reply_text("❌ Unauthorized!")
        return
    
    if not context.args:
        await update.message.reply_text(
            "❌ Format: <code>/cmd your_command</code>",
            parse_mode='HTML'
        )
        return
    
    command = ' '.join(context.args)
    
    # Blacklist command berbahaya
    blacklist = ['rm -rf', 'dd if=', 'mkfs', 'format', '> /dev/']
    if any(cmd in command.lower() for cmd in blacklist):
        await update.message.reply_text("❌ Dangerous command blocked!")
        return
    
    loading_msg = await update.message.reply_text("⏳ Executing...")
    
    result = run_command(command)
    
    # Split jika terlalu panjang
    if len(result) > 4000:
        result = result[:4000] + "\n\n... (truncated)"
    
    await loading_msg.edit_text(
        f"💻 <b>Command:</b> <code>{command}</code>\n\n"
        f"<b>Output:</b>\n<code>{result}</code>",
        parse_mode='HTML'
    )

async def error_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler untuk error"""
    logger.error(f"Update {update} caused error {context.error}")

# ==================== MAIN ====================

def main():
    """Main function"""
    # Buat application
    application = Application.builder().token(BOT_TOKEN).build()
    
    # Register handlers
    application.add_handler(CommandHandler("start", start))
    application.add_handler(CommandHandler("cmd", cmd_handler))
    
    # Register message handler untuk keyboard buttons
    application.add_handler(MessageHandler(
        filters.Regex('^(📋 Menu|ℹ️ Help|🔄 Refresh)$'),
        handle_keyboard_button
    ))
    
    application.add_handler(CallbackQueryHandler(button_callback))
    application.add_error_handler(error_handler)
    
    # Start bot
    logger.info("Bot started!")
    application.run_polling(allowed_updates=Update.ALL_TYPES)

if __name__ == "__main__":
    main()