#!/usr/bin/env bash
set -euo pipefail
export PATH="${HOME}/.foundry/bin:${PATH}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
RPC="${RPC_URL:-http://127.0.0.1:8545}"

if [[ ! -f broadcast/local-addresses.json ]]; then
  echo "Missing broadcast/local-addresses.json - run LocalDeploy first" >&2
  exit 1
fi

forge script script/DemoJoin.s.sol:DemoJoin --rpc-url "$RPC" --broadcast --slow -vv

# Advance Anvil time so registrations are older than the proposal (RegisteredTooLate).
curl -s -X POST "$RPC" -H 'content-type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"evm_increaseTime","params":[5]}' >/dev/null
curl -s -X POST "$RPC" -H 'content-type: application/json' \
  --data '{"jsonrpc":"2.0","id":2,"method":"evm_mine","params":[]}' >/dev/null

forge script script/DemoVote.s.sol:DemoVote --rpc-url "$RPC" --broadcast --slow -vv
echo "demo-scenario finished"
