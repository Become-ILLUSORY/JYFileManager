#!/bin/sh
# Print authoritative pub.dev tags (dart3-compatible, null-safe) for packages
OUT=/var/minis/workspace/jyfilemanager/docs/research/tags.tsv
: > "$OUT"
for p in "$@"; do
  s=$(curl -s --max-time 25 "https://pub.dev/api/packages/$p/score")
  d3=$(echo "$s" | jq -r '(.tags // []) | if index("is:dart3-compatible") then "D3-OK" else "NO" end')
  ns=$(echo "$s" | jq -r '(.tags // []) | if index("is:null-safe") then "nullsafe" else "unsafe" end')
  printf "%s\t%s\t%s\n" "$p" "$d3" "$ns" >> "$OUT"
done
cat "$OUT"
