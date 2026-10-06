#!/bin/sh
# Verify packages: name, version, published, sdk, platforms(from tags), likes, dart3, deps
OUT=${OUTFILE:-/var/minis/workspace/jyfilemanager/docs/research/pkg_verify.tsv}
for p in "$@"; do
  j=$(curl -s --max-time 25 "https://pub.dev/api/packages/$p")
  s=$(curl -s --max-time 25 "https://pub.dev/api/packages/$p/score")
  if [ "$(echo "$j" | jq -r '.error // empty' 2>/dev/null)" != "" ]; then
    echo -e "$p\tNOT_FOUND" >> "$OUT"
    continue
  fi
  ver=$(echo "$j" | jq -r '.latest.version')
  pub=$(echo "$j" | jq -r '.latest.published' | cut -c1-10)
  sdk=$(echo "$j" | jq -r '.latest.pubspec.environment.sdk // "?"')
  deps=$(echo "$j" | jq -r '(.latest.pubspec.dependencies // {}) | keys | join(" ")' 2>/dev/null)
  likes=$(echo "$s" | jq -r '.likeCount // "?"')
  pts=$(echo "$s" | jq -r '.grantedPoints // "?"')
  d3=$(echo "$s" | jq -r '(.tags // []) | if index("is:dart3-compatible") then "D3" else "noD3" end')
  plat=$(echo "$s" | jq -r '(.tags // []) | map(select(startswith("platform:"))) | map(sub("platform:";"")) | join(",")')
  echo -e "$p\t$ver\t$pub\t$sdk\t$plat\t$likes\t$pts\t$d3\t$deps" >> "$OUT"
done
echo "DONE $(wc -l < $OUT)"
