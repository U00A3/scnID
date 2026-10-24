# Redbelly testnet notes (chain 153)

## Block time vs wall clock

`PersonGovernor.state()` uses **`block.timestamp`**, not the browser clock.

A proposal stays **Pending** until:

```text
block.timestamp >= voteStart
```

Then it becomes **Active** until `voteEnd`. Vote buttons in the UI unlock only when on-chain `state` is Active.

### What you may see in the UI

If Redbelly testnet stalls or produces blocks slowly, wall-clock time can pass `voteStart` while the chain is still behind. The ballot then shows something like:

> On-chain status is still Pending - waiting for Redbelly block time to pass the open stamp (…). Vote buttons unlock when state becomes Active.

That is **honest**: casting `castPersonVote` earlier would revert with `ProposalNotActive`. The UI does not pretend wall time equals chain time.

### How to check

```bash
export PATH="$PATH:$HOME/.foundry/bin"
RPC=https://governors.testnet.redbelly.network
G=0x5949F2aD56ee79BB088fb38272bb4004847A721d   # or your governor

cast block latest -f number --rpc-url $RPC
cast block latest -f timestamp --rpc-url $RPC
date -u +%s
cast call $G "state(uint256)(uint8)" 1 --rpc-url $RPC
# 0 = Pending, 1 = Active, 2 = Defeated, 3 = Succeeded, 4 = Canceled
```

If `number` / `timestamp` do not advance across several calls, the network (or RPC view) is stuck. When blocks resume, Pending proposals that have passed their open stamp flip to Active without redeploy.

### POV implication

- Short **votingDelay** (e.g. 30 s) is fine when the testnet is healthy.
- During stalls, demos should wait for Active (or cancel and re-propose after the chain catches up).
- Anvil local demos are not affected the same way (local clock advances with blocks under your control).

This is a testnet / ops caveat, not a bug in Join or personhood storage.
