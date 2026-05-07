#!/usr/bin/env bash
set -euo pipefail

# Pack a Claude Desktop Extension (.mcpb) bundle.
#
# pnpm's default isolated layout uses symlinks under node_modules/.pnpm/
# that do not survive the .mcpb pack/unpack round-trip: top-level packages
# get materialized but their transitive deps (e.g. zod-to-json-schema reached
# from @modelcontextprotocol/sdk) become unreachable. This script installs a
# flat, prod-only node_modules just for packing, packs, and restores the
# original dev install on exit.

cd "$(dirname "$0")/.."

DEV_NM=.nm-dev

if [ -d "$DEV_NM" ]; then
  echo "Refusing to run: $DEV_NM already exists from a previous interrupted pack." >&2
  echo "Either restore (rm -rf node_modules && mv $DEV_NM node_modules)"           >&2
  echo "or discard (rm -rf $DEV_NM)."                                              >&2
  exit 1
fi

restore() {
  if [ -d "$DEV_NM" ]; then
    rm -rf node_modules
    mv "$DEV_NM" node_modules
  fi
}
trap restore EXIT

mv node_modules "$DEV_NM"

pnpm install --node-linker=hoisted --prod --frozen-lockfile --ignore-scripts

rm -f *.mcpb
pnpm dlx @anthropic-ai/mcpb pack

echo "Bundle: $(ls *.mcpb)"
