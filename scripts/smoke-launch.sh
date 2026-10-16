#!/bin/bash
# Catch dyld/signing failures that signature verification and Debug tests cannot detect.
set -euo pipefail
app=${1:?Pass the built Lisiere.app path}
launch_log=$(mktemp -t lisiere-launch)
"$app/Contents/MacOS/Lisiere" > "$launch_log" 2>&1 &
app_pid=$!
cleanup() {
  kill "$app_pid" 2>/dev/null || true
  wait "$app_pid" 2>/dev/null || true
  rm -f "$launch_log"
}
trap cleanup EXIT
sleep 5
if ! kill -0 "$app_pid" 2>/dev/null; then
  cat "$launch_log"
  echo "Lisière exited during launch." >&2
  exit 1
fi
echo "Lisière stayed running through startup."
