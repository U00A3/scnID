#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Default: testnet (public UI). Pass `local` for Anvil addresses.
target="${1:-testnet}"
case "$target" in
  local) src="$ROOT/broadcast/local-addresses.json" ;;
  testnet) src="$ROOT/broadcast/testnet-addresses.json" ;;
  *)
    echo "usage: $0 [local|testnet]" >&2
    exit 1
    ;;
esac
dst="$ROOT/ui/src/addresses.json"
if [[ ! -f "$src" ]]; then
  echo "missing $src" >&2
  exit 1
fi
cp "$src" "$dst"
echo "synced ($target) -> $dst"
