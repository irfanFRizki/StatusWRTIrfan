#!/bin/sh
# Enhanced Data Monitor v3.0 with Dual Previous Periods

# Load configuration
CONFIG_FILE="/etc/config/data-monitor"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "âŒ Configuration file not found: $CONFIG_FILE"
    exit 1
fi

. "$CONFIG_FILE"

# Function to convert date format
convert_date() {
    local input_date="$1"
    echo "$input_date" | awk -F'-' '{printf "%04d-%02d-%02d", $3, $2, $1}'
}

# Function to get data usage for interface
get_interface_data() {
    local interface="$1"
    local rx_bytes tx_bytes total_bytes total_gb
    
    if [ -f "/sys/class/net/$interface/statistics/rx_bytes" ] && [ -f "/sys/class/net/$interface/statistics/tx_bytes" ]; then
        rx_bytes=$(cat "/sys/class/net/$interface/statistics/rx_bytes")
        tx_bytes=$(cat "/sys/class/net/$interface/statistics/tx_bytes")
        total_bytes=$((rx_bytes + tx_bytes))
        total_gb=$(echo "scale=2; $total_bytes / 1024 / 1024 / 1024" | bc 2>/dev/null || echo "0.00")
        echo "$total_gb"
    else
        echo "0.00"
    fi
}

# Function to calculate days between dates
calculate_days() {
    local start_date="$1"
    local end_date="$2"
    local start_epoch end_epoch diff_days
    
    start_epoch=$(date -d "$(convert_date "$start_date")" +%s 2>/dev/null || echo "0")
    end_epoch=$(date -d "$(convert_date "$end_date")" +%s 2>/dev/null || echo "0")
    
    if [ "$start_epoch" -ne 0 ] && [ "$end_epoch" -ne 0 ]; then
        diff_days=$(((end_epoch - start_epoch) / 86400 + 1))
        echo "$diff_days"
    else
        echo "1"
    fi
}

# Function to get daily usage data
get_daily_usage() {
    local start_date="$1"
    local data_file="/tmp/data_usage_daily.log"
    local current_date today_usage
    
    # Create log file if it doesn't exist
    touch "$data_file"
    
    # Get current date
    current_date=$(date +%d-%m-%Y)
    
    # Get current total usage
    today_usage=$(get_interface_data "$NETWORK_INTERFACE")
    
    # Log today's usage (overwrite if exists for today)
    grep -v "^$current_date:" "$data_file" > "${data_file}.tmp" 2>/dev/null || touch "${data_file}.tmp"
    echo "$current_date:$today_usage" >> "${data_file}.tmp"
    mv "${data_file}.tmp" "$data_file"
    
    # Return daily breakdown since start date
    local start_epoch current_epoch
    start_epoch=$(date -d "$(convert_date "$start_date")" +%s 2>/dev/null || date +%s)
    current_epoch=$(date +%s)
    
    local daily_data=""
    local day_counter=1
    local temp_date="$start_date"
    local prev_usage=0
    
    while [ "$(date -d "$(convert_date "$temp_date")" +%s 2>/dev/null || echo 0)" -le "$current_epoch" ]; do
        local day_usage=$(grep "^$temp_date:" "$data_file" | cut -d':' -f2 2>/dev/null || echo "0.00")
        
        if [ "$day_usage" = "0.00" ] || [ -z "$day_usage" ]; then
            if [ "$temp_date" = "$current_date" ]; then
                day_usage="$today_usage"
            else
                day_usage="0.00"
            fi
        fi
        
        # Calculate daily increment
        local daily_increment
        if [ "$day_counter" -eq 1 ]; then
            daily_increment="$day_usage"
        else
            daily_increment=$(echo "scale=2; $day_usage - $prev_usage" | bc 2>/dev/null || echo "0.00")
            if [ "$(echo "$daily_increment < 0" | bc 2>/dev/null)" = "1" ]; then
                daily_increment="$day_usage"
            fi
        fi
        
        daily_data="$daily_data$day_counter. $daily_increment GB ($temp_date)\n"
        
        prev_usage="$day_usage"
        day_counter=$((day_counter + 1))
        
        # Move to next day
        temp_date=$(date -d "$(convert_date "$temp_date") +1 day" +%d-%m-%Y 2>/dev/null || break)
        
        # Safety check to prevent infinite loop
        if [ "$day_counter" -gt 100 ]; then
            break
        fi
    done
    
    echo -e "$daily_data"
}

# Function to send Telegram message
send_telegram() {
    local message="$1"
    local url="https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage"
    
    # Use wget if available, otherwise curl
    if command -v wget > /dev/null; then
        wget -qO- --post-data="chat_id=$TELEGRAM_CHAT_ID&text=$message&parse_mode=Markdown" "$url" > /dev/null 2>&1
    elif command -v curl > /dev/null; then
        curl -s -X POST "$url" -d "chat_id=$TELEGRAM_CHAT_ID" -d "text=$message" -d "parse_mode=Markdown" > /dev/null 2>&1
    else
        echo "âŒ Neither wget nor curl found. Cannot send Telegram message."
        return 1
    fi
}

# Function to generate enhanced report with dual previous periods
generate_report() {
    local current_date=$(date +%d-%m-%Y)
    local current_time=$(date +%H:%M:%S)
    local report_header report_body report_footer
    
    # Header with phone number if available
    if [ -n "$PHONE_NUMBER" ] && [ "$PHONE_NUMBER" != "" ]; then
        report_header="**ðŸ“Š Data Usage Report**\nðŸ“± Phone: \`$PHONE_NUMBER\`"
    else
        report_header="**ðŸ“Š Data Usage Report**"
    fi
    
    report_header="$report_header\nâ”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”"
    
    # Current period info
    local period_days=$(calculate_days "$START_DATE" "$current_date")
    report_body="Interface: \`$NETWORK_INTERFACE\`\nPeriod: $START_DATE â†’ $current_date ($period_days hari)\nâ”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”"
    
    # Previous Period 1 (most recent)
    if [ -n "$PREV_PERIOD_1_START" ] && [ "$PREV_PERIOD_1_START" != "" ]; then
        local prev1_days=$(calculate_days "$PREV_PERIOD_1_START" "$PREV_PERIOD_1_END")
        report_body="$report_body\n\n**Previous Period 1:**\nPeriod: $PREV_PERIOD_1_START â†’ $PREV_PERIOD_1_END ($prev1_days hari)\nTotal Usage: $PREV_PERIOD_1_TOTAL GB"
    fi
    
    # Previous Period 2 (older)
    if [ -n "$PREV_PERIOD_2_START" ] && [ "$PREV_PERIOD_2_START" != "" ]; then
        local prev2_days=$(calculate_days "$PREV_PERIOD_2_START" "$PREV_PERIOD_2_END")
        report_body="$report_body\n\n**Previous Period 2:**\nPeriod: $PREV_PERIOD_2_START â†’ $PREV_PERIOD_2_END ($prev2_days hari)\nTotal Usage: $PREV_PERIOD_2_TOTAL GB"
    fi
    
    report_body="$report_body\nâ”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”"
    
    # Current period usage breakdown
    local daily_breakdown=$(get_daily_usage "$START_DATE")
    local total_usage=$(get_interface_data "$NETWORK_INTERFACE")
    
    report_body="$report_body\n\n**Current Period Usage:**\nDaily Breakdown:\n$daily_breakdown"
    report_body="$report_bodyâ•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•\nTotal: **$total_usage GB**"
    
    # Footer
    report_footer="â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”\nReport: $current_date $current_time"
    
    # Combine all parts
    local full_report="$report_header\n$report_body\n$report_footer"
    
    echo -e "$full_report"
}

# Main execution
main() {
    echo "ðŸ”„ Generating enhanced data usage report..."
    
    # Check if required tools are available
    if ! command -v bc > /dev/null; then
        echo "âš ï¸  Warning: bc not found. Some calculations may be inaccurate."
    fi
    
    # Generate and send report
    local report=$(generate_report)
    
    echo "ðŸ“Š Generated Report:"
    echo -e "$report"
    echo ""
    
    if [ "$TELEGRAM_BOT_TOKEN" != "YOUR_BOT_TOKEN_HERE" ] && [ "$TELEGRAM_CHAT_ID" != "YOUR_CHAT_ID_HERE" ]; then
        echo "ðŸ“¤ Sending to Telegram..."
        if send_telegram "$report"; then
            echo "âœ… Report sent successfully!"
        else
            echo "âŒ Failed to send report"
        fi
    else
        echo "âš ï¸  Telegram not configured. Report generated locally only."
    fi
}

# Run main function
main
