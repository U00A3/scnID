# TODO (post-review)

Notes from an early contract review of the personhood registry and the SCN paper weight idea (Njaybby / scn-governance lineage). Not a full roadmap - a punch list so findings are not lost.

Related: [OVERVIEW-LIGHT](./OVERVIEW-LIGHT.md) · [ROADMAP-BICAMERAL](./ROADMAP-BICAMERAL.md) · [SYBIL](./SYBIL.md)

---

## Direction we like

**Linking + paper base weight 0.1**

- Weight `0.1` per linked wallet, **capped at 1.0** (κ ≈ 10).
- Then ten Mock Joins with one wallet each ≈ one Join with ten links - farming the Mock adapter becomes relatively pointless for *weight*, not just for honest UX.
- Today `personWeightOf` is still **0/1**. Bicameral / SCN weight wiring is Phase 3; this is the intended person-side story when we leave 0/1.

---

## Registry findings (actionable)

### 1. Rebind leaves the old primary linked (and able to vote)

**Today:** `completeRebind` moves `voter` to the new address and `_addWallet`s the new one if needed, but **keeps the old primary in `_wallets`**. Any linked wallet (including the old primary) can still pass `isActiveVoter` and cast the person ballot.

**Intent in code:** keep history / do not wipe the old address from the person.

**TODO:**

- [ ] Decide product rule: after rebind, should the old primary stay a **secondary** (current), be **auto-unlinked**, or stay linked but **blocked from casting** until re-linked via offer?
- [ ] Implement the chosen rule on-chain (prefer explicit behaviour over silent surprise).
- [ ] Document in OVERVIEW / Officer-facing copy either way.

### 2. Any linked wallet can cast the person vote (not only primary)

**Today:** `PersonGovernor.castPersonVote` + `registry.isActiveVoter` - one ballot per `person`, signed from **any** linked, permissioned wallet.

**Intent:** Lab-style UX (link wallets, vote from whichever you hold).

**TODO:**

- [ ] Keep as designed unless we explicitly want primary-only casting.
- [ ] Make this loud in docs / UI (not a silent "finding").
- [ ] Optional: event / indexer note "cast from linked wallet X for person P".

### 3. No cap on linked wallets; revoke walks the full list

**Today:** unbounded `_wallets[person]` growth; `revoke` iterates all.

**TODO:**

- [ ] Cap linked wallets at **10** (align with SCN κ / paper 0.1 × 10 = 1).
- [ ] Revert `acceptLink` / `_addWallet` when at cap.
- [ ] Revisit gas of `revoke` once cap exists (loop of 10 is fine).

### 4. Unlinked wallet can relink to another person immediately

**Today:** after unlink, `unlinkCooldown` gates **another unlink** via `unlinkReadyAt`, but a free wallet can **Join or accept a link offer elsewhere** without a "cooled" rebind-to-other-person delay tied to weight.

**Review note:** fine while weight is 0/1; **needs a snapshot / cooldown story once weight depends on links**.

**TODO:**

- [ ] While weight is 0/1: document as known; optional soft cooldown later.
- [ ] Before 0.1 weights: define snapshot rule (e.g. links counted only if linked before `voteStart` / proposal `createdAt`, and/or post-unlink cooldown before counting toward another person's weight).
- [ ] Add tests for "unlink then immediately inflate another person's link set".

---

## Suggested priority

| Priority | Item | Why |
|----------|------|-----|
| Now (docs) | Loud docs for "any linked wallet may cast" | Cheap clarity |
| Soon (contract) | Link cap = 10 | Matches paper κ; bounds revoke |
| Soon (contract) | Explicit rebind policy for old primary | Removes ambiguity |
| Next (weight) | 0.1 per link, cap 1 + snapshot rules | Anti-farm + paper; needs unlink/relink policy |

Redeploy of `PersonhoodRegistry` / governor on testnet is required for on-chain items (gas on 153 is painful - batch when ready).

---

## Out of scope here

- Soft Hidden / commit-reveal (see SEALED-VOTING).
- Attestation primary flip / nullifier V3 (see ATTESTATION-BRIDGE, OVERVIEW-LIGHT).
- Tenure / Discord / XP soft gates (product bridge, not this registry punch list).
