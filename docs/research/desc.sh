#!/bin/sh
OUT=/var/minis/workspace/jyfilemanager/docs/research/desc.tsv
: > "$OUT"
for p in "$@"; do
  d=$(curl -s --max-time 25 "https://pub.dev/api/packages/$p" | jq -r '(.latest.version // "?") + "\t" + (.latest.published[0:10] // "?") + "\t" + (.latest.pubspec.environment.sdk // "?") + "\t" + ((.latest.pubspec.description // "-") | gsub("\n";" "))[0:170]' 2>/dev/null)
  printf "%s\t%s\n" "$p" "$d" >> "$OUT"
done
cat "$OUT"
