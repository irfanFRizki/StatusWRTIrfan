#!/bin/sh
#
# sysinfo.sh - OpenWRT System Information Script
# Menampilkan informasi CPU, RAM, Temperature, Load Average, dll
# Mendukung output untuk terminal (dengan colors) dan plain text untuk bot
#

# Check if output should be plain text (no colors)
# Jika dipanggil dengan parameter --plain atau dari script lain
if [ "$1" = "--plain" ] || [ -z "$TERM" ] || [ "$TERM" = "dumb" ]; then
    PLAIN_OUTPUT=1
else
    PLAIN_OUTPUT=0
fi

# Colors untuk terminal (hanya jika bukan plain output)
if [ $PLAIN_OUTPUT -eq 0 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    NC=''
fi

# Banner
echo ""
echo "=========================================="
echo "   OpenWRT System Information"
echo "=========================================="
echo ""

# ==========================================
# HOSTNAME & UPTIME
# ==========================================
echo "${CYAN}=== System Info ===${NC}"
HOSTNAME=$(uname -n)
UPTIME=$(uptime | awk -F'up ' '{print $2}' | awk -F',' '{print $1}')
echo "Hostname    : ${HOSTNAME}"
echo "Uptime      : ${UPTIME}"
echo ""

# ==========================================
# CPU TEMPERATURE
# ==========================================
echo "${CYAN}=== CPU Temperature ===${NC}"

# Try multiple methods to get temperature
TEMP_RAW=""

# Method 1: thermal_zone0 (Raspberry Pi)
if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
    TEMP_RAW=$(cat /sys/class/thermal/thermal_zone0/temp)
    TEMP=$(awk "BEGIN {printf \"%.1f\", $TEMP_RAW/1000}")
    
    # Color based on temperature
    if [ $(echo "$TEMP > 70" | bc -l 2>/dev/null || echo 0) -eq 1 ]; then
        TEMP_COLOR=$RED
    elif [ $(echo "$TEMP > 60" | bc -l 2>/dev/null || echo 0) -eq 1 ]; then
        TEMP_COLOR=$YELLOW
    else
        TEMP_COLOR=$GREEN
    fi
    
    echo "CPU Temp    : ${TEMP_COLOR}${TEMP}°C${NC}"

# Method 2: hwmon (some devices)
elif [ -f /sys/class/hwmon/hwmon0/temp1_input ]; then
    TEMP_RAW=$(cat /sys/class/hwmon/hwmon0/temp1_input)
    TEMP=$(awk "BEGIN {printf \"%.1f\", $TEMP_RAW/1000}")
    echo "CPU Temp    : ${GREEN}${TEMP}°C${NC}"

# Method 3: Try sensors command if available
elif command -v sensors >/dev/null 2>&1; then
    TEMP=$(sensors | grep -i 'core 0' | awk '{print $3}' | sed 's/+//;s/°C//')
    if [ -n "$TEMP" ]; then
        echo "CPU Temp    : ${GREEN}${TEMP}°C${NC}"
    else
        echo "CPU Temp    : N/A"
    fi
else
    echo "CPU Temp    : N/A"
fi
echo ""

# ==========================================
# CPU USAGE
# ==========================================
echo "${CYAN}=== CPU Usage ===${NC}"

# Get CPU usage using top (more accurate)
CPU_USAGE=$(top -bn1 | grep '^CPU:' | sed 's/CPU://g' | awk '{print $1}' | sed 's/%//')

if [ -z "$CPU_USAGE" ]; then
    # Fallback method using /proc/stat
    CPU_LINE1=$(cat /proc/stat | grep '^cpu ')
    sleep 0.5
    CPU_LINE2=$(cat /proc/stat | grep '^cpu ')
    
    IDLE1=$(echo $CPU_LINE1 | awk '{print $5}')
    IDLE2=$(echo $CPU_LINE2 | awk '{print $5}')
    
    TOTAL1=$(echo $CPU_LINE1 | awk '{print $2+$3+$4+$5+$6+$7+$8}')
    TOTAL2=$(echo $CPU_LINE2 | awk '{print $2+$3+$4+$5+$6+$7+$8}')
    
    IDLE_DELTA=$((IDLE2 - IDLE1))
    TOTAL_DELTA=$((TOTAL2 - TOTAL1))
    
    if [ $TOTAL_DELTA -gt 0 ]; then
        CPU_USAGE=$(awk "BEGIN {printf \"%.1f\", 100 * (1 - $IDLE_DELTA / $TOTAL_DELTA)}")
    else
        CPU_USAGE="0.0"
    fi
fi

# Color based on CPU usage
CPU_USAGE_INT=$(echo $CPU_USAGE | cut -d. -f1)
if [ $CPU_USAGE_INT -gt 80 ]; then
    CPU_COLOR=$RED
elif [ $CPU_USAGE_INT -gt 60 ]; then
    CPU_COLOR=$YELLOW
else
    CPU_COLOR=$GREEN
fi

echo "CPU Usage   : ${CPU_COLOR}${CPU_USAGE}%${NC}"
echo ""

# ==========================================
# LOAD AVERAGE
# ==========================================
echo "${CYAN}=== Load Average ===${NC}"
LOAD=$(cat /proc/loadavg | awk '{print $1, $2, $3}')
LOAD1=$(echo $LOAD | awk '{print $1}')
LOAD5=$(echo $LOAD | awk '{print $2}')
LOAD15=$(echo $LOAD | awk '{print $3}')

echo "1 min       : ${LOAD1}"
echo "5 min       : ${LOAD5}"
echo "15 min      : ${LOAD15}"
echo ""

# ==========================================
# CPU INFO
# ==========================================
echo "${CYAN}=== CPU Info ===${NC}"

# Get CPU model
CPU_MODEL=$(cat /proc/cpuinfo | grep 'model name' | head -1 | cut -d: -f2 | sed 's/^[ \t]*//')
if [ -z "$CPU_MODEL" ]; then
    CPU_MODEL=$(cat /proc/cpuinfo | grep 'Processor' | head -1 | cut -d: -f2 | sed 's/^[ \t]*//')
fi

# Get CPU cores
CPU_CORES=$(grep -c ^processor /proc/cpuinfo)

# Get CPU frequency
CPU_FREQ=""
if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq ]; then
    FREQ_KHZ=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq)
    CPU_FREQ=$(awk "BEGIN {printf \"%.0f MHz\", $FREQ_KHZ/1000}")
elif [ -f /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_cur_freq ]; then
    FREQ_KHZ=$(cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_cur_freq)
    CPU_FREQ=$(awk "BEGIN {printf \"%.0f MHz\", $FREQ_KHZ/1000}")
else
    # Try to get from cpuinfo
    CPU_FREQ=$(cat /proc/cpuinfo | grep 'cpu MHz' | head -1 | awk '{printf "%.0f MHz", $4}')
fi

if [ -n "$CPU_MODEL" ]; then
    echo "CPU Model   : ${CPU_MODEL}"
fi
echo "CPU Cores   : ${CPU_CORES}"
if [ -n "$CPU_FREQ" ]; then
    echo "CPU Freq    : ${CPU_FREQ}"
fi
echo ""

# ==========================================
# MEMORY (RAM)
# ==========================================
echo "${CYAN}=== Memory (RAM) ===${NC}"

# Parse /proc/meminfo
MEM_TOTAL=$(grep MemTotal /proc/meminfo | awk '{print $2}')
MEM_FREE=$(grep MemFree /proc/meminfo | awk '{print $2}')
MEM_AVAILABLE=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
MEM_BUFFERS=$(grep Buffers /proc/meminfo | awk '{print $2}')
MEM_CACHED=$(grep '^Cached:' /proc/meminfo | awk '{print $2}')

# Calculate used memory
MEM_USED=$((MEM_TOTAL - MEM_FREE - MEM_BUFFERS - MEM_CACHED))

# Convert to MB
MEM_TOTAL_MB=$((MEM_TOTAL / 1024))
MEM_USED_MB=$((MEM_USED / 1024))
MEM_FREE_MB=$((MEM_FREE / 1024))
MEM_AVAILABLE_MB=$((MEM_AVAILABLE / 1024))

# Calculate percentage
if [ $MEM_TOTAL -gt 0 ]; then
    MEM_USAGE_PCT=$(awk "BEGIN {printf \"%.1f\", ($MEM_USED / $MEM_TOTAL) * 100}")
else
    MEM_USAGE_PCT="0.0"
fi

# Color based on memory usage
MEM_USAGE_INT=$(echo $MEM_USAGE_PCT | cut -d. -f1)
if [ $MEM_USAGE_INT -gt 90 ]; then
    MEM_COLOR=$RED
elif [ $MEM_USAGE_INT -gt 75 ]; then
    MEM_COLOR=$YELLOW
else
    MEM_COLOR=$GREEN
fi

echo "RAM Total   : ${MEM_TOTAL_MB} MB"
echo "RAM Used    : ${MEM_COLOR}${MEM_USED_MB} MB (${MEM_USAGE_PCT}%)${NC}"
echo "RAM Free    : ${MEM_FREE_MB} MB"
echo "RAM Available: ${MEM_AVAILABLE_MB} MB"
echo ""

# ==========================================
# SWAP
# ==========================================
SWAP_TOTAL=$(grep SwapTotal /proc/meminfo | awk '{print $2}')
SWAP_FREE=$(grep SwapFree /proc/meminfo | awk '{print $2}')
SWAP_USED=$((SWAP_TOTAL - SWAP_FREE))

if [ $SWAP_TOTAL -gt 0 ]; then
    echo "${CYAN}=== Swap ===${NC}"
    SWAP_TOTAL_MB=$((SWAP_TOTAL / 1024))
    SWAP_USED_MB=$((SWAP_USED / 1024))
    SWAP_FREE_MB=$((SWAP_FREE / 1024))
    SWAP_USAGE_PCT=$(awk "BEGIN {printf \"%.1f\", ($SWAP_USED / $SWAP_TOTAL) * 100}")
    
    echo "Swap Total  : ${SWAP_TOTAL_MB} MB"
    echo "Swap Used   : ${SWAP_USED_MB} MB (${SWAP_USAGE_PCT}%)"
    echo "Swap Free   : ${SWAP_FREE_MB} MB"
    echo ""
fi

# ==========================================
# DISK USAGE (Top 5 only untuk menghindari output terlalu panjang)
# ==========================================
echo "${CYAN}=== Disk Usage ===${NC}"

# Get disk usage for root and other mounted partitions
df -h | grep -E '^/dev/' | head -5 | while read line; do
    DEVICE=$(echo $line | awk '{print $1}')
    SIZE=$(echo $line | awk '{print $2}')
    USED=$(echo $line | awk '{print $3}')
    AVAIL=$(echo $line | awk '{print $4}')
    USAGE=$(echo $line | awk '{print $5}' | sed 's/%//')
    MOUNT=$(echo $line | awk '{print $6}')
    
    # Color based on usage
    if [ $USAGE -gt 90 ]; then
        DISK_COLOR=$RED
    elif [ $USAGE -gt 75 ]; then
        DISK_COLOR=$YELLOW
    else
        DISK_COLOR=$GREEN
    fi
    
    echo "${DEVICE} (${MOUNT})"
    echo "  Size      : ${SIZE}"
    echo "  Used      : ${DISK_COLOR}${USED} (${USAGE}%)${NC}"
    echo "  Available : ${AVAIL}"
    echo ""
done

# ==========================================
# NETWORK INTERFACES (Top 5 active interfaces only)
# ==========================================
echo "${CYAN}=== Network Interfaces ===${NC}"

# Only show UP interfaces or interfaces with traffic
ip -br addr | grep -v '^lo' | while read line; do
    IFACE=$(echo $line | awk '{print $1}')
    STATE=$(echo $line | awk '{print $2}')
    IP=$(echo $line | awk '{print $3}' | cut -d'/' -f1)
    
    # Skip DOWN interfaces without traffic
    if [ "$STATE" = "DOWN" ]; then
        if [ -f /sys/class/net/$IFACE/statistics/rx_bytes ]; then
            RX_BYTES=$(cat /sys/class/net/$IFACE/statistics/rx_bytes)
            TX_BYTES=$(cat /sys/class/net/$IFACE/statistics/tx_bytes)
            TOTAL_BYTES=$((RX_BYTES + TX_BYTES))
            
            # Skip if no traffic
            if [ $TOTAL_BYTES -lt 1000 ]; then
                continue
            fi
        else
            continue
        fi
    fi
    
    if [ "$STATE" = "UP" ]; then
        STATE_COLOR=$GREEN
    else
        STATE_COLOR=$RED
    fi
    
    echo "${IFACE}"
    echo "  State     : ${STATE_COLOR}${STATE}${NC}"
    if [ -n "$IP" ] && [ "$IP" != "" ]; then
        # Remove IPv6 for cleaner output
        if echo "$IP" | grep -q ":"; then
            continue
        fi
        echo "  IP        : ${IP}"
    fi
    
    # Get RX/TX bytes if available
    if [ -f /sys/class/net/$IFACE/statistics/rx_bytes ]; then
        RX_BYTES=$(cat /sys/class/net/$IFACE/statistics/rx_bytes)
        TX_BYTES=$(cat /sys/class/net/$IFACE/statistics/tx_bytes)
        
        # Convert to human readable
        RX_MB=$(awk "BEGIN {printf \"%.2f\", $RX_BYTES/1024/1024}")
        TX_MB=$(awk "BEGIN {printf \"%.2f\", $TX_BYTES/1024/1024}")
        
        echo "  RX        : ${RX_MB} MB"
        echo "  TX        : ${TX_MB} MB"
    fi
    echo ""
done | head -40  # Limit output

# ==========================================
# SYSTEM TIME
# ==========================================
echo "${CYAN}=== System Time ===${NC}"
DATE=$(date '+%Y-%m-%d %H:%M:%S %Z')
echo "Current Time: ${DATE}"
echo ""

echo "=========================================="
echo ""