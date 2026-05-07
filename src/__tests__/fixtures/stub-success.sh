#!/usr/bin/env bash
set -euo pipefail
B64=$(cat "$(dirname "$0")/tiny.png.b64")
cat <<EOF
{"status":"success","image_base64":"$B64","metadata":{"width":1920,"height":1440,"captured_at":"2026-05-06T19:23:45.123Z","wait_duration_ms":42,"device_name":"iPhone 15 Pro Desk View"},"error_code":null,"error_message":null}
EOF
