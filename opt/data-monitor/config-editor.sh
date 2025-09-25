#!/bin/sh
# Color-Fixed Data Monitor Configuration Editor v3.1
# Interactive CLI tool to edit /etc/config/data-monitor

CONFIG_FILE="/etc/config/data-monitor"
BACKUP_DIR="/etc/config"

# Colors for better UI - using echo -e instead of printf
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# Function to print colored text - FIXED VERSION
print_color() {
    local color=$1
    shift
    echo -e "${color}$*${NC}"
}

# Function to print header
print_header() {
    echo ""
    print_color $CYAN "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_color $WHITE "                  📊 DATA MONITOR CONFIGURATION EDITOR v3.1"
    print_color $CYAN "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# Function to create backup
create_backup() {
    if [ -f "$CONFIG_FILE" ]; then
        local backup_file="${BACKUP_DIR}/data-monitor.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$CONFIG_FILE" "$backup_file"
        print_color $GREEN "✅ Backup created: $backup_file"
    fi
}

# Function to load current configuration
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        . "$CONFIG_FILE" 2>/dev/null
        
        # Set defaults for new options if not present
        PHONE_NUMBER="${PHONE_NUMBER:-}"
        SCHEDULE_TYPE="${SCHEDULE_TYPE:-daily}"
        SCHEDULE_HOUR="${SCHEDULE_HOUR:-8}"
        SCHEDULE_DAYS="${SCHEDULE_DAYS:-everyday}"
        SCHEDULE_CRON="${SCHEDULE_CRON:-0 8 * * *}"
        
        # Previous Period 1
        PREV_PERIOD1_START="${PREV_PERIOD1_START:-}"
        PREV_PERIOD1_END="${PREV_PERIOD1_END:-}"
        PREV_PERIOD1_TOTAL="${PREV_PERIOD1_TOTAL:-0.0}"
        PREV_PERIOD1_NOTE="${PREV_PERIOD1_NOTE:-}"
        
        # Previous Period 2
        PREV_PERIOD2_START="${PREV_PERIOD2_START:-}"
        PREV_PERIOD2_END="${PREV_PERIOD2_END:-}"
        PREV_PERIOD2_TOTAL="${PREV_PERIOD2_TOTAL:-0.0}"
        PREV_PERIOD2_NOTE="${PREV_PERIOD2_NOTE:-}"
        
    else
        print_color $RED "❌ Configuration file not found: $CONFIG_FILE"
        print_color $YELLOW "⚠️  Creating default configuration..."
        create_default_config
    fi
}

# Function to create default configuration
create_default_config() {
    cat > "$CONFIG_FILE" << 'EOF'
# Enhanced Data Monitor Configuration File v3.1

# Telegram Bot Configuration
export TELEGRAM_BOT_TOKEN="YOUR_BOT_TOKEN_HERE"
export TELEGRAM_CHAT_ID="YOUR_CHAT_ID_HERE"

# Phone Number (optional, for identification in reports)
export PHONE_NUMBER=""

# Network interface to monitor (usually wwan0 for mobile data)
export NETWORK_INTERFACE="wwan0"

# Current monitoring period start date (DD-MM-YYYY)
export START_DATE="12-09-2025"

# Previous Period 1 tracking (for comparison reports)
export PREV_PERIOD1_START="01-08-2025"
export PREV_PERIOD1_END="11-08-2025"
export PREV_PERIOD1_TOTAL="0.0"
export PREV_PERIOD1_NOTE=""

# Previous Period 2 tracking (for additional comparison)
export PREV_PERIOD2_START="12-08-2025"
export PREV_PERIOD2_END="11-09-2025"
export PREV_PERIOD2_TOTAL="0.0"
export PREV_PERIOD2_NOTE=""

# Schedule Configuration
export SCHEDULE_TYPE="daily"
export SCHEDULE_HOUR="8"
export SCHEDULE_DAYS="everyday"
export SCHEDULE_CRON="0 8 * * *"
EOF
    print_color $GREEN "✅ Default configuration created"
    load_config
}

# Function to sync cron expression
sync_cron_expression() {
    if [ "$SCHEDULE_TYPE" != "custom" ]; then
        if [ "$SCHEDULE_DAYS" = "everyday" ]; then
            SCHEDULE_CRON="0 $SCHEDULE_HOUR * * *"
        else
            cron_days=$(echo "$SCHEDULE_DAYS" | sed 's/monday/1/g; s/tuesday/2/g; s/wednesday/3/g; s/thursday/4/g; s/friday/5/g; s/saturday/6/g; s/sunday/0/g')
            SCHEDULE_CRON="0 $SCHEDULE_HOUR * * $cron_days"
        fi
    fi
}

# Function to display current configuration - FIXED VERSION
display_current_config() {
    print_color $BLUE "📋 Current Configuration:"
    print_color $CYAN "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    local status_icon
    local masked_token
    local masked_chat
    local masked_phone
    
    # Check and display Telegram Bot Token
    if [ "$TELEGRAM_BOT_TOKEN" = "YOUR_BOT_TOKEN_HERE" ] || [ -z "$TELEGRAM_BOT_TOKEN" ]; then
        status_icon="❌"
        masked_token="Not set"
        echo -e "${WHITE}1.${NC} Telegram Bot Token      : ${RED}$status_icon${NC} ${YELLOW}$masked_token${NC}"
    else
        status_icon="✅"
        masked_token=$(echo "$TELEGRAM_BOT_TOKEN" | sed 's/\(.\{8\}\).*/\1**********/')
        echo -e "${WHITE}1.${NC} Telegram Bot Token      : ${GREEN}$status_icon${NC} ${YELLOW}$masked_token${NC}"
    fi
    
    # Check and display Telegram Chat ID
    if [ "$TELEGRAM_CHAT_ID" = "YOUR_CHAT_ID_HERE" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
        status_icon="❌"
        masked_chat="Not set"
        echo -e "${WHITE}2.${NC} Telegram Chat ID       : ${RED}$status_icon${NC} ${YELLOW}$masked_chat${NC}"
    else
        status_icon="✅"
        masked_chat=$(echo "$TELEGRAM_CHAT_ID" | sed 's/\(.\{3\}\).*/\1**********/')
        echo -e "${WHITE}2.${NC} Telegram Chat ID       : ${GREEN}$status_icon${NC} ${YELLOW}$masked_chat${NC}"
    fi
    
    # Check and display Phone Number
    if [ -n "$PHONE_NUMBER" ]; then
        status_icon="✅"
        masked_phone=$(echo "$PHONE_NUMBER" | sed 's/\(.\{3\}\).*/\1*******/')
        echo -e "${WHITE}3.${NC} Phone Number           : ${GREEN}$status_icon${NC} ${YELLOW}$masked_phone${NC}"
    else
        status_icon="⚠️"
        echo -e "${WHITE}3.${NC} Phone Number           : ${YELLOW}$status_icon${NC} ${YELLOW}Not set${NC}"
    fi
    
    # Display other configuration items
    echo -e "${WHITE}4.${NC} Network Interface       : ${GREEN}✅${NC} ${YELLOW}${NETWORK_INTERFACE:-wwan0}${NC}"
    echo -e "${WHITE}5.${NC} Current Start Date      : ${GREEN}✅${NC} ${YELLOW}${START_DATE:-Not set}${NC}"
    echo -e "${WHITE}6.${NC} Previous Period 1 Start : ${GREEN}✅${NC} ${YELLOW}${PREV_PERIOD1_START:-Not set}${NC}"
    echo -e "${WHITE}7.${NC} Previous Period 1 End   : ${GREEN}✅${NC} ${YELLOW}${PREV_PERIOD1_END:-Not set}${NC}"
    echo -e "${WHITE}8.${NC} Previous Period 1 Total : ${CYAN}🔄${NC} ${YELLOW}${PREV_PERIOD1_TOTAL:-0.0} GB${NC} ${CYAN}(Auto-calculated)${NC}"
    echo -e "${WHITE}9.${NC} Previous Period 1 Note  : ${GREEN}✅${NC} ${YELLOW}${PREV_PERIOD1_NOTE:-Not set}${NC}"
    echo -e "${WHITE}10.${NC} Previous Period 2 Start : ${GREEN}✅${NC} ${YELLOW}${PREV_PERIOD2_START:-Not set}${NC}"
    echo -e "${WHITE}11.${NC} Previous Period 2 End   : ${GREEN}✅${NC} ${YELLOW}${PREV_PERIOD2_END:-Not set}${NC}"
    echo -e "${WHITE}12.${NC} Previous Period 2 Total : ${CYAN}🔄${NC} ${YELLOW}${PREV_PERIOD2_TOTAL:-0.0} GB${NC} ${CYAN}(Auto-calculated)${NC}"
    echo -e "${WHITE}13.${NC} Previous Period 2 Note  : ${GREEN}✅${NC} ${YELLOW}${PREV_PERIOD2_NOTE:-Not set}${NC}"
    echo -e "${WHITE}14.${NC} Schedule Type          : ${GREEN}✅${NC} ${YELLOW}${SCHEDULE_TYPE:-daily}${NC}"
    echo -e "${WHITE}15.${NC} Schedule Hour          : ${GREEN}✅${NC} ${YELLOW}${SCHEDULE_HOUR:-8}:00${NC}"
    echo -e "${WHITE}16.${NC} Schedule Days          : ${GREEN}✅${NC} ${YELLOW}${SCHEDULE_DAYS:-everyday}${NC}"
    echo -e "${WHITE}17.${NC} Custom Cron            : ${GREEN}✅${NC} ${YELLOW}${SCHEDULE_CRON:-0 8 * * *}${NC}"
    
    print_color $CYAN "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Validation functions
validate_date() {
    local date_str="$1"
    echo "$date_str" | grep -qE '^[0-9]{1,2}-[0-9]{1,2}-[0-9]{4}$'
}

validate_phone() {
    local phone="$1"
    [ -z "$phone" ] || echo "$phone" | grep -qE '^[+]?[0-9\-\s()]+$'
}

validate_hour() {
    local hour="$1"
    echo "$hour" | grep -qE '^([0-1]?[0-9]|2[0-3])$'
}

validate_days() {
    local days="$1"
    [ "$days" = "everyday" ] || echo "$days" | grep -qE '^(monday|tuesday|wednesday|thursday|friday|saturday|sunday)(,(monday|tuesday|wednesday|thursday|friday|saturday|sunday))*$'
}

validate_schedule_type() {
    local type="$1"
    case "$type" in
        hourly|daily|custom) return 0 ;;
        *) return 1 ;;
    esac
}

validate_cron() {
    local cron="$1"
    local field_count=$(echo "$cron" | awk '{print NF}')
    [ "$field_count" -eq 5 ]
}

# Function to edit configuration item
edit_config_item() {
    local item_num="$1"
    local current_value=""
    local new_value=""
    local prompt_text=""
    local validation_func=""
    
    case $item_num in
        1) 
            current_value="$TELEGRAM_BOT_TOKEN"
            prompt_text="Enter Telegram Bot Token"
            ;;
        2) 
            current_value="$TELEGRAM_CHAT_ID"
            prompt_text="Enter Telegram Chat ID"
            ;;
        3) 
            current_value="$PHONE_NUMBER"
            prompt_text="Enter Phone Number (optional)"
            validation_func="validate_phone"
            ;;
        4) 
            current_value="$NETWORK_INTERFACE"
            prompt_text="Enter Network Interface"
            ;;
        5) 
            current_value="$START_DATE"
            prompt_text="Enter Current Start Date (DD-MM-YYYY)"
            validation_func="validate_date"
            ;;
        6) 
            current_value="$PREV_PERIOD1_START"
            prompt_text="Enter Previous Period 1 Start (DD-MM-YYYY)"
            validation_func="validate_date"
            ;;
        7) 
            current_value="$PREV_PERIOD1_END"
            prompt_text="Enter Previous Period 1 End (DD-MM-YYYY)"
            validation_func="validate_date"
            ;;
        8) 
            print_color $YELLOW "⚠️  Previous Period 1 Total is auto-calculated"
            return 0
            ;;
        9) 
            current_value="$PREV_PERIOD1_NOTE"
            prompt_text="Enter Previous Period 1 Note (optional)"
            ;;
        10) 
            current_value="$PREV_PERIOD2_START"
            prompt_text="Enter Previous Period 2 Start (DD-MM-YYYY)"
            validation_func="validate_date"
            ;;
        11) 
            current_value="$PREV_PERIOD2_END"
            prompt_text="Enter Previous Period 2 End (DD-MM-YYYY)"
            validation_func="validate_date"
            ;;
        12) 
            print_color $YELLOW "⚠️  Previous Period 2 Total is auto-calculated"
            return 0
            ;;
        13) 
            current_value="$PREV_PERIOD2_NOTE"
            prompt_text="Enter Previous Period 2 Note (optional)"
            ;;
        14) 
            current_value="$SCHEDULE_TYPE"
            prompt_text="Enter Schedule Type (hourly/daily/custom)"
            validation_func="validate_schedule_type"
            ;;
        15) 
            current_value="$SCHEDULE_HOUR"
            prompt_text="Enter Schedule Hour (0-23)"
            validation_func="validate_hour"
            ;;
        16) 
            current_value="$SCHEDULE_DAYS"
            prompt_text="Enter Schedule Days (everyday or monday,wednesday,friday)"
            validation_func="validate_days"
            ;;
        17) 
            current_value="$SCHEDULE_CRON"
            prompt_text="Enter Custom Cron Expression"
            validation_func="validate_cron"
            ;;
        *) 
            print_color $RED "❌ Invalid option"
            return 1
            ;;
    esac
    
    echo ""
    print_color $YELLOW "📝 Editing Configuration Item"
    echo -e "${WHITE}Current value: ${YELLOW}$current_value${NC}"
    echo -n -e "${BLUE}$prompt_text${NC}: "
    read new_value
    
    if [ -z "$new_value" ]; then
        new_value="$current_value"
        print_color $YELLOW "⚠️  Using current value"
    fi
    
    if [ -n "$validation_func" ]; then
        if ! $validation_func "$new_value"; then
            print_color $RED "❌ Invalid format!"
            return 1
        fi
    fi
    
    # Update configuration variables
    case $item_num in
        1) TELEGRAM_BOT_TOKEN="$new_value" ;;
        2) TELEGRAM_CHAT_ID="$new_value" ;;
        3) PHONE_NUMBER="$new_value" ;;
        4) NETWORK_INTERFACE="$new_value" ;;
        5) START_DATE="$new_value" ;;
        6) PREV_PERIOD1_START="$new_value" ;;
        7) PREV_PERIOD1_END="$new_value" ;;
        9) PREV_PERIOD1_NOTE="$new_value" ;;
        10) PREV_PERIOD2_START="$new_value" ;;
        11) PREV_PERIOD2_END="$new_value" ;;
        13) PREV_PERIOD2_NOTE="$new_value" ;;
        14) SCHEDULE_TYPE="$new_value" ;;
        15) SCHEDULE_HOUR="$new_value" ;;
        16) SCHEDULE_DAYS="$new_value" ;;
        17) SCHEDULE_CRON="$new_value" ;;
    esac
    
    # Sync cron if needed
    case $item_num in
        14|15|16) 
            sync_cron_expression
            print_color $YELLOW "🔄 Cron synced: $SCHEDULE_CRON"
            ;;
    esac
    
    print_color $GREEN "✅ Updated successfully!"
}

# Function to save configuration
save_config() {
    print_color $YELLOW "💾 Saving configuration..."
    create_backup
    
    cat > "$CONFIG_FILE" << EOF
# Enhanced Data Monitor Configuration File v3.1

# Telegram Bot Configuration
export TELEGRAM_BOT_TOKEN="$TELEGRAM_BOT_TOKEN"
export TELEGRAM_CHAT_ID="$TELEGRAM_CHAT_ID"

# Phone Number (optional, for identification in reports)
export PHONE_NUMBER="$PHONE_NUMBER"

# Network interface to monitor (usually wwan0 for mobile data)
export NETWORK_INTERFACE="$NETWORK_INTERFACE"

# Current monitoring period start date (DD-MM-YYYY)
export START_DATE="$START_DATE"

# Previous Period 1 tracking (for comparison reports)
export PREV_PERIOD1_START="$PREV_PERIOD1_START"
export PREV_PERIOD1_END="$PREV_PERIOD1_END"
export PREV_PERIOD1_TOTAL="$PREV_PERIOD1_TOTAL"
export PREV_PERIOD1_NOTE="$PREV_PERIOD1_NOTE"

# Previous Period 2 tracking (for additional comparison)
export PREV_PERIOD2_START="$PREV_PERIOD2_START"
export PREV_PERIOD2_END="$PREV_PERIOD2_END"
export PREV_PERIOD2_TOTAL="$PREV_PERIOD2_TOTAL"
export PREV_PERIOD2_NOTE="$PREV_PERIOD2_NOTE"

# Schedule Configuration
export SCHEDULE_TYPE="$SCHEDULE_TYPE"
export SCHEDULE_HOUR="$SCHEDULE_HOUR"
export SCHEDULE_DAYS="$SCHEDULE_DAYS"
export SCHEDULE_CRON="$SCHEDULE_CRON"
EOF
    
    print_color $GREEN "✅ Configuration saved to $CONFIG_FILE"
}

# Function to show main menu
show_menu() {
    echo ""
    print_color $PURPLE "🎛️  MENU OPTIONS:"
    print_color $CYAN "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    print_color $WHITE "📝 Edit Configuration:"
    echo "   1-17) Edit specific configuration item"
    echo "   s)    Save configuration"
    echo "   t)    Test report generation"
    echo "   c)    Setup/Update crontab"
    echo "   r)    Reload/refresh display"
    echo "   q)    Quit"
    echo ""
    echo -n -e "${BLUE}Choose option: ${NC}"
}

# Function to setup crontab - CONFIGURABLE SINGLE SEND SCHEDULE
setup_crontab() {
    print_color $YELLOW "⚙️  Setting up crontab..."
    
    if [ -z "$SCHEDULE_CRON" ]; then
        print_color $RED "❌ No schedule configured"
        return 1
    fi
    
    # Remove existing entries
    crontab -l 2>/dev/null | grep -v "data-monitor" > /tmp/crontab.tmp 2>/dev/null || echo "" > /tmp/crontab.tmp
    
    # Always add daily data collection at midnight
    echo "0 0 * * * /opt/data-monitor/run.sh --collect # data-monitor daily collection" >> /tmp/crontab.tmp
    
    # Add configured report schedule (only one send schedule)
    echo "$SCHEDULE_CRON /opt/data-monitor/run.sh --send # data-monitor scheduled report" >> /tmp/crontab.tmp
    
    crontab /tmp/crontab.tmp
    rm /tmp/crontab.tmp
    
    print_color $GREEN "✅ Crontab updated successfully!"
    print_color $YELLOW "📋 Data collection: Daily at midnight"
    print_color $YELLOW "📋 Report send: $SCHEDULE_CRON"
    
    echo ""
    print_color $CYAN "Current cron jobs for data-monitor:"
    crontab -l 2>/dev/null | grep "data-monitor" | while read -r line; do
        print_color $WHITE "   $line"
    done
}

# Function to test report
test_report() {
    print_color $YELLOW "🧪 Testing report generation..."
    if [ -f "/opt/data-monitor/run.sh" ]; then
        /opt/data-monitor/run.sh --test
    else
        print_color $RED "❌ Report script not found"
    fi
}

# Main function
main() {
    print_header
    load_config
    
    # Check first-time setup
    if [ "$TELEGRAM_BOT_TOKEN" = "YOUR_BOT_TOKEN_HERE" ] || [ -z "$TELEGRAM_BOT_TOKEN" ]; then
        print_color $YELLOW "🆕 First time setup detected!"
        echo -n -e "${BLUE}Set up Telegram Bot Token now? (Y/n): ${NC}"
        read setup_token
        
        if [ "$setup_token" != "n" ] && [ "$setup_token" != "N" ]; then
            edit_config_item 1
            edit_config_item 2
            echo -n -e "${BLUE}Add phone number? (y/N): ${NC}"
            read add_phone
            if [ "$add_phone" = "y" ] || [ "$add_phone" = "Y" ]; then
                edit_config_item 3
            fi
        fi
    fi
    
    while true; do
        display_current_config
        show_menu
        read choice
        
        case $choice in
            1) edit_config_item "1" ;;
            2) edit_config_item "2" ;;
            3) edit_config_item "3" ;;
            4) edit_config_item "4" ;;
            5) edit_config_item "5" ;;
            6) edit_config_item "6" ;;
            7) edit_config_item "7" ;;
            8) edit_config_item "8" ;;
            9) edit_config_item "9" ;;
            10) edit_config_item "10" ;;
            11) edit_config_item "11" ;;
            12) edit_config_item "12" ;;
            13) edit_config_item "13" ;;
            14) edit_config_item "14" ;;
            15) edit_config_item "15" ;;
            16) edit_config_item "16" ;;
            17) edit_config_item "17" ;;
            s|S) save_config ;;
            t|T) test_report ;;
            c|C) setup_crontab ;;
            r|R) 
                load_config
                print_color $GREEN "✅ Reloaded"
                ;;
            q|Q) 
                print_color $GREEN "👋 Goodbye!"
                exit 0
                ;;
            *) 
                print_color $RED "❌ Invalid option"
                ;;
        esac
        
        echo ""
        echo -n -e "${YELLOW}Press Enter to continue...${NC}"
        read dummy
    done
}

# Check permissions
if [ ! -w "$(dirname "$CONFIG_FILE")" ]; then
    print_color $RED "❌ No write permission. Try: sudo $0"
    exit 1
fi

main