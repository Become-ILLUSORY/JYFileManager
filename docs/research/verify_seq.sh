#!/bin/sh
# Verify a list of package names, one API call each, sequential, safe
NAMES="$1"; OUT="$2"
: > "$OUT"
while IFS= read -r p; do
  [ -z "$p" ] && continue
  j=$(curl -s --max-time 25 "https://pub.dev/api/packages/$p")
  err=$(echo "$j" | jq -r '.error // empty' 2>/dev/null)
  if [ -n "$err" ]; then
    printf "%s\tNOT_FOUND\n" "$p" >> "$OUT"
    continue
  fi
  ver=$(echo "$j" | jq -r '.latest.version')
  pub=$(echo "$j" | jq -r '.latest.published[0:10]')
  sdk=$(echo "$j" | jq -r '.latest.pubspec.environment.sdk // "?"')
  s=$(curl -s --max-time 25 "https://pub.dev/api/packages/$p/score")
  likes=$(echo "$s" | jq -r '.likeCount // "?"')
  pts=$(echo "$s" | jq -r '.grantedPoints // "?"')
  plat=$(echo "$s" | jq -r '(.tags // []) | map(select(startswith("platform:"))) | map(sub("platform:";"")) | join(",")')
  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "$p" "$ver" "$pub" "$sdk" "$plat" "$likes" "$pts" >> "$OUT"
done < "$NAMES"
echo "DONE $(wc -l < $OUT)"
