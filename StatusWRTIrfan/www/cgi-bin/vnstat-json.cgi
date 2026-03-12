#!/bin/sh

# Debug log ke /tmp/vnstat-json.log
echo "---- $(date) ----" >> /tmp/vnstat-json.log
echo "QUERY_STRING=$QUERY_STRING" >> /tmp/vnstat-json.log

iface=$(printf '%s\n' "$QUERY_STRING" | sed -n 's/.*iface=\([^&]*\).*/\1/p')
[ -z "$iface" ] && iface=br-lan
echo "iface=$iface" >> /tmp/vnstat-json.log

echo "Access-Control-Allow-Origin: *"
echo "Content-Type: application/json"
echo ""

if [ -x /usr/bin/vnstat ]; then
  /usr/bin/vnstat --json -i "$iface" 2>> /tmp/vnstat-json.log
else
  echo '{"error":"vnstat not found"}'
fi
