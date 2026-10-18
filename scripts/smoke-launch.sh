#!/bin/bash
# Compatibility entry point. The production bundle is never launched with personal data.
set -euo pipefail
app=${1:?Pass the built Lisiere.app path}
output=${2:-"$(dirname "$app")/Validation-$(date +%Y%m%d-%H%M%S)"}
exec python3 "$(dirname "$0")/validate-release.py" "$app" --output "$output"
