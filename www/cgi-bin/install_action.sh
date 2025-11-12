#!/bin/sh
# install_action.sh (SSE) - improved flushing + heartbeat
# Put in /www/cgi-bin/ and chmod +x

# Output SSE headers
printf 'Content-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\n\r\n'

# Helper: send SSE data line
send_line() {
  # Ensure no NUL
  line="${1%$'\0'}"
  # Escape leading "/"? not necessary. Print as SSE data
  printf 'data: %s\n\n' "$line"
  # try to flush stdout
  # (printf should write immediately; uhttpd may buffer but awk ensures child flush)
}

# Helper: send SSE event name + data (optional)
send_event() {
  event="$1"
  data="$2"
  printf 'event: %s\n' "$event"
  printf 'data: %s\n\n' "$data"
}

# Run command and stream stdout+stderr, forcing flush via awk
run_cmd_stream() {
  cmd="$1"
  # Use sh -c to evaluate command string; redirect both stdout/stderr to awk,
  # awk prints and fflush() each line to minimize buffering.
  # Then read that output line-by-line and send as SSE.
  sh -c "$cmd" 2>&1 | awk '{ print; fflush(); }' | while IFS= read -r __line; do
    send_line "$__line"
  done
}

# small wrappers
send_info()    { send_line "[INFO] $1"; }
send_error()   { send_line "[ERROR] $1"; }
send_success() { send_line "[OK] $1"; }

# parse action (GET)
ACTION=""
if [ "$REQUEST_METHOD" = "GET" ]; then
  for kv in $(echo "$QUERY_STRING" | tr '&' '\n'); do
    k=$(echo "$kv" | cut -d= -f1)
    v=$(echo "$kv" | cut -d= -f2-)
    if [ "$k" = "action" ]; then ACTION=$(printf '%s' "$v" | sed 's/%20/ /g'); fi
  done
fi

# default repo dir
SRC_DIR="/root/StatusWRTIrfan"
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

# Start a heartbeat in background to keep connection alive (every N seconds)
HEARTBEAT_PID=""
start_heartbeat() {
  # send a lighter heartbeat to avoid flooding
  (
    while true; do
      printf 'data: %s\n\n' "[HEARTBEAT]" >/dev/stdout 2>/dev/null
      sleep 12
    done
  ) &
  HEARTBEAT_PID=$!
}

stop_heartbeat() {
  if [ -n "$HEARTBEAT_PID" ]; then
    kill "$HEARTBEAT_PID" 2>/dev/null || true
    HEARTBEAT_PID=""
  fi
}

# Ensure resources cleaned on exit
cleanup() {
  stop_heartbeat
  # final done event
  send_event "done" "CLOSED"
  exit 0
}
trap cleanup EXIT INT TERM

# improved functions (similar to earlier)
do_install_update() {
  send_info "Memulai update paket dan instalasi dependensi..."
  # update repo list
  run_cmd_stream "opkg update || true"
  send_info "opkg update selesai (best-effort)."

  # install packages (best-effort)
  for pkg in coreutils-sleep bc git git-http wget python3-requests python3-pip coreutils-base64; do
    send_info "Menginstal $pkg ..."
    run_cmd_stream "opkg install $pkg || true"
  done

  # pip
  send_info "pip3 install requests websocket-client (best-effort)"
  run_cmd_stream "pip3 install requests websocket-client 2>&1 || true"

  # append DHCP entries (as in original)
  send_info "Menambahkan entri domain di /etc/config/dhcp (append)..."
  run_cmd_stream "cat >> /etc/config/dhcp << 'EOF'
config domain
    option name 'HP_IRFAN'
    option ip '192.168.7.245'

config domain
    option name 'HP_TAB'
    option ip '192.168.7.106'

config domain
    option name 'HP_ANITA'
    option ip '192.168.7.220'

config domain
    option name 'HP_AQILLA'
    option ip '192.168.7.177'

config domain
    option name 'HP_JAMAL'
    option ip '192.168.7.169'

config domain
    option name 'LAPTOP'
    option ip '192.168.7.123'

config domain
    option name 'HP_AMAT'
    option ip '192.168.7.166'

config domain
    option name 'HP_BAPAK'
    option ip '192.168.7.233'

config domain
    option name 'CCTV'
    option ip '192.168.7.138'
EOF
echo \"[INFO] DHCP entries appended.\""

  # deploy files if repo exists
  if [ -n "$SRC_DIR" ] && [ -d "$SRC_DIR" ]; then
    send_info "Men-deploy file dari repo (jika ada)..."
    run_cmd_stream "mkdir -p /usr/lib/lua/luci/controller /usr/lib/lua/luci/view /www/cgi-bin /www || true"
    # move operations (best-effort)
    run_cmd_stream "mv '$SRC_DIR/usr/lib/lua/luci/controller/status_monitor.lua' /usr/lib/lua/luci/controller/ 2>/dev/null || true"
    run_cmd_stream "mv '$SRC_DIR/usr/lib/lua/luci/view/status_monitor.htm' /usr/lib/lua/luci/view/ 2>/dev/null || true"
    run_cmd_stream "mv '$SRC_DIR/usr/bin/online.sh' /usr/bin/ 2>/dev/null || true"
    run_cmd_stream "mv '$SRC_DIR/usr/bin/send_telegram.py' /usr/bin/ 2>/dev/null || true"
    run_cmd_stream "mv '$SRC_DIR/www/'*.html /www/ 2>/dev/null || true"
    run_cmd_stream "mv '$SRC_DIR/www/cgi-bin/'* /www/cgi-bin/ 2>/dev/null || true"
    run_cmd_stream "chmod +x /www/cgi-bin/* /usr/bin/online.sh /usr/bin/send_telegram.py 2>/dev/null || true"
    send_info "Deploy finished (best-effort)."
  else
    send_info "Repo $SRC_DIR tidak ditemukan — melewatkan deploy."
  fi

  send_success "install_update selesai."
}

do_clone() {
  send_info "Meng-clone repository StatusWRTIrfan..."
  cd /root || send_error "Gagal cd /root"
  if [ -d "$SRC_DIR" ]; then
    send_info "Direktori $SRC_DIR sudah ada — menghapus dulu..."
    run_cmd_stream "rm -rf '$SRC_DIR' || true"
  fi
  # force progress output from git, and pipe through awk (run_cmd_stream forces awk)
  run_cmd_stream "git clone --progress https://github.com/irfanFRizki/StatusWRTIrfan.git"
  # if clone succeeded, update SRC_DIR
  if [ -d "/root/StatusWRTIrfan" ]; then
    SRC_DIR="/root/StatusWRTIrfan"
    send_success "Clone repository selesai."
  else
    send_error "Clone gagal atau folder tidak ditemukan."
  fi
}

do_update_vnstat_nlbwmon() {
  if [ ! -d "$SRC_DIR" ]; then send_error "Repo belum di-clone: $SRC_DIR tidak ada."; return 1; fi
  send_info "Mengganti vnstat.db..."
  run_cmd_stream "mkdir -p /etc/vnstat 2>/dev/null || true"
  run_cmd_stream "rm -f /etc/vnstat/vnstat.db 2>/dev/null || true"
  if [ -f "$SRC_DIR/vnstat.db" ]; then
    run_cmd_stream "mv '$SRC_DIR/vnstat.db' /etc/vnstat/ 2>/dev/null || true"
    send_success "vnstat.db diganti."
  else
    send_error "vnstat.db tidak ditemukan di repo."
  fi
  send_info "Memperbarui /etc/nlbwmon/ (best-effort)..."
  run_cmd_stream "rm -rf /etc/nlbwmon/* 2>/dev/null || true"
  run_cmd_stream "cp -r '$SRC_DIR/etc/nlbwmon/'* /etc/nlbwmon/ 2>/dev/null || true"
  send_success "/etc/nlbwmon diperbarui (jika ada)."
}

do_create_nftables() {
  send_info "Membuat /etc/nftables.d/11-ttl.nft (FIX TTL 63)..."
  run_cmd_stream "mkdir -p /etc/nftables.d 2>/dev/null || true"
  cat >/etc/nftables.d/11-ttl.nft <<'EOF'
chain mangle_postrouting_ttl65 {
    type filter hook postrouting priority 300; policy accept;
    counter ip ttl set 65
}

chain mangle_prerouting_ttl65 {
    type filter hook prerouting priority 300; policy accept;
    counter ip ttl set 65
}
EOF
  send_info "File 11-ttl.nft ditulis."
  run_cmd_stream "/etc/init.d/firewall restart 2>&1 || true"
  send_success "Firewall direstart."
}

do_install_ipk() {
  if [ ! -d "$SRC_DIR/ipk" ]; then send_error "Direktori $SRC_DIR/ipk tidak ditemukan."; return 1; fi
  send_info "Menginstal .ipk..."
  for ipk in "$SRC_DIR"/ipk/*.ipk; do
    [ -f "$ipk" ] || continue
    send_info "Menginstal $(basename "$ipk") ..."
    run_cmd_stream "opkg install '$ipk' || true"
  done
  send_success "Instal .ipk selesai."
}

do_install_all() {
  send_info "Memulai install_all (best-effort)..."
  do_install_update
  if [ ! -d "$SRC_DIR" ]; then do_clone; else send_info "Repo sudah ada; melewati clone."; fi
  do_update_vnstat_nlbwmon
  do_create_nftables
  do_install_ipk
  send_success "install_all selesai."
}

# Start heartbeat
start_heartbeat

# Execute requested action
case "$ACTION" in
  install_update) do_install_update ;;
  clone)          do_clone ;;
  update)         do_update_vnstat_nlbwmon ;;
  nftables)       do_create_nftables ;;
  install_ipk)    do_install_ipk ;;
  install_all)    do_install_all ;;
  *) send_error "Action tidak dikenal: $ACTION" ;;
esac

# Stop heartbeat, send final done event
stop_heartbeat
send_event "done" "OK"
# allow trap/cleanup to exit
exit 0
