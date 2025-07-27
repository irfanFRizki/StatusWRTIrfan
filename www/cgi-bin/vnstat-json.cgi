#!/bin/sh
iface=$(printf '%s\n' "$QUERY_STRING" | sed -n 's/.*iface=\([^&]*\).*/\1/p')
[ -z "$iface" ] && iface=br-lan

echo "Access-Control-Allow-Origin: *"
echo "Content-Type: application/json"
echo ""

if [ -x /usr/bin/vnstat ]; then
  /usr/bin/vnstat --json -i "$iface"
else
  echo '{"error":"vnstat not found"}'
fi
