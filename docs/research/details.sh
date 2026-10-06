#!/bin/sh
# Print pubspec + repo + homepage for a package
for p in "$@"; do
  echo "##### $p"
  curl -s --max-time 25 "https://pub.dev/api/packages/$p" | jq -r '"version: "+.latest.version, "repo: "+(.latest.pubspec.repository // .latest.pubspec.homepage // "none"), "desc: "+(.latest.pubspec.description // ""), ("deps: "+((.latest.pubspec.dependencies // {})|to_entries|map(.key+"@"+(.value|tostring))|join(" ; "))), ("platforms_raw: "+((.latest.pubspec.flutter.plugin.platforms // {})|keys|join(",")))'
done
