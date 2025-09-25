#!/usr/bin/env python3
"""
Enhanced OpenWrt Data Usage Monitor Script - Robust Configuration Handling
"""

import json
import subprocess
import urllib.request
import urllib.parse
import urllib.error
import time
from datetime import datetime, timedelta
import os
import sys

class Config:
    def __init__(self):
        # Telegram Bot Configuration
        self.TELEGRAM_BOT_TOKEN = os.getenv('TELEGRAM_BOT_TOKEN', 'YOUR_BOT_TOKEN_HERE')
        self.TELEGRAM_CHAT_ID = os.getenv('TELEGRAM_CHAT_ID', 'YOUR_CHAT_ID_HERE')
        
        # Network interface to monitor
        self.INTERFACE = os.getenv('NETWORK_INTERFACE', 'wwan0')
        
        # Current monitoring period
        self.START_DATE = os.getenv('START_DATE', '12-09-2025')
        
        # Previous period tracking - with robust handling
        self.PREV_PERIOD_START = os.getenv('PREV_PERIOD_START', '').strip()
        self.PREV_PERIOD_END = os.getenv('PREV_PERIOD_END', '').strip()
        
        # Handle PREV_PERIOD_TOTAL safely
        prev_total_str = os.getenv('PREV_PERIOD_TOTAL', '0').strip()
        try:
            self.PREV_PERIOD_TOTAL = float(prev_total_str) if prev_total_str else 0.0
        except ValueError:
            print(f"Warning: Invalid PREV_PERIOD_TOTAL value '{prev_total_str}', using 0.0")
            self.PREV_PERIOD_TOTAL = 0.0

def log_message(message):
    """Simple logging function"""
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    log_entry = f"[{timestamp}] {message}"
    print(log_entry)
    
    # Write to log file
    try:
        with open('/tmp/data_usage_monitor.log', 'a') as f:
            f.write(log_entry + '\n')
    except Exception as e:
        print(f"Log write error: {e}")

class DataUsageMonitor:
    def __init__(self, config):
        self.config = config
        
    def get_vnstat_data(self):
        """Get vnstat data in JSON format - compatible with vnstat2"""
        try:
            # Try vnstat2 format first
            cmd = ['vnstat', '-i', self.config.INTERFACE, '--json']
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
            
            if result.returncode != 0:
                log_message(f"vnstat command failed with return code {result.returncode}")
                # Try alternative vnstat command
                cmd = ['vnstat', '-i', self.config.INTERFACE, '-d', '--json']
                result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
                
                if result.returncode != 0:
                    log_message("Both vnstat commands failed")
                    return None
            
            # Parse JSON
            try:
                data = json.loads(result.stdout)
                log_message("Successfully parsed vnstat JSON data")
                return data
            except json.JSONDecodeError as e:
                log_message(f"JSON decode error: {e}")
                return None
                
        except subprocess.TimeoutExpired:
            log_message("vnstat command timed out")
            return None
        except Exception as e:
            log_message(f"Error running vnstat: {e}")
            return None
    
    def calculate_usage_between_dates(self, start_date, end_date):
        """Calculate usage between two specific dates"""
        try:
            # Parse dates
            start_day, start_month, start_year = map(int, start_date.split('-'))
            end_day, end_month, end_year = map(int, end_date.split('-'))
            
            start_dt = datetime(start_year, start_month, start_day)
            end_dt = datetime(end_year, end_month, end_day)
            
            vnstat_data = self.get_vnstat_data()
            
            if not vnstat_data:
                log_message("No vnstat data available")
                return None
            
            # Handle different vnstat JSON structures
            interfaces_data = None
            
            if 'interfaces' in vnstat_data:
                interfaces_data = vnstat_data['interfaces']
            elif isinstance(vnstat_data, list) and len(vnstat_data) > 0:
                interfaces_data = vnstat_data
            else:
                log_message(f"Unknown vnstat data structure: {list(vnstat_data.keys())}")
                return None
            
            if not interfaces_data:
                log_message("No interfaces found in vnstat data")
                return None
            
            # Get matching interface
            interface_data = None
            for iface in interfaces_data:
                if 'name' in iface and iface['name'] == self.config.INTERFACE:
                    interface_data = iface
                    break
            
            if not interface_data and interfaces_data:
                interface_data = interfaces_data[0]
            
            if not interface_data:
                log_message("No matching interface data found")
                return None
            
            # Get daily traffic data
            daily_data = None
            if 'traffic' in interface_data and 'days' in interface_data['traffic']:
                daily_data = interface_data['traffic']['days']
            elif 'traffic' in interface_data and 'day' in interface_data['traffic']:
                daily_data = interface_data['traffic']['day']
            elif 'days' in interface_data:
                daily_data = interface_data['days']
            
            if not daily_data:
                log_message(f"No daily data found in interface.")
                return None
            
            total_bytes = 0
            days_counted = 0
            
            for day_data in daily_data:
                try:
                    # Handle different date formats
                    if 'date' in day_data:
                        date_info = day_data['date']
                        day_dt = datetime(date_info['year'], date_info['month'], date_info['day'])
                    elif 'id' in day_data:
                        day_dt = datetime.strptime(day_data['id'], '%Y-%m-%d')
                    else:
                        continue
                    
                    # Only count days within the specified range (inclusive)
                    if start_dt <= day_dt <= end_dt:
                        rx_bytes = day_data.get('rx', 0)
                        tx_bytes = day_data.get('tx', 0)
                        total_bytes += rx_bytes + tx_bytes
                        days_counted += 1
                        
                except (ValueError, KeyError) as e:
                    log_message(f"Error processing day data: {e}")
                    continue
            
            log_message(f"Calculated usage for {days_counted} days between {start_date} and {end_date}")
            
            # Convert bytes to GB
            total_gb = total_bytes / (1024 * 1024 * 1024)
            return total_gb
            
        except Exception as e:
            log_message(f"Error calculating usage between dates: {e}")
            return None
    
    def calculate_usage_since_date(self, start_date):
        """Calculate total data usage since start_date with daily breakdown"""
        try:
            # Parse start date
            day, month, year = map(int, start_date.split('-'))
            start_dt = datetime(year, month, day)
            
            vnstat_data = self.get_vnstat_data()
            
            if not vnstat_data:
                log_message("No vnstat data available")
                return None, []
            
            # Handle different vnstat JSON structures
            interfaces_data = None
            
            if 'interfaces' in vnstat_data:
                interfaces_data = vnstat_data['interfaces']
            elif isinstance(vnstat_data, list) and len(vnstat_data) > 0:
                interfaces_data = vnstat_data
            else:
                log_message(f"Unknown vnstat data structure: {list(vnstat_data.keys())}")
                return None, []
            
            if not interfaces_data:
                log_message("No interfaces found in vnstat data")
                return None, []
            
            # Get matching interface
            interface_data = None
            for iface in interfaces_data:
                if 'name' in iface and iface['name'] == self.config.INTERFACE:
                    interface_data = iface
                    break
            
            if not interface_data and interfaces_data:
                interface_data = interfaces_data[0]
            
            if not interface_data:
                log_message("No matching interface data found")
                return None, []
            
            # Get daily traffic data
            daily_data = None
            if 'traffic' in interface_data and 'days' in interface_data['traffic']:
                daily_data = interface_data['traffic']['days']
            elif 'traffic' in interface_data and 'day' in interface_data['traffic']:
                daily_data = interface_data['traffic']['day']
            elif 'days' in interface_data:
                daily_data = interface_data['days']
            
            if not daily_data:
                log_message(f"No daily data found in interface.")
                return None, []
            
            total_bytes = 0
            daily_breakdown = []
            
            # Sort daily data by date
            sorted_daily_data = []
            for day_data in daily_data:
                try:
                    # Handle different date formats
                    if 'date' in day_data:
                        date_info = day_data['date']
                        day_dt = datetime(date_info['year'], date_info['month'], date_info['day'])
                    elif 'id' in day_data:
                        day_dt = datetime.strptime(day_data['id'], '%Y-%m-%d')
                    else:
                        continue
                    
                    sorted_daily_data.append((day_dt, day_data))
                    
                except (ValueError, KeyError) as e:
                    log_message(f"Error processing day data: {e}")
                    continue
            
            # Sort by date
            sorted_daily_data.sort(key=lambda x: x[0])
            
            days_counted = 0
            for day_dt, day_data in sorted_daily_data:
                # Only count days from start_date onwards
                if day_dt >= start_dt:
                    rx_bytes = day_data.get('rx', 0)
                    tx_bytes = day_data.get('tx', 0)
                    day_total_bytes = rx_bytes + tx_bytes
                    day_total_gb = day_total_bytes / (1024 * 1024 * 1024)
                    
                    total_bytes += day_total_bytes
                    days_counted += 1
                    
                    daily_breakdown.append({
                        'date': day_dt.strftime('%d-%m-%Y'),
                        'usage_gb': day_total_gb,
                        'day_number': days_counted
                    })
            
            log_message(f"Processed {days_counted} days of data since {start_date}")
            
            # Convert bytes to GB
            total_gb = total_bytes / (1024 * 1024 * 1024)
            return total_gb, daily_breakdown
            
        except ValueError as e:
            log_message(f"Error parsing date: {e}")
            return None, []
        except Exception as e:
            log_message(f"Error calculating usage: {e}")
            return None, []
    
    def calculate_days_between(self, start_date, end_date):
        """Calculate number of days between two dates (inclusive)"""
        try:
            # Parse start date
            start_day, start_month, start_year = map(int, start_date.split('-'))
            # Parse end date  
            end_day, end_month, end_year = map(int, end_date.split('-'))
            
            start_dt = datetime(start_year, start_month, start_day)
            end_dt = datetime(end_year, end_month, end_day)
            
            # Calculate days (inclusive)
            days = (end_dt - start_dt).days + 1
            
            # Debug logging
            log_message(f"Days calculation: {start_date} to {end_date} = {days} days")
            
            return days
        except Exception as e:
            log_message(f"Error calculating days between {start_date} and {end_date}: {e}")
            return 0
    
    def get_accurate_previous_period_data(self):
        """Get accurate previous period data from vnstat"""
        if not self.config.PREV_PERIOD_START or not self.config.PREV_PERIOD_END:
            return None, 0
            
        # Calculate actual usage from vnstat data
        actual_usage = self.calculate_usage_between_dates(
            self.config.PREV_PERIOD_START, 
            self.config.PREV_PERIOD_END
        )
        
        if actual_usage is not None:
            log_message(f"Actual previous period usage from vnstat: {actual_usage:.2f} GB")
            return actual_usage, self.calculate_days_between(self.config.PREV_PERIOD_START, self.config.PREV_PERIOD_END)
        else:
            # Fallback to configured value
            log_message(f"Using configured previous period usage: {self.config.PREV_PERIOD_TOTAL:.2f} GB")
            return self.config.PREV_PERIOD_TOTAL, self.calculate_days_between(self.config.PREV_PERIOD_START, self.config.PREV_PERIOD_END)
    
    def format_enhanced_report(self, total_gb, daily_breakdown, start_date, end_date):
        """Format the enhanced usage report with daily breakdown and previous period info"""
        
        # Calculate current period days
        current_days = self.calculate_days_between(start_date, end_date)
        
        # Build daily breakdown text
        daily_text = ""
        if daily_breakdown:
            for i, day in enumerate(daily_breakdown, 1):
                daily_text += f"         {i}. {day['usage_gb']:.2f} GB ({day['date']})\n"
            daily_text = daily_text.rstrip('\n')
        else:
            daily_text = "         (No daily data available)"
        
        # Previous period info - get accurate data
        prev_period_text = ""
        if self.config.PREV_PERIOD_START and self.config.PREV_PERIOD_END:
            prev_usage, prev_days = self.get_accurate_previous_period_data()
            if prev_usage > 0:
                prev_period_text = f"""
ðŸ“ˆ *Previous Period:*
ðŸ—“ï¸ Period: {self.config.PREV_PERIOD_START} â†’ {self.config.PREV_PERIOD_END} ({prev_days} hari)
ðŸ“Š Total Usage: {prev_usage:.2f} GB
â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”"""
        
        report = f"""ðŸ“Š *Data Usage Report*
â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”
ðŸŒ Interface: `{self.config.INTERFACE}`
ðŸ“… Period: {start_date} â†’ {end_date} ({current_days} hari)
â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”{prev_period_text}

ðŸ”¥ *Current Period Usage:*
ðŸ“ˆ Daily Breakdown:
{daily_text}
         â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
         Total: *{total_gb:.2f} GB*
â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”

â° Report: {datetime.now().strftime('%d-%m-%Y %H:%M:%S')}"""
        return report
    
    def send_telegram_message(self, message):
        """Send message to Telegram bot using urllib"""
        try:
            url = f"https://api.telegram.org/bot{self.config.TELEGRAM_BOT_TOKEN}/sendMessage"
            
            data = {
                'chat_id': self.config.TELEGRAM_CHAT_ID,
                'text': message,
                'parse_mode': 'Markdown'
            }
            
            # Encode data
            encoded_data = urllib.parse.urlencode(data).encode('utf-8')
            
            # Create request
            req = urllib.request.Request(url, data=encoded_data, method='POST')
            req.add_header('Content-Type', 'application/x-www-form-urlencoded')
            
            # Send request
            with urllib.request.urlopen(req, timeout=15) as response:
                if response.status == 200:
                    log_message("âœ… Message sent successfully to Telegram")
                    return True
                else:
                    log_message(f"âŒ Telegram API returned status {response.status}")
                    return False
                    
        except urllib.error.URLError as e:
            log_message(f"âŒ Network error sending Telegram message: {e}")
            return False
        except Exception as e:
            log_message(f"âŒ Unexpected error sending message: {e}")
            return False
    
    def test_vnstat(self):
        """Test vnstat command and show data structure"""
        log_message("Testing vnstat command...")
        data = self.get_vnstat_data()
        if data:
            log_message("âœ… vnstat data retrieved successfully")
            return True
        else:
            log_message("âŒ Failed to get vnstat data")
            return False
    
    def generate_and_send_report(self):
        """Generate usage report and send to Telegram"""
        try:
            today_date = datetime.now().strftime('%d-%m-%Y')
            
            # Test vnstat first
            if not self.test_vnstat():
                error_msg = f"âŒ vnstat test failed for {today_date}"
                log_message(error_msg)
                self.send_telegram_message(error_msg)
                return False
            
            total_gb, daily_breakdown = self.calculate_usage_since_date(self.config.START_DATE)
            
            if total_gb is None:
                error_msg = f"âŒ Error calculating data usage for {today_date}"
                log_message(error_msg)
                self.send_telegram_message(error_msg)
                return False
            
            report = self.format_enhanced_report(total_gb, daily_breakdown, self.config.START_DATE, today_date)
            success = self.send_telegram_message(report)
            
            if success:
                log_message(f"âœ… Report sent successfully. Usage: {total_gb:.2f} GB, Days: {len(daily_breakdown)}")
            
            return success
            
        except Exception as e:
            log_message(f"âŒ Error in generate_and_send_report: {e}")
            return False

def main():
    """Main function"""
    config = Config()
    monitor = DataUsageMonitor(config)
    
    # Validate configuration
    if config.TELEGRAM_BOT_TOKEN == 'YOUR_BOT_TOKEN_HERE':
        log_message("âŒ ERROR: Please set TELEGRAM_BOT_TOKEN in /etc/config/data-monitor")
        sys.exit(1)
    
    if config.TELEGRAM_CHAT_ID == 'YOUR_CHAT_ID_HERE':
        log_message("âŒ ERROR: Please set TELEGRAM_CHAT_ID in /etc/config/data-monitor")
        sys.exit(1)
    
    log_message("ðŸš€ Starting Enhanced Data Usage Monitor (Robust)")
    log_message(f"ðŸ“¡ Interface: {config.INTERFACE}")
    log_message(f"ðŸ“… Start Date: {config.START_DATE}")
    if config.PREV_PERIOD_START and config.PREV_PERIOD_END:
        log_message(f"ðŸ“‹ Previous Period: {config.PREV_PERIOD_START} â†’ {config.PREV_PERIOD_END}")
        log_message(f"ðŸ“Š Previous Period Total: {config.PREV_PERIOD_TOTAL} GB")
        # Test calculation
        days = monitor.calculate_days_between(config.PREV_PERIOD_START, config.PREV_PERIOD_END)
        log_message(f"ðŸ“… Previous Period Days: {days}")
    
    # Generate and send report
    success = monitor.generate_and_send_report()
    
    if success:
        log_message("âœ… Enhanced report completed successfully")
        sys.exit(0)
    else:
        log_message("âŒ Report failed")
        sys.exit(1)

if __name__ == "__main__":
    main()
