#!/bin/sh
# Run pub.dev search for each query, output top 6 results with like count if available
OUT=/var/minis/workspace/jyfilemanager/docs/research/search_results7.txt
: > "$OUT"
while IFS= read -r q; do
  [ -z "$q" ] && continue
  enc=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "$q")
  res=$(curl -s --max-time 25 "https://pub.dev/api/search?q=$enc")
  echo "### $q" >> "$OUT"
  echo "$res" | jq -r '.packages[:6][] | .package' >> "$OUT" 2>/dev/null || echo "(no results)" >> "$OUT"
  echo "" >> "$OUT"
  sleep 0.3
done < /var/minis/workspace/jyfilemanager/docs/research/search_queries7.txt
echo DONE
wc -l "$OUT"
