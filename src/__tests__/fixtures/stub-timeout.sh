#!/usr/bin/env bash
set -euo pipefail
B64=$(cat "$(dirname "$0")/tiny.png.b64")
cat <<EOF
{"status":"timeout","image_base64":"$B64","metadata":{"width":1920,"height":1440,"captured_at":"2026-05-06T19:24:00.000Z","wait_duration_ms":300000,"device_name":"iPhone 15 Pro Desk View"},"error_code":"timeout","error_message":"Stability timeout reached"}
EOF
