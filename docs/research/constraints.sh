#!/bin/sh
# Show dependency version constraints for a package
for p in "$@"; do
  echo "##### $p"
  curl -s --max-time 25 "https://pub.dev/api/packages/$p" | jq -r '.latest.pubspec.dependencies | to_entries | map(.key+" => "+(.value|tostring)) | .[]'
done
