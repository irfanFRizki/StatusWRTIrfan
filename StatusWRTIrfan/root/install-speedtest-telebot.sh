#!/bin/bash

# Speed Test Monitor Installation Script
# For OpenWrt/Linux systems

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
INSTALL_DIR="/opt/speedtest-monitor"
SERVICE_NAME="speedtest-monitor"
PYTHON_SCRIPT="speedtest_monitor.py"
WEB_DIR="/www/speedtest"

echo -e "${BLUE}🚀 Speed Test Monitor Installation Script${NC}"
echo "=================================="

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root (use sudo)"
   exit 1
fi

# Detect system type
detect_system() {
    if [ -f /etc/openwrt_release ]; then
        SYSTEM="openwrt"
        print_status "Detected OpenWrt system"
    elif [ -f /etc/debian_version ]; then
        SYSTEM="debian"
        print_status "Detected Debian/Ubuntu system"
    elif [ -f /etc/redhat-release ]; then
        SYSTEM="redhat"
        print_status "Detected RedHat/CentOS system"
    else
        SYSTEM="generic"
        print_warning "Unknown system, proceeding with generic installation"
    fi
}

# Install dependencies
install_dependencies() {
    print_status "Installing dependencies..."
    
    case $SYSTEM in
        "openwrt")
            opkg update
            opkg install python3 python3-pip python3-sqlite3
            pip3 install speedtest-cli requests schedule
            ;;
        "debian")
            apt update
            apt install -y python3 python3-pip python3-sqlite3 speedtest-cli
            pip3 install requests schedule
            ;;
        "redhat")
            yum install -y python3 python3-pip python3-sqlite3
            pip3 install speedtest-cli requests schedule
            ;;
        *)
            print_warning "Please install Python3, pip3, and sqlite3 manually"
            pip3 install speedtest-cli requests schedule
            ;;
    esac
}

# Create installation directory
create_directories() {
    print_status "Creating directories..."
    
    mkdir -p $INSTALL_DIR
    mkdir -p $WEB_DIR
    mkdir -p /var/log/speedtest-monitor
}

# Install Python script
install_python_script() {
    print_status "Installing Python script..."
    
    # Check if speedtest_monitor.py exists in current directory
    if [ ! -f "$PYTHON_SCRIPT" ]; then
        print_warning "speedtest_monitor.py not found in current directory!"
        print_status "Creating Python script from template..."
        
        # Create the Python script directly
        cat > "$INSTALL_DIR/$PYTHON_SCRIPT" << 'PYTHON_EOF'
#!/usr/bin/env python3
"""
Speed Test Monitor with Telegram Integration
Automated speed testing and daily reporting system
"""

import subprocess
import json
import requests
import sqlite3
import schedule
import time
import logging
from datetime import datetime, timedelta
from typing import Dict, List, Optional
import re
import os
import argparse

# Configuration
CONFIG_FILE = "speedtest_config.json"
DB_FILE = "speedtest_history.db"

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('speedtest.log'),
        logging.StreamHandler()
    ]
)

class SpeedTestMonitor:
    def __init__(self, config_file: str = CONFIG_FILE):
        self.config_file = config_file
        self.config = self.load_config()
        self.db_file = DB_FILE
        self.init_database()
        
    def load_config(self) -> Dict:
        """Load configuration from JSON file"""
        default_config = {
            "telegram": {
                "bot_token": "",
                "chat_id": "",
                "daily_time": "07:00"
            },
            "speedtest": {
                "server_id": None,
                "timeout": 60
            }
        }
        
        try:
            if os.path.exists(self.config_file):
                with open(self.config_file, 'r') as f:
                    config = json.load(f)
                # Merge with defaults
                for key in default_config:
                    if key not in config:
                        config[key] = default_config[key]
                    elif isinstance(default_config[key], dict):
                        for subkey in default_config[key]:
                            if subkey not in config[key]:
                                config[key][subkey] = default_config[key][subkey]
                return config
            else:
                return default_config
        except Exception as e:
            logging.error(f"Error loading config: {e}")
            return default_config
    
    def save_config(self):
        """Save configuration to JSON file"""
        try:
            with open(self.config_file, 'w') as f:
                json.dump(self.config, f, indent=2)
        except Exception as e:
            logging.error(f"Error saving config: {e}")
    
    def init_database(self):
        """Initialize SQLite database"""
        try:
            conn = sqlite3.connect(self.db_file)
            cursor = conn.cursor()
            cursor.execute('''
                CREATE TABLE IF NOT EXISTS speed_tests (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                    download_mbps REAL,
                    upload_mbps REAL,
                    ping_ms REAL,
                    server_name TEXT,
                    server_location TEXT,
                    external_ip TEXT
                )
            ''')
            conn.commit()
            conn.close()
            logging.info("Database initialized successfully")
        except Exception as e:
            logging.error(f"Error initializing database: {e}")
    
    def run_speedtest(self) -> Optional[Dict]:
        """Run speedtest-cli and parse results"""
        try:
            logging.info("Starting speed test...")
            
            # Build speedtest command
            cmd = ["speedtest-cli", "--json"]
            if self.config["speedtest"]["server_id"]:
                cmd.extend(["--server", str(self.config["speedtest"]["server_id"])])
            
            # Run speedtest with timeout
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=self.config["speedtest"]["timeout"]
            )
            
            if result.returncode != 0:
                logging.error(f"Speedtest failed: {result.stderr}")
                return None
            
            # Parse JSON output
            data = json.loads(result.stdout)
            
            test_result = {
                "timestamp": datetime.now().isoformat(),
                "download_mbps": round(data["download"] / 1_000_000, 2),
                "upload_mbps": round(data["upload"] / 1_000_000, 2),
                "ping_ms": round(data["ping"], 2),
                "server_name": data["server"]["sponsor"],
                "server_location": f"{data['server']['name']}, {data['server']['country']}",
                "external_ip": data["client"]["ip"]
            }
            
            logging.info(f"Speed test completed: {test_result['download_mbps']} Mbps down, "
                        f"{test_result['upload_mbps']} Mbps up, {test_result['ping_ms']} ms ping")
            
            return test_result
            
        except subprocess.TimeoutExpired:
            logging.error("Speed test timed out")
            return None
        except json.JSONDecodeError as e:
            logging.error(f"Error parsing speedtest JSON: {e}")
            return None
        except Exception as e:
            logging.error(f"Error running speed test: {e}")
            return None
    
    def save_test_result(self, result: Dict):
        """Save test result to database"""
        try:
            conn = sqlite3.connect(self.db_file)
            cursor = conn.cursor()
            cursor.execute('''
                INSERT INTO speed_tests 
                (timestamp, download_mbps, upload_mbps, ping_ms, server_name, server_location, external_ip)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            ''', (
                result["timestamp"],
                result["download_mbps"],
                result["upload_mbps"],
                result["ping_ms"],
                result["server_name"],
                result["server_location"],
                result["external_ip"]
            ))
            conn.commit()
            conn.close()
            logging.info("Test result saved to database")
        except Exception as e:
            logging.error(f"Error saving test result: {e}")
    
    def get_recent_tests(self, days: int = 7) -> List[Dict]:
        """Get recent test results from database"""
        try:
            conn = sqlite3.connect(self.db_file)
            cursor = conn.cursor()
            
            since_date = (datetime.now() - timedelta(days=days)).isoformat()
            cursor.execute('''
                SELECT * FROM speed_tests 
                WHERE timestamp > ? 
                ORDER BY timestamp DESC
            ''', (since_date,))
            
            rows = cursor.fetchall()
            conn.close()
            
            # Convert to list of dictionaries
            results = []
            columns = ["id", "timestamp", "download_mbps", "upload_mbps", "ping_ms", 
                      "server_name", "server_location", "external_ip"]
            
            for row in rows:
                result = dict(zip(columns, row))
                results.append(result)
            
            return results
        except Exception as e:
            logging.error(f"Error getting recent tests: {e}")
            return []
    
    def calculate_averages(self, tests: List[Dict]) -> Dict:
        """Calculate average speeds from test results"""
        if not tests:
            return {"download": 0, "upload": 0, "ping": 0, "count": 0}
        
        avg_download = sum(test["download_mbps"] for test in tests) / len(tests)
        avg_upload = sum(test["upload_mbps"] for test in tests) / len(tests)
        avg_ping = sum(test["ping_ms"] for test in tests) / len(tests)
        
        return {
            "download": round(avg_download, 2),
            "upload": round(avg_upload, 2),
            "ping": round(avg_ping, 2),
            "count": len(tests)
        }
    
    def send_telegram_message(self, message: str) -> bool:
        """Send message to Telegram"""
        if not self.config["telegram"]["bot_token"] or not self.config["telegram"]["chat_id"]:
            logging.error("Telegram bot token or chat ID not configured")
            return False
        
        try:
            url = f"https://api.telegram.org/bot{self.config['telegram']['bot_token']}/sendMessage"
            payload = {
                "chat_id": self.config["telegram"]["chat_id"],
                "text": message,
                "parse_mode": "Markdown"
            }
            
            response = requests.post(url, json=payload, timeout=30)
            response.raise_for_status()
            
            result = response.json()
            if result.get("ok"):
                logging.info("Telegram message sent successfully")
                return True
            else:
                logging.error(f"Telegram API error: {result.get('description', 'Unknown error')}")
                return False
                
        except requests.exceptions.RequestException as e:
            logging.error(f"Error sending Telegram message: {e}")
            return False
        except Exception as e:
            logging.error(f"Unexpected error sending Telegram message: {e}")
            return False
    
    def format_speed_report(self, test_result: Dict, include_history: bool = True) -> str:
        """Format speed test result for Telegram"""
        timestamp = datetime.fromisoformat(test_result["timestamp"].replace('Z', '+00:00'))
        
        message = f"🚀 *Speed Test Report*\n\n"
        message += f"📅 *Date:* {timestamp.strftime('%Y-%m-%d')}\n"
        message += f"🕐 *Time:* {timestamp.strftime('%H:%M:%S')}\n\n"
        message += f"📥 *Download:* {test_result['download_mbps']} Mbps\n"
        message += f"📤 *Upload:* {test_result['upload_mbps']} Mbps\n"
        message += f"📡 *Ping:* {test_result['ping_ms']} ms\n"
        message += f"🌐 *Server:* {test_result['server_name']}\n"
        message += f"📍 *Location:* {test_result['server_location']}\n"
        message += f"🌍 *External IP:* {test_result['external_ip']}\n"
        
        if include_history:
            # Add weekly average
            recent_tests = self.get_recent_tests(7)
            if len(recent_tests) > 1:
                averages = self.calculate_averages(recent_tests)
                message += f"\n📊 *7-Day Average ({averages['count']} tests):*\n"
                message += f"📥 {averages['download']} Mbps | 📤 {averages['upload']} Mbps | 📡 {averages['ping']} ms\n"
        
        message += f"\n_Generated by Speed Test Monitor_"
        return message
    
    def format_daily_report(self, test_result: Dict) -> str:
        """Format daily speed test report"""
        message = f"🌅 *Daily Speed Test Report*\n\n"
        
        # Current test results
        timestamp = datetime.fromisoformat(test_result["timestamp"].replace('Z', '+00:00'))
        message += f"📅 *Date:* {timestamp.strftime('%Y-%m-%d')}\n"
        message += f"🕐 *Time:* {timestamp.strftime('%H:%M:%S')}\n\n"
        message += f"📥 *Download Speed:* {test_result['download_mbps']} Mbps\n"
        message += f"📤 *Upload Speed:* {test_result['upload_mbps']} Mbps\n"
        message += f"📡 *Ping:* {test_result['ping_ms']} ms\n"
        message += f"🌐 *Server:* {test_result['server_name']}\n"
        message += f"📍 *Location:* {test_result['server_location']}\n\n"
        
        # Historical data
        recent_tests = self.get_recent_tests(7)
        if len(recent_tests) > 1:
            averages = self.calculate_averages(recent_tests)
            message += f"📊 *Weekly Average ({averages['count']} tests):*\n"
            message += f"📥 {averages['download']} Mbps | 📤 {averages['upload']} Mbps | 📡 {averages['ping']} ms\n\n"
        
        # Monthly average
        monthly_tests = self.get_recent_tests(30)
        if len(monthly_tests) > len(recent_tests):
            monthly_avg = self.calculate_averages(monthly_tests)
            message += f"📈 *Monthly Average ({monthly_avg['count']} tests):*\n"
            message += f"📥 {monthly_avg['download']} Mbps | 📤 {monthly_avg['upload']} Mbps | 📡 {monthly_avg['ping']} ms\n\n"
        
        # Speed trend analysis
        if len(recent_tests) >= 3:
            trend = self.analyze_speed_trend(recent_tests[:3])
            message += f"📈 *Trend (last 3 tests):* {trend}\n\n"
        
        message += f"_Automated daily report from Speed Test Monitor_"
        return message
    
    def analyze_speed_trend(self, tests: List[Dict]) -> str:
        """Analyze speed trend from recent tests"""
        if len(tests) < 3:
            return "Insufficient data"
        
        # Sort by timestamp (newest first)
        sorted_tests = sorted(tests, key=lambda x: x["timestamp"], reverse=True)
        
        # Calculate trend for download speed
        speeds = [test["download_mbps"] for test in sorted_tests]
        
        if speeds[0] > speeds[1] > speeds[2]:
            return "📈 Improving"
        elif speeds[0] < speeds[1] < speeds[2]:
            return "📉 Declining"
        elif abs(speeds[0] - speeds[2]) < 1:  # Less than 1 Mbps difference
            return "➡️ Stable"
        else:
            return "↗️ Variable"
    
    def run_test_and_report(self, send_telegram: bool = True) -> Optional[Dict]:
        """Run speed test and optionally send to Telegram"""
        test_result = self.run_speedtest()
        if not test_result:
            return None
        
        # Save to database
        self.save_test_result(test_result)
        
        # Send to Telegram if requested
        if send_telegram and self.config["telegram"]["bot_token"]:
            message = self.format_speed_report(test_result)
            self.send_telegram_message(message)
        
        return test_result
    
    def daily_report(self):
        """Run daily speed test and send report"""
        logging.info("Running daily speed test report...")
        
        test_result = self.run_speedtest()
        if not test_result:
            error_msg = "❌ *Daily Speed Test Failed*\n\nUnable to complete speed test. Please check your internet connection and try again."
            self.send_telegram_message(error_msg)
            return
        
        # Save to database
        self.save_test_result(test_result)
        
        # Send daily report
        message = self.format_daily_report(test_result)
        self.send_telegram_message(message)
    
    def setup_scheduler(self):
        """Setup daily scheduled tests"""
        if not self.config["telegram"]["daily_time"]:
            logging.warning("Daily time not configured, skipping scheduler setup")
            return
        
        daily_time = self.config["telegram"]["daily_time"]
        schedule.every().day.at(daily_time).do(self.daily_report)
        logging.info(f"Scheduled daily reports at {daily_time}")
    
    def run_scheduler(self):
        """Run the scheduler"""
        self.setup_scheduler()
        
        logging.info("Speed Test Monitor started. Press Ctrl+C to stop.")
        logging.info(f"Daily reports scheduled at {self.config['telegram']['daily_time']}")
        
        try:
            while True:
                schedule.run_pending()
                time.sleep(60)  # Check every minute
        except KeyboardInterrupt:
            logging.info("Scheduler stopped by user")
    
    def configure_telegram(self, bot_token: str, chat_id: str, daily_time: str = "07:00"):
        """Configure Telegram settings"""
        self.config["telegram"]["bot_token"] = bot_token
        self.config["telegram"]["chat_id"] = chat_id
        self.config["telegram"]["daily_time"] = daily_time
        self.save_config()
        logging.info("Telegram configuration updated")
    
    def test_telegram(self) -> bool:
        """Test Telegram bot connection"""
        if not self.config["telegram"]["bot_token"] or not self.config["telegram"]["chat_id"]:
            logging.error("Telegram not configured")
            return False
        
        test_message = f"🧪 *Speed Test Monitor*\n\n✅ Telegram bot connection test successful!\n\n📅 {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"
        return self.send_telegram_message(test_message)
    
    def get_status(self) -> Dict:
        """Get current status and recent tests"""
        recent_tests = self.get_recent_tests(1)
        total_tests = len(self.get_recent_tests(9999))  # Get all tests
        
        status = {
            "telegram_configured": bool(self.config["telegram"]["bot_token"] and self.config["telegram"]["chat_id"]),
            "daily_time": self.config["telegram"]["daily_time"],
            "total_tests": total_tests,
            "last_test": recent_tests[0] if recent_tests else None
        }
        
        return status


def main():
    parser = argparse.ArgumentParser(description="Speed Test Monitor with Telegram Integration")
    parser.add_argument("--config", default=CONFIG_FILE, help="Configuration file path")
    parser.add_argument("--run-test", action="store_true", help="Run single speed test")
    parser.add_argument("--daily-report", action="store_true", help="Send daily report")
    parser.add_argument("--start-scheduler", action="store_true", help="Start daily scheduler")
    parser.add_argument("--test-telegram", action="store_true", help="Test Telegram bot connection")
    parser.add_argument("--configure", action="store_true", help="Configure Telegram settings")
    parser.add_argument("--status", action="store_true", help="Show current status")
    
    args = parser.parse_args()
    
    # Initialize monitor
    monitor = SpeedTestMonitor(args.config)
    
    if args.configure:
        print("Configure Telegram Bot:")
        bot_token = input("Bot Token: ").strip()
        chat_id = input("Chat ID: ").strip()
        daily_time = input("Daily report time (HH:MM, default 07:00): ").strip() or "07:00"
        
        monitor.configure_telegram(bot_token, chat_id, daily_time)
        print("Configuration saved!")
        
    elif args.test_telegram:
        if monitor.test_telegram():
            print("✅ Telegram test successful!")
        else:
            print("❌ Telegram test failed!")
            
    elif args.run_test:
        result = monitor.run_test_and_report()
        if result:
            print(f"Speed Test Results:")
            print(f"Download: {result['download_mbps']} Mbps")
            print(f"Upload: {result['upload_mbps']} Mbps")
            print(f"Ping: {result['ping_ms']} ms")
        else:
            print("Speed test failed!")
            
    elif args.daily_report:
        monitor.daily_report()
        
    elif args.start_scheduler:
        monitor.run_scheduler()
        
    elif args.status:
        status = monitor.get_status()
        print(f"Status:")
        print(f"- Telegram configured: {status['telegram_configured']}")
        print(f"- Daily report time: {status['daily_time']}")
        print(f"- Total tests in database: {status['total_tests']}")
        if status['last_test']:
            last = status['last_test']
            print(f"- Last test: {last['timestamp']} - {last['download_mbps']} Mbps down, {last['upload_mbps']} Mbps up")
        else:
            print("- No tests recorded yet")
    
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
PYTHON_EOF
        
        print_status "Python script created successfully"
    else
        cp "$PYTHON_SCRIPT" "$INSTALL_DIR/"
        print_status "Python script copied from current directory"
    fi
    
    chmod +x "$INSTALL_DIR/$PYTHON_SCRIPT"
    
    # Create symlink for easy access - prioritize /usr/bin for OpenWrt
    if [ "$SYSTEM" = "openwrt" ]; then
        # For OpenWrt, use /usr/bin which is always in PATH
        ln -sf "$INSTALL_DIR/$PYTHON_SCRIPT" /usr/bin/speedtest-monitor
        print_status "Created symlink in /usr/bin/speedtest-monitor"
    else
        # For other systems, create /usr/local/bin if it doesn't exist
        mkdir -p /usr/local/bin
        ln -sf "$INSTALL_DIR/$PYTHON_SCRIPT" /usr/local/bin/speedtest-monitor
        
        # Ensure /usr/local/bin is in PATH
        if ! echo "$PATH" | grep -q "/usr/local/bin"; then
            echo 'export PATH=$PATH:/usr/local/bin' >> /etc/profile
            export PATH=$PATH:/usr/local/bin
        fi
        print_status "Created symlink in /usr/local/bin/speedtest-monitor"
    fi
}

# Install web interface
install_web_interface() {
    print_status "Installing web interface..."
    
    # Create index.html in web directory (basic redirect)
    cat > $WEB_DIR/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Speed Test Monitor</title>
    <meta http-equiv="refresh" content="0; url=/speedtest-monitor.html">
</head>
<body>
    <p>Redirecting to Speed Test Monitor...</p>
</body>
</html>
EOF

    print_status "Web interface installed at $WEB_DIR"
    print_warning "You'll need to copy the HTML file manually to your web server"
}

# Create systemd service (for systems that support it)
create_systemd_service() {
    if command -v systemctl &> /dev/null; then
        print_status "Creating systemd service..."
        
        cat > /etc/systemd/system/$SERVICE_NAME.service << EOF
[Unit]
Description=Speed Test Monitor
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/python3 $INSTALL_DIR/$PYTHON_SCRIPT --start-scheduler
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

        systemctl daemon-reload
        systemctl enable $SERVICE_NAME
        
        print_status "Systemd service created and enabled"
    else
        print_warning "Systemd not available, service not created"
    fi
}

# Create init script for OpenWrt
create_openwrt_service() {
    if [ "$SYSTEM" = "openwrt" ]; then
        print_status "Creating OpenWrt init script..."
        
        cat > /etc/init.d/$SERVICE_NAME << 'EOF'
#!/bin/sh /etc/rc.common

START=99
STOP=10

USE_PROCD=1
PROG="/usr/bin/python3"
ARGS="/opt/speedtest-monitor/speedtest_monitor.py --start-scheduler"

start_service() {
    procd_open_instance
    procd_set_param command $PROG $ARGS
    procd_set_param respawn
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}

stop_service() {
    killall python3 2>/dev/null || true
}
EOF

        chmod +x /etc/init.d/$SERVICE_NAME
        /etc/init.d/$SERVICE_NAME enable
        
        print_status "OpenWrt service created and enabled"
    fi
}

# Create cron job as backup
create_cron_job() {
    print_status "Creating cron job for daily reports..."
    
    # Remove existing cron job
    crontab -l 2>/dev/null | grep -v "speedtest-monitor\|speedtest_monitor" | crontab - 2>/dev/null || true
    
    # Add new cron job for 7 AM daily
    (crontab -l 2>/dev/null; echo "0 7 * * * $INSTALL_DIR/speedtest_monitor.py --daily-report >> /var/log/speedtest-monitor/cron.log 2>&1") | crontab -
    
    print_status "Cron job created for daily reports at 7:00 AM"
    print_status "Backup cron job ensures reports are sent even if service fails"
}

# Create configuration helper
create_config_helper() {
    print_status "Creating configuration helper script..."
    
    cat > $INSTALL_DIR/configure.sh << 'EOF'
#!/bin/bash

# Configuration helper for Speed Test Monitor

echo "Speed Test Monitor Configuration"
echo "================================"

# Check if config exists
if [ -f "speedtest_config.json" ]; then
    echo "Current configuration found:"
    cat speedtest_config.json | python3 -m json.tool 2>/dev/null || cat speedtest_config.json
    echo
    read -p "Do you want to reconfigure? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
fi

# Get Telegram configuration
echo "Please provide your Telegram Bot configuration:"
echo "1. Create a bot by messaging @BotFather on Telegram"
echo "2. Get your chat ID by messaging @userinfobot"
echo

read -p "Bot Token: " BOT_TOKEN
read -p "Chat ID: " CHAT_ID
read -p "Daily report time (HH:MM, default 07:00): " DAILY_TIME
DAILY_TIME=${DAILY_TIME:-07:00}

# Create configuration file
cat > speedtest_config.json << EOL
{
  "telegram": {
    "bot_token": "$BOT_TOKEN",
    "chat_id": "$CHAT_ID",
    "daily_time": "$DAILY_TIME"
  },
  "speedtest": {
    "server_id": null,
    "timeout": 60
  }
}
EOL

echo "Configuration saved to speedtest_config.json"

# Test Telegram connection
echo "Testing Telegram connection..."
python3 speedtest_monitor.py --test-telegram

echo "Configuration complete!"
echo "You can now:"
echo "- Run a test: python3 speedtest_monitor.py --run-test"
echo "- Start scheduler: python3 speedtest_monitor.py --start-scheduler"
echo "- Check status: python3 speedtest_monitor.py --status"
EOF

    chmod +x $INSTALL_DIR/configure.sh
}

# Create uninstall script
create_uninstall_script() {
    print_status "Creating uninstall script..."
    
    cat > $INSTALL_DIR/uninstall.sh << 'EOF'
#!/bin/bash

echo "Uninstalling Speed Test Monitor..."

# Stop and disable services
if command -v systemctl &> /dev/null; then
    systemctl stop speedtest-monitor 2>/dev/null || true
    systemctl disable speedtest-monitor 2>/dev/null || true
    rm -f /etc/systemd/system/speedtest-monitor.service
    systemctl daemon-reload
fi

# Stop OpenWrt service
if [ -f /etc/init.d/speedtest-monitor ]; then
    /etc/init.d/speedtest-monitor stop 2>/dev/null || true
    /etc/init.d/speedtest-monitor disable 2>/dev/null || true
    rm -f /etc/init.d/speedtest-monitor
fi

# Remove cron job
crontab -l 2>/dev/null | grep -v "speedtest-monitor" | crontab - 2>/dev/null || true

# Remove files
rm -rf /opt/speedtest-monitor
rm -f /usr/local/bin/speedtest-monitor
rm -rf /var/log/speedtest-monitor

echo "Speed Test Monitor uninstalled successfully"
EOF

    chmod +x $INSTALL_DIR/uninstall.sh
}

# Main installation function
main_install() {
    print_status "Starting installation..."
    
    detect_system
    install_dependencies
    create_directories
    install_python_script
    install_web_interface
    
    if [ "$SYSTEM" = "openwrt" ]; then
        create_openwrt_service
    else
        create_systemd_service
    fi
    
    create_cron_job
    create_config_helper
    create_uninstall_script
    
    print_status "Installation completed successfully!"
    echo
    echo -e "${GREEN}✅ Speed Test Monitor installed successfully!${NC}"
    echo
    echo -e "${BLUE}📁 Installation Details:${NC}"
    echo "- Installation directory: $INSTALL_DIR"
    echo "- Database: $INSTALL_DIR/speedtest_history.db"
    echo "- Logs: $INSTALL_DIR/speedtest.log"
    echo "- Configuration: $INSTALL_DIR/speedtest_config.json"
    
    if [ "$SYSTEM" = "openwrt" ]; then
        echo "- Command available: speedtest-monitor (via /usr/bin/)"
        echo "- Service: /etc/init.d/$SERVICE_NAME"
    else
        echo "- Command available: speedtest-monitor (via /usr/local/bin/)"
        echo "- Service: systemctl $SERVICE_NAME"
    fi
    
    echo
    echo -e "${YELLOW}🔧 Next steps:${NC}"
    echo "1. Configure Telegram bot:"
    echo "   cd $INSTALL_DIR && ./configure.sh"
    echo
    echo "2. Test the installation:"
    echo "   speedtest-monitor --run-test"
    echo "   # Or if command not found: $INSTALL_DIR/speedtest_monitor.py --run-test"
    echo
    echo "3. Test Telegram connection:"
    echo "   speedtest-monitor --test-telegram"
    echo
    echo "4. Check status:"
    echo "   speedtest-monitor --status"
    echo
    echo "5. Start the service:"
    
    if [ "$SYSTEM" = "openwrt" ]; then
        echo "   /etc/init.d/$SERVICE_NAME start"
        echo "   /etc/init.d/$SERVICE_NAME enable  # Auto-start on boot"
    elif command -v systemctl &> /dev/null; then
        echo "   systemctl start $SERVICE_NAME"
        echo "   systemctl enable $SERVICE_NAME  # Auto-start on boot"
    else
        echo "   speedtest-monitor --start-scheduler &"
    fi
    
    echo
    echo -e "${GREEN}📱 Telegram Bot Setup:${NC}"
    echo "1. Chat with @BotFather on Telegram"
    echo "2. Create new bot: /newbot"
    echo "3. Get Chat ID from @userinfobot"
    echo "4. Run: cd $INSTALL_DIR && ./configure.sh"
    echo
    echo -e "${BLUE}📊 Daily reports will be sent at 7:00 AM automatically!${NC}"
    
    # Test if command works
    echo
    print_status "Testing command availability..."
    if command -v speedtest-monitor &> /dev/null; then
        echo -e "${GREEN}✅ speedtest-monitor command is available${NC}"
    else
        print_warning "speedtest-monitor command not found in PATH"
        echo "Use direct path: $INSTALL_DIR/speedtest_monitor.py"
        
        # Try to fix PATH issue
        if [ "$SYSTEM" = "openwrt" ]; then
            print_status "Creating alternative wrapper script..."
            cat > /usr/bin/speedtest-monitor << EOF
#!/bin/sh
exec /usr/bin/python3 $INSTALL_DIR/speedtest_monitor.py "\$@"
EOF
            chmod +x /usr/bin/speedtest-monitor
            
            if command -v speedtest-monitor &> /dev/null; then
                echo -e "${GREEN}✅ Fixed: speedtest-monitor command now available${NC}"
            fi
        fi
    fi
}

# Run installation
main_install
