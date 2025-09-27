#!/bin/sh
# Data Monitor Report Script v3.2 - Final Fix with Note Support
CONFIG_FILE="/etc/config/data-monitor"
LOG_FILE="/tmp/data-monitor.log"

# Load configuration
if [ -f "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
else
    echo "⚠ Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Function to convert DD-MM-YYYY to YYYY-MM-DD
convert_date_format() {
    local date_str="$1"
    echo "$date_str" | awk -F'-' '{printf "%s-%02d-%02d", $3, $2, $1}'
}

# Function to calculate days between dates
calculate_days_between() {
    local start_date="$1"
    local end_date="$2"
    
    local start_conv=$(convert_date_format "$start_date")
    local end_conv=$(convert_date_format "$end_date")
    
    local start_epoch=$(date -d "$start_conv" +%s 2>/dev/null || echo "0")
    local end_epoch=$(date -d "$end_conv" +%s 2>/dev/null || echo "0")
    
    if [ "$start_epoch" -eq 0 ] || [ "$end_epoch" -eq 0 ]; then
        echo "0"
    else
        local diff_seconds=$((end_epoch - start_epoch))
        local diff_days=$((diff_seconds / 86400 + 1))
        echo "$diff_days"
    fi
}

# Function to get current date
get_current_date() {
    date +%d-%m-%Y
}

# Function to get 3ginfo technical data
get_3ginfo_data() {
    local temp_file="/tmp/3ginfo_output.json"
    
    # Detect running services
    SERVICE_INFO=""
    
    # Check OpenClash
    if [ -x "/etc/init.d/openclash" ]; then
        local openclash_status=$(/etc/init.d/openclash status 2>/dev/null | grep -E "(running|active)" | head -1)
        if [ -n "$openclash_status" ]; then
            SERVICE_INFO="OpenClash"
        fi
    fi
    
    # Check Nikki service
    if [ -z "$SERVICE_INFO" ] && [ -x "/etc/init.d/nikki" ]; then
        local nikki_status=$(/etc/init.d/nikki status 2>/dev/null | grep -E "(running|active)" | head -1)
        if [ -n "$nikki_status" ]; then
            SERVICE_INFO="Nikki"
        fi
    fi
    
    # Check other common services if OpenClash and Nikki are not running
    if [ -z "$SERVICE_INFO" ]; then
        # Check PassWall
        if [ -x "/etc/init.d/passwall" ]; then
            local passwall_status=$(/etc/init.d/passwall status 2>/dev/null | grep -E "(running|active)" | head -1)
            if [ -n "$passwall_status" ]; then
                SERVICE_INFO="PassWall"
            fi
        fi
        
        # Check ShadowSocksR Plus
        if [ -z "$SERVICE_INFO" ] && [ -x "/etc/init.d/shadowsocksr" ]; then
            local ssr_status=$(/etc/init.d/shadowsocksr status 2>/dev/null | grep -E "(running|active)" | head -1)
            if [ -n "$ssr_status" ]; then
                SERVICE_INFO="ShadowSocksR"
            fi
        fi
        
        # Check V2Ray
        if [ -z "$SERVICE_INFO" ] && [ -x "/etc/init.d/v2ray" ]; then
            local v2ray_status=$(/etc/init.d/v2ray status 2>/dev/null | grep -E "(running|active)" | head -1)
            if [ -n "$v2ray_status" ]; then
                SERVICE_INFO="V2Ray"
            fi
        fi
    fi
    
    # Default if no service detected
    if [ -z "$SERVICE_INFO" ]; then
        SERVICE_INFO="Default"
    fi
    
    # Run 3ginfo script and capture output
    if [ -x "/usr/share/3ginfo-lite/3ginfo.sh" ]; then
        sh /usr/share/3ginfo-lite/3ginfo.sh > "$temp_file" 2>/dev/null
        
        if [ -f "$temp_file" ]; then
            # Extract data from JSON output
            MODEM_BAND=$(grep '"mode":' "$temp_file" | sed 's/.*"mode":"\([^"]*\)".*/\1/' 2>/dev/null || echo "-")
            EARFCN_INFO=$(grep '"earfcn":' "$temp_file" | sed 's/.*"earfcn":"\([^"]*\)".*/\1/' 2>/dev/null || echo "-")
            ENB_PCI=$(grep '"pci":' "$temp_file" | sed 's/.*"pci":"\([^"]*\)".*/\1/' 2>/dev/null || echo "-")
            SINR_INFO=$(grep '"sinr":' "$temp_file" | sed 's/.*"sinr":"\([^"]*\)".*/\1/' 2>/dev/null || echo "-")
            TEMP_INFO=$(grep '"mtemp":' "$temp_file" | sed 's/.*"mtemp":"\([^"]*\)".*/\1/' 2>/dev/null || echo "-")
            OPERATOR_NAME=$(grep '"operator_name":' "$temp_file" | sed 's/.*"operator_name":"\([^"]*\)".*/\1/' 2>/dev/null || echo "-")
            LOCATION_INFO=$(grep '"location":' "$temp_file" | sed 's/.*"location":"\([^"]*\)".*/\1/' 2>/dev/null || echo "-")
            MODEM_INFO=$(grep '"modem":' "$temp_file" | sed 's/.*"modem":"\([^"]*\)".*/\1/' 2>/dev/null || echo "-")
            
            # Get additional info from raw output if available
            if [ "$MODEM_BAND" = "-" ]; then
                MODEM_BAND=$(sh -x /usr/share/3ginfo-lite/3ginfo.sh 2>&1 | grep "MODE=" | tail -1 | sed "s/.*MODE='\([^']*\)'.*/\1/" 2>/dev/null || echo "-")
            fi
            
            if [ "$EARFCN_INFO" = "-" ]; then
                EARFCN_INFO=$(sh -x /usr/share/3ginfo-lite/3ginfo.sh 2>&1 | grep "EARFCN=" | tail -1 | sed "s/.*EARFCN=\([^ ]*\).*/\1/" 2>/dev/null || echo "-")
            fi
            
            if [ "$ENB_PCI" = "-" ]; then
                ENB_PCI=$(sh -x /usr/share/3ginfo-lite/3ginfo.sh 2>&1 | grep "PCI=" | tail -1 | sed "s/.*PCI=\([^ ]*\).*/\1/" 2>/dev/null || echo "-")
            fi
            
            if [ "$SINR_INFO" = "-" ]; then
                SINR_INFO=$(sh -x /usr/share/3ginfo-lite/3ginfo.sh 2>&1 | grep "SINR=" | tail -1 | sed "s/.*SINR=\([^ ]*\).*/\1/" 2>/dev/null || echo "-")
            fi
            
            if [ "$TEMP_INFO" = "-" ]; then
                TEMP_INFO=$(sh -x /usr/share/3ginfo-lite/3ginfo.sh 2>&1 | grep "TEMP=" | tail -1 | sed "s/.*TEMP='\([^']*\)'.*/\1/" 2>/dev/null || echo "-")
            fi
            
            if [ "$OPERATOR_NAME" = "-" ]; then
                OPERATOR_NAME=$(sh -x /usr/share/3ginfo-lite/3ginfo.sh 2>&1 | grep "COPS=" | tail -1 | sed "s/.*COPS='\([^']*\)'.*/\1/" 2>/dev/null || echo "-")
            fi
            
            if [ "$LOCATION_INFO" = "-" ]; then
                LOCATION_INFO=$(sh -x /usr/share/3ginfo-lite/3ginfo.sh 2>&1 | grep "LOC=" | tail -1 | sed "s/.*LOC=\([^ ]*\).*/\1/" 2>/dev/null || echo "-")
            fi
            
            if [ "$MODEM_INFO" = "-" ]; then
                MODEM_INFO=$(sh -x /usr/share/3ginfo-lite/3ginfo.sh 2>&1 | grep "MODEL=" | tail -1 | sed "s/.*MODEL='\([^']*\)'.*/\1/" 2>/dev/null || echo "-")
            fi
            
            # Clean up TEMP format - remove HTML entities
            TEMP_INFO=$(echo "$TEMP_INFO" | sed 's/&deg;/°/g' | sed 's/&amp;/\&/g')
            
            rm -f "$temp_file"
        else
            # Fallback: run with debug and parse output directly
            local debug_output=$(sh -x /usr/share/3ginfo-lite/3ginfo.sh 2>&1)
            
            MODEM_BAND=$(echo "$debug_output" | grep "MODE=" | tail -1 | sed "s/.*MODE='\([^']*\)'.*/\1/" 2>/dev/null || echo "-")
            EARFCN_INFO=$(echo "$debug_output" | grep "EARFCN=" | tail -1 | sed "s/.*EARFCN=\([0-9]*\).*/\1/" 2>/dev/null || echo "-")
            ENB_PCI=$(echo "$debug_output" | grep "PCI=" | tail -1 | sed "s/.*PCI=\([0-9]*\).*/\1/" 2>/dev/null || echo "-")
            SINR_INFO=$(echo "$debug_output" | grep "SINR=" | tail -1 | sed "s/.*SINR=\([0-9-]*\).*/\1/" 2>/dev/null || echo "-")
            TEMP_INFO=$(echo "$debug_output" | grep "TEMP=" | tail -1 | sed "s/.*TEMP='\([^']*\)'.*/\1/" 2>/dev/null || echo "-")
            OPERATOR_NAME=$(echo "$debug_output" | grep "COPS=" | tail -1 | sed "s/.*COPS='\([^']*\)'.*/\1/" 2>/dev/null || echo "-")
            LOCATION_INFO=$(echo "$debug_output" | grep "LOC=" | tail -1 | sed "s/.*LOC=\([^ ]*\).*/\1/" 2>/dev/null || echo "-")
            MODEM_INFO=$(echo "$debug_output" | grep "MODEL=" | tail -1 | sed "s/.*MODEL='\([^']*\)'.*/\1/" 2>/dev/null || echo "-")
            
            # Clean up TEMP format - remove HTML entities
            TEMP_INFO=$(echo "$TEMP_INFO" | sed 's/&deg;/°/g' | sed 's/&amp;/\&/g')
        fi
    else
        # Default values if 3ginfo script is not available
        MODEM_BAND="-"
        EARFCN_INFO="-"
        ENB_PCI="-"
        SINR_INFO="-"
        TEMP_INFO="-"
        OPERATOR_NAME="-"
        LOCATION_INFO="-"
        MODEM_INFO="-"
    fi
    
    # Clean up data format and remove duplicates
    [ -z "$MODEM_BAND" ] && MODEM_BAND="-"
    [ -z "$EARFCN_INFO" ] && EARFCN_INFO="-"
    [ -z "$ENB_PCI" ] && ENB_PCI="-"
    [ -z "$SINR_INFO" ] && SINR_INFO="-"
    [ -z "$TEMP_INFO" ] && TEMP_INFO="-"
    [ -z "$OPERATOR_NAME" ] && OPERATOR_NAME="-"
    [ -z "$LOCATION_INFO" ] && LOCATION_INFO="-"
    [ -z "$MODEM_INFO" ] && MODEM_INFO="-"
    
    # Clean up operator name - remove duplicates
    if [ "$OPERATOR_NAME" != "-" ]; then
        OPERATOR_NAME=$(echo "$OPERATOR_NAME" | awk '{
            # Split by space and track unique words
            words[1]=$1
            for(i=2;i<=NF;i++) {
                found=0
                for(j=1;j<i;j++) {
                    if(words[j]==$i) {
                        found=1
                        break
                    }
                }
                if(!found) words[i]=$i
            }
            # Reconstruct without duplicates
            result=""
            for(i=1;i<=NF;i++) {
                if(words[i]!="") {
                    if(result=="") result=words[i]
                    else result=result " " words[i]
                }
            }
            print result
        }')
    fi
}

# Function to get daily usage - FINAL FIXED VERSION
# FIXED get_daily_usage function
get_daily_usage() {
    local check_date="$1"  # DD-MM-YYYY format
    local interface="${2:-wwan0}"
    local debug="$3"
    local usage="0.00"
    
    # Convert DD-MM-YYYY to YYYY-MM-DD for vnstat
    local vnstat_date=$(echo "$check_date" | awk -F"-" "{printf \"%s-%02d-%02d\", \$3, \$2, \$1}")
    
    [ "$debug" = "--debug" ] && echo "Debug: Checking $check_date (converted to $vnstat_date)" >&2
    
    # Method 1: Try vnstat JSON (most accurate)
    if command -v vnstat >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
        local vnstat_json=$(vnstat -i "$interface" --json d 2>/dev/null)
        if [ -n "$vnstat_json" ]; then
            # Parse JSON to find matching date
            usage=$(echo "$vnstat_json" | jq -r "
                .interfaces[0].traffic.day[] | 
                select(.date.year == $(echo $vnstat_date | cut -d- -f1) and 
                       .date.month == $(echo $vnstat_date | cut -d- -f2) and 
                       .date.day == $(echo $vnstat_date | cut -d- -f3)) | 
                (.rx + .tx) / 1024 / 1024 / 1024" 2>/dev/null)
            
            if [ -n "$usage" ] && [ "$usage" != "null" ] && [ "$usage" != "" ]; then
                usage=$(printf "%.2f" "$usage" 2>/dev/null || echo "0.00")
                [ "$debug" = "--debug" ] && echo "Debug: JSON method found $check_date: $usage GB" >&2
                echo "$usage"
                return
            fi
        fi
    fi
    
    # Method 2: Parse vnstat text output (fallback)
    if command -v vnstat >/dev/null 2>&1; then
        local vnstat_text=$(vnstat -i "$interface" -d 2>/dev/null)
        if [ -n "$vnstat_text" ]; then
            # Look for exact date match in format YYYY-MM-DD
            usage=$(echo "$vnstat_text" | awk -v date="$vnstat_date" "
                \$1 == date { 
                    # Field structure: DATE RX TX TOTAL RATE
                    # Total is typically the 4th field, in format \"X.XX GiB\"
                    total_field = \"\"
                    for(i=1; i<=NF; i++) {
                        if(\$i ~ /[0-9]+\.[0-9]+\$/ && \$(i+1) ~ /GiB/) {
                            total_field = \$i
                            break
                        }
                    }
                    # If no unit found, try field 4 (typical total position)
                    if(total_field == \"\" && NF >= 4 && \$4 ~ /[0-9]+\.[0-9]+\$/) {
                        total_field = \$4
                    }
                    if(total_field != \"\") {
                        # Convert GiB to GB
                        printf \"%.2f\", total_field * 1.073741824
                    }
                    exit
                }")
            
            if [ -n "$usage" ] && [ "$usage" != "0.00" ]; then
                [ "$debug" = "--debug" ] && echo "Debug: Text method found $check_date: $usage GB" >&2
                echo "$usage"
                return
            fi
        fi
    fi
    
    # Return 0.00 if no data found
    [ "$debug" = "--debug" ] && echo "Debug: No data found for $check_date" >&2
    echo "0.00"
}

# Function to get date range
get_date_range() {
    local start_date="$1"
    local end_date="$2"
    
    local start_conv=$(convert_date_format "$start_date")
    local end_conv=$(convert_date_format "$end_date")
    
    local current_epoch=$(date -d "$start_conv" +%s 2>/dev/null || echo "0")
    local end_epoch=$(date -d "$end_conv" +%s 2>/dev/null || echo "0")
    
    if [ "$current_epoch" -eq 0 ] || [ "$end_epoch" -eq 0 ]; then
        echo ""
        return
    fi
    
    local dates=""
    while [ "$current_epoch" -le "$end_epoch" ]; do
        local current_date=$(date -d "@$current_epoch" +%d-%m-%Y 2>/dev/null)
        if [ -n "$current_date" ]; then
            dates="$dates $current_date"
        fi
        current_epoch=$((current_epoch + 86400))
    done
    
    echo "$dates"
}

# Function to calculate period total
calculate_period_total() {
    local start_date="$1"
    local end_date="$2"
    local interface="${3:-wwan0}"
    
    local total="0.00"
    local dates=$(get_date_range "$start_date" "$end_date")
    
    for date in $dates; do
        local daily_usage=$(get_daily_usage "$date" "$interface")
        total=$(awk -v total="$total" -v daily="$daily_usage" 'BEGIN { printf "%.2f", total + daily }')
    done
    
    echo "$total"
}

# Function to send telegram message
send_telegram() {
    local message="$1"
    
    if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
        echo "⚠ Telegram configuration not set"
        return 1
    fi
    
    # Clean message for Telegram compatibility
    local cleaned_message=$(echo "$message" | sed 's/&deg;/°/g' | sed 's/&amp;/\&/g')
    
    # Split message if too long (Telegram limit is 4096 characters)
    local message_length=$(echo "$cleaned_message" | wc -c)
    
    if [ "$message_length" -gt 4000 ]; then
        # Send in parts
        local part1=$(echo "$cleaned_message" | head -c 3500)
        local part2=$(echo "$cleaned_message" | tail -c +3501)
        
        # Send first part
        send_telegram_part "$part1" "1/2"
        sleep 1
        
        # Send second part
        send_telegram_part "$part2" "2/2"
    else
        send_telegram_part "$cleaned_message" ""
    fi
}

# Function to send single telegram message part
send_telegram_part() {
    local message="$1"
    local part_info="$2"
    local temp_msg="/tmp/telegram_message.txt"
    
    if [ -n "$part_info" ]; then
        echo "📊 Data Monitor Report $part_info" > "$temp_msg"
        echo "" >> "$temp_msg"
        echo "$message" >> "$temp_msg"
    else
        echo "$message" > "$temp_msg"
    fi
    
    local response=$(curl -s -X POST \
        "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d "parse_mode=Markdown" \
        -d "text=$(cat "$temp_msg")")
    
    if echo "$response" | grep -q '"ok":true'; then
        echo "✅ Message part sent to Telegram successfully!"
        rm -f "$temp_msg"
        return 0
    else
        echo "⚠ Failed to send message part to Telegram"
        echo "Response: $response"
        
        # Try without Markdown if it failed
        echo "🔄 Retrying without Markdown formatting..."
        local response2=$(curl -s -X POST \
            "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
            -d "chat_id=${TELEGRAM_CHAT_ID}" \
            -d "text=$(cat "$temp_msg")")
        
        if echo "$response2" | grep -q '"ok":true'; then
            echo "✅ Message sent without Markdown formatting!"
            rm -f "$temp_msg"
            return 0
        else
            echo "❌ Failed to send message completely"
            rm -f "$temp_msg"
            return 1
        fi
    fi
}

# Main report generation
generate_report() {
    local current_date=$(get_current_date)
    local report_time=$(date +"%d-%m-%Y %H:%M:%S")
    
    # Get 3ginfo technical data
    get_3ginfo_data
    
    # Calculate current period days
    local current_days=$(calculate_days_between "$START_DATE" "$current_date")
    
    # Get dates for current period
    local dates=$(get_date_range "$START_DATE" "$current_date")
    
    # Build daily breakdown
    local daily_breakdown=""
    local counter=1
    local current_total="0.00"
    
    # Process each date in current period
    for date in $dates; do
        local daily_usage=$(get_daily_usage "$date" "$NETWORK_INTERFACE")
        daily_breakdown="${daily_breakdown}${counter}. ${daily_usage} GB (${date})
"
        current_total=$(awk -v total="$current_total" -v daily="$daily_usage" 'BEGIN { printf "%.2f", total + daily }')
        counter=$((counter + 1))
    done
    
    # Calculate previous periods
    local prev1_days=""
    local prev1_total="0.00"
    local prev2_days=""
    local prev2_total="0.00"
    
    if [ -n "$PREV_PERIOD1_START" ] && [ -n "$PREV_PERIOD1_END" ]; then
        prev1_days=$(calculate_days_between "$PREV_PERIOD1_START" "$PREV_PERIOD1_END")
        prev1_total=$(calculate_period_total "$PREV_PERIOD1_START" "$PREV_PERIOD1_END" "$NETWORK_INTERFACE")
    fi
    
    if [ -n "$PREV_PERIOD2_START" ] && [ -n "$PREV_PERIOD2_END" ]; then
        prev2_days=$(calculate_days_between "$PREV_PERIOD2_START" "$PREV_PERIOD2_END")
        prev2_total=$(calculate_period_total "$PREV_PERIOD2_START" "$PREV_PERIOD2_END" "$NETWORK_INTERFACE")
    fi
    
    # Build message with modern formatting
    local message="📊 *DATA USAGE REPORT*"
    
    if [ -n "$PHONE_NUMBER" ]; then
        message="${message}
📱 Phone: \`${PHONE_NUMBER}\`"
    fi
    
    message="${message}
🌐 Operator: *${OPERATOR_NAME}*
📍 Lokasi: *${LOCATION_INFO}*
📡 Modem: \`${MODEM_INFO}\`
▫️▫️▫️▫️▫️▫️▫️▫️▫️▫️▫️▫️▫️▫️▫️▫️
🔧 Service: *${SERVICE_INFO}*
🔌 Interface: \`${NETWORK_INTERFACE}\`
📅 Period: *${START_DATE}* ➜ *${current_date}* _(${current_days} hari)_
📶 BAND: \`${MODEM_BAND}\`
📊 EARFCN(DL/UL): \`${EARFCN_INFO}\`
🏢 eNB ID(PCI): \`${ENB_PCI}\`
📈 RS-SNR: \`${SINR_INFO}dB\`
🌡️ TEMP: \`${TEMP_INFO}\`
▫️▫️▫️▫️▫️▫️▫️▫️▫️▫️▫️▫️▫️▫️▫️▫️"
    
    # Previous periods with Note support and modern formatting
    if [ -n "$PREV_PERIOD1_START" ] && [ -n "$PREV_PERIOD1_END" ] && [ "$prev1_days" != "0" ]; then
        message="${message}
🔙 *PREVIOUS PERIODS*
📆 Period 1: *${PREV_PERIOD1_START}* ➜ *${PREV_PERIOD1_END}* _(${prev1_days} hari)_
💾 Total Usage: *${prev1_total} GB*"
        
        # Add note if available
        if [ -n "$PREV_PERIOD1_NOTE" ] && [ "$PREV_PERIOD1_NOTE" != "" ]; then
            message="${message}
💬 Note: _${PREV_PERIOD1_NOTE}_"
        fi
        
        if [ -n "$PREV_PERIOD2_START" ] && [ -n "$PREV_PERIOD2_END" ] && [ "$prev2_days" != "0" ]; then
            message="${message}

📆 Period 2: *${PREV_PERIOD2_START}* ➜ *${PREV_PERIOD2_END}* _(${prev2_days} hari)_
💾 Total Usage: *${prev2_total} GB*"
            
            # Add note if available
            if [ -n "$PREV_PERIOD2_NOTE" ] && [ "$PREV_PERIOD2_NOTE" != "" ]; then
                message="${message}
💬 Note: _${PREV_PERIOD2_NOTE}_"
            fi
        fi
        
        message="${message}
▫️▫️▫️▫️▫️▫️▫️▫️▫️▫️▫️▫️▫️▫️▫️"
    fi
    
    # Current period usage with modern formatting
    message="${message}
📊 *CURRENT PERIOD USAGE*
📈 Daily Breakdown:
${daily_breakdown}▪️▪️▪️▪️▪️▪️▪️▪️▪️▪️▪️▪️▪️▪️▪️
💯 *TOTAL: ${current_total} GB*
▫️▫️▫️▫️▫️▫️▫️▫️▫️▫️▫️▫️▫️▫️▫️
⏰ Report: \`${report_time}\`"
    
    # Display or send
    if [ "$1" != "--send" ]; then
        echo "$message"
        echo ""
        echo "✅ Test completed. Use '/opt/data-monitor/run.sh --send' to send to Telegram."
        return 0
    fi
    
    echo "📤 Sending report to Telegram..."
    if send_telegram "$message"; then
        echo "✅ Report sent successfully!"
    else
        echo "⚠ Failed to send report"
        return 1
    fi
    
    echo "[$(date)] Generated report - Current: ${current_total} GB, Period: ${current_days} days" >> "$LOG_FILE"
}

# Function to test individual date
test_single_date() {
    local test_date="$1"
    echo "🧪 Testing single date: $test_date"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    local result=$(get_daily_usage "$test_date" "wwan0" "--debug")
    echo "Result: $result GB"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Function to test report
test_report() {
    echo "🧪 Testing Report Generation..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    generate_report
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Function to collect daily data
collect_daily_data() {
    local interface="${NETWORK_INTERFACE:-wwan0}"
    local today=$(date +%d-%m-%Y)
    local log_file="/tmp/data-usage-history.log"
    
    if [ -f "/sys/class/net/$interface/statistics/rx_bytes" ]; then
        rx_bytes=$(cat "/sys/class/net/$interface/statistics/rx_bytes")
        tx_bytes=$(cat "/sys/class/net/$interface/statistics/tx_bytes")
        total_bytes=$((rx_bytes + tx_bytes))
        
        if [ -f "$log_file" ]; then
            grep -v "^$today,$interface," "$log_file" > "$log_file.tmp" 2>/dev/null || touch "$log_file.tmp"
            mv "$log_file.tmp" "$log_file"
        fi
        
        echo "$today,$interface,$total_bytes" >> "$log_file"
        echo "✅ Collected data for $today: $(awk -v total="$total_bytes" 'BEGIN { printf "%.2f GB", total/1024/1024/1024 }')"
    else
        echo "⚠ Interface $interface not found"
    fi
}

# Main script
case "$1" in
    --send)
        generate_report --send
        ;;
    --test)
        test_report
        ;;
    --test-date)
        test_single_date "$2"
        ;;
    --collect)
        collect_daily_data
        ;;
    *)
        echo "📊 Data Monitor Report Script v3.2"
        echo "Usage:"
        echo "  $0 --test             # Test report generation"
        echo "  $0 --test-date DATE   # Test single date (DD-MM-YYYY)"
        echo "  $0 --send             # Send report to Telegram"  
        echo "  $0 --collect          # Collect daily data"
        ;;
esac