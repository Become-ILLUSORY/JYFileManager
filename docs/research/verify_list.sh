#!/bin/sh
# Usage: sh verify_list.sh names.txt out.tsv  (parallel)
NAMES="$1"; OUT="$2"
: > "$OUT"
export OUT
cat "$NAMES" | tr -d '\r' | grep -v '^$' | xargs -P 6 -n 1 sh -c '
p="$1"
j=$(curl -s --max-time 30 "https://pub.dev/api/packages/$p")
s=$(curl -s --max-time 30 "https://pub.dev/api/packages/$p/score")
if [ "$(echo "$j" | jq -r ".error // empty" 2>/dev/null)" != "" ]; then
  printf "%s\tNOT_FOUND\n" "$p" >> "$OUT"
  exit 0
fi
ver=$(echo "$j" | jq -r ".latest.version")
pub=$(echo "$j" | jq -r ".latest.published" | cut -c1-10)
sdk=$(echo "$j" | jq -r ".latest.pubspec.environment.sdk // \"?\"")
deps=$(echo "$j" | jq -r "(.latest.pubspec.dependencies // {}) | keys | join(\",\")" 2>/dev/null)
likes=$(echo "$s" | jq -r ".likeCount // \"?\"")
pts=$(echo "$s" | jq -r ".grantedPoints // \"?\"")
plat=$(echo "$s" | jq -r "(.tags // []) | map(select(startswith(\"platform:\"))) | map(sub(\"platform:\";\"\")) | join(\",\")")
# own Dart3 judgement: upper bound must allow >=3.0.0
d3=$(python3 -c "
import sys,re
s=sys.argv[1]
m=re.search(r\"<\s*(\d+)\", s)
if m:
    print(\"D3-OK\" if int(m.group(1))>=4 else (\"D3-BLOCKED\" if int(m.group(1))<=3 else \"?\"))
else:
    print(\"D3-OK?\")
" "$sdk" 2>/dev/null)
printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "$p" "$ver" "$pub" "$sdk" "$plat" "$likes" "$pts" "$d3" "$deps" >> "$OUT"
' _ 
echo "DONE $(wc -l < $OUT)"
