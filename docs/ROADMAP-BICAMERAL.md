# Phase 3 - Bicameral + SCN weights

v0 ships **person chamber only** (`PersonGovernor`). Stake / bicameral pieces are already in-tree for the next step.

## Already vendored

| Contract | Path | Status |
|----------|------|--------|
| `StakeVault` | `contracts/weight/StakeVault.sol` | Deployed on Anvil and Redbelly testnet; not in POV UI yet |
| `BicameralGovernor` | `contracts/governance/BicameralGovernor.sol` | Compiled; not wired as default |
| SCN paper base tier 0.1 | - | Spec only (same gap as upstream SCN) |

## Next implementation steps

1. Confirm with Redbelly whether κ ~= 10 addresses / identity is protocol-hard (SCN assumption A1).
2. Either:
   - Point UI / demos at `BicameralGovernor` (stake + person), or
   - Extend `PersonGovernor` into a thin bicameral wrapper.
3. Implement base tier weighting in registry / governor (`weight = 1/κ` per linked wallet, cap 1) - today person weight is 0/1. See also [TODO.md](./TODO.md) (link cap, rebind, unlink snapshot).
4. Preflight against Redbelly testnet Permission (extender policy: `treatExtenderAsBusiness = false` on testnet).

## Non-goals until then

- Do not curve stake (keep linear - split-neutral).
- Do not treat Mock adapter as production uniqueness.
