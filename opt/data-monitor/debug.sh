#!/bin/sh
echo "======================================"
echo "   Debug Information"
echo "======================================"

echo "📋 System Information:"
cat /etc/openwrt_release 2>/dev/null || echo "Not OpenWrt or file missing"
echo

echo "🐍 Python Information:"
python3 --version
python3 -c "import sys; print('Python path:', sys.path)"
echo

echo "📡 vnstat Information:"
vnstat --version
echo "Available interfaces:"
vnstat --iflist 2>/dev/null || ip link show
echo

echo "🌐 Network Interfaces:"
ip addr show | grep "inet " | head -5

echo "📊 Sample vnstat output:"
vnstat -i wwan0 --json 2>/dev/null | head -20 || echo "vnstat JSON failed"

echo "📁 Files check:"
ls -la /opt/data-monitor/
ls -la /etc/config/data-monitor

echo "⏰ Cron jobs:"
cat /etc/crontabs/root 2>/dev/null | grep data-monitor || echo "No cron job found"

echo "📝 Recent logs:"
tail -10 /tmp/data_usage_monitor.log 2>/dev/null || echo "No log file yet"

echo "🧮 Testing date calculation:"
. /etc/config/data-monitor
if [ -n "$PREV_PERIOD_START" ] && [ -n "$PREV_PERIOD_END" ]; then
    echo "Previous period: $PREV_PERIOD_START to $PREV_PERIOD_END"
    python3 -c "
from datetime import datetime
try:
    start = datetime.strptime('$PREV_PERIOD_START', '%d-%m-%Y')
    end = datetime.strptime('$PREV_PERIOD_END', '%d-%m-%Y')
    days = (end - start).days + 1
    print(f'Calculated days: {days}')
except Exception as e:
    print(f'Error: {e}')
    "
else
    echo "No previous period dates configured"
fi
