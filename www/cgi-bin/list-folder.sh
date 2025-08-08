#!/bin/sh
# list-folder.sh – List isi direktori dalam format JSON

echo "Content-Type: application/json"
echo ""

# Ambil parameter path
DIR=$(echo "$QUERY_STRING" \
  | sed -e 's/+/ /g' \
        -e 's/%2F/\//g' \
        -e 's/.*path=//')

# Cegah path traversal — hanya path absolut
case "$DIR" in
  /*) ;;
  *) echo "[]"; exit 0;;
esac

# Baca isi direktori
echo "["
first=true
ls -A "$DIR" 2>/dev/null | while IFS= read -r f; do
  # Comma pemisah jika bukan elemen pertama
  if [ "$first" = true ]; then
    first=false
  else
    printf ",\n"
  fi

  # Tentukan apakah directory
  if [ -d "$DIR/$f" ]; then
    printf '  { "name": "%s", "isDirectory": true }' "$f"
  else
    printf '  { "name": "%s", "isDirectory": false }' "$f"
  fi
done
echo
echo "]"
