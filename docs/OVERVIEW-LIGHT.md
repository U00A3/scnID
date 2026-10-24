# SCNID - how it works (for the community)

**For:** members, guests, anyone who does not want contract names first  
**Site:** [scnid.mynode.uk](https://scnid.mynode.uk) (hosted demo; **UI source is private**, not in the public git tree)  
**Deeper notes:** [SYBIL](./SYBIL.md) · [ATTESTATION-BRIDGE](./ATTESTATION-BRIDGE.md) · [SEALED-VOTING](./SEALED-VOTING.md) · [VISION](./VISION.md)  
**Lab sibling** (soft gates in a hybrid urn): [daoLab OVERVIEW-LIGHT](https://github.com/U00A3/daoLab/blob/main/docs/OVERVIEW-LIGHT.md)

This is **not** an official Redbelly Network product. It is an independent POV / POC: Lab-like Join + link, an on-chain **person** unit, and a person-chamber vote on Redbelly testnet.

**Attribution:** substantial SCN / personhood ideas and code lineage come from [Njaybby/scn-governance](https://github.com/Njaybby/scn-governance) ([Njaybby](https://github.com/Njaybby), MIT). See the README Credits section and [`NOTICE`](../NOTICE).

---

## Three ideas, one roof

```text
Door (CAT + Join)  ->  Person key on-chain  ->  Urn (1 person = 1 ballot)
```

**The door.** Connect a wallet on Redbelly Testnet. Permission / CAT must allow the address to write. Join registers you through the current **personhood adapter** (today: Mock). There is no second KYC inside SCNID. The network already gated write access; we open membership.

**The person.** The chain stores a `person` key and which wallets belong to it. Link more wallets under the same person. Honest flow: one Join, then link - not ten Joins.

**The urn.** Officer opens a signalling proposal. Registered persons vote on-chain (`castPersonVote`). Soft **Hidden** can hide running scores in the UI. Cancel exists for proposer / owner (Pending or Active). Stake chamber and SCN paper weights are later (see ROADMAP-BICAMERAL).

```text
Guest (CAT wallet) → Join → person
person → link wallets (optional)
person → vote while Active
Officer / owner → propose, cancel
```

---

## What ships today (honest inventory)

| Piece | Status | Sybil / honesty note |
|-------|--------|----------------------|
| CAT / Permission gate | Live (network) | Write access only - **not** uniqueness |
| `PersonhoodRegistry` Join + Link | Live | One ballot per `person` for honest users |
| Mock adapter (primary) | Live POV | **Unbounded** - N Joins = N persons |
| Attested adapter | Deployed, not primary | Ready as bridge when we flip primary |
| Nullifier adapter | Deployed stub | Wait for Redbelly iden3 V3 |
| PersonGovernor propose / vote / cancel | Live | Signalling only; no execution payload |
| Soft Hidden tallies | Live (UI tag) | Anti-suggestion; tallies still public on-chain |
| Commit-reveal | Docs only | Desired for real sealed ballots |
| Tenure / XP / Discord gates | **Not in SCNID product** | Lab has them; we recommend them as a bridge layer below |
| Stake / bicameral UI | Vault address only | Phase 3 |

**What we never promise:** 1 network KYC = 1 vote. Redbelly does not expose that map on-chain.

---

## The problem the network does not solve for us

CAT says: *this wallet may write on testnet*. It does not say: *this is one human*.

One person can hold many wallets. If we counted "one address = one vote", ten Joins would mean ten ballots.

SCNID's foundation (same idea as Lab Identity):

- **Person votes, not the wallet.** Linked wallets share one ballot.
- **Limit:** anyone who does ten separate Joins under Mock still has ten persons. That is why further layers exist.

---

## Sybil resistance today - scorecard

| Defence | In SCNID now? | What it actually does |
|---------|---------------|------------------------|
| 1 person = 1 ballot (link wallets) | Yes | Stops honest multi-wallet double voting |
| Block Join-after-proposal (`RegisteredTooLate`) | Yes | Stops walking into an open vote with a brand-new person |
| Mock uniqueness | Weak | Demo only - farm of Joins still works |
| Attestation primary | Available, off | Raises cost if attestors are honest |
| Nullifier | Not yet | Real uniqueness target when V3 lands |
| Tenure before open | No | Lab: membership age gate |
| XP threshold | No | Lab: empty Identity farms fail hard votes |
| Discord link gate | No | Lab: social layer, not membership; still needs wallet sig |
| Allowlist | No | Lab: closed / emergency urn |
| Soft Hidden / commit-reveal | Soft Hidden only | Secrecy axis - **separate** from sybil |

**Bottom line for v0:** good UX and an honest on-chain person unit for **cooperative** demos. Against a motivated farm under Mock, resistance is **low**. That matches Lab's light mode without tenure / Discord / XP.

---

## Vision before V3 nullifiers - what we suggest

Nullifiers are the destination for uniqueness. Until Redbelly ships them, we want a **layered bridge**, not a single silver bullet.

### 1. Flip primary to attestation (chain)

Use `AttestedPersonhoodAdapter` as primary (see ATTESTATION-BRIDGE). Publish the `humanRef` rule. Keep assurance honest (not "100% unique"). When nullifiers arrive, demote attestation to corroborator.

### 2. Soft gates (Lab playbook, adapted to on-chain person)

Borrow the knobs from [Lab's defence write-up](https://github.com/U00A3/daoLab/blob/main/docs/OVERVIEW-LIGHT.md) - they do not prove one human, they make farms **costly or useless on high-stakes votes**:

| Gate | Idea for SCNID | Helps against |
|------|----------------|---------------|
| **Tenure** | Person must exist for N time *before* `voteStart` (stronger than today's Join-after-open block) | Fresh Join farms for elections |
| **XP / reputation** | Optional threshold to cast (prestige gate, not vote weight) | Empty person farms |
| **Discord (or similar)** | Link one account → one person; gate on hard votes only | Low-effort sock farms; still needs wallet signature |
| **Allowlist** | Named persons only for closed / emergency votes | Everything except the list |

Suggested tightness (same spirit as Lab):

| Mode | Typical set | Why |
|------|-------------|-----|
| **Light POV** | Mock or attest, no soft gates, Live or Hidden | Fast demo; farm cut less on purpose |
| **Hard signalling** | Attest + tenure + XP + Discord + Hidden / commit-reveal | High-stakes community signal |
| **Closed** | Hard + allowlist | Named people only |

### 3. Sealed ballots (secrecy, not sybil)

Soft Hidden is shipped. **Commit-reveal** is the desired upgrade so mid-vote scores are not public on-chain either (SEALED-VOTING). Secrecy does not replace uniqueness; both matter.

### 4. Keep the honest path obvious

Always: one Join, link wallets, one ballot. Never reward more Joins or more linked addresses with more votes.

---

## What SCNID does not promise (yet)

- That Mock Join is production uniqueness.
- That attestation equals 1 KYC = 1 vote.
- That Discord alone can cast or prove a human.
- That soft Hidden is cryptographic secrecy.
- That explorer alone proves every person is a unique human.
- That stake / bicameral weighting is live in the POV UI.

A farm of ten Joins **still exists** as a cost (CAT + Join gas) under Mock. We do not pretend it vanished. On a light POV vote that is acceptable; on a hard vote soft gates + attestation should keep fresh persons out; after V3, nullifiers should carry uniqueness.

---

## Where to see it

| Where | What |
|-------|------|
| [scnid.mynode.uk](https://scnid.mynode.uk) | Join, Link, Vote, Officer, Contracts footer |
| This file | Inventory, sybil scorecard, pre-V3 suggestions |
| [SYBIL.md](./SYBIL.md) | Lab vs SCN vs SCNID table |
| [ATTESTATION-BRIDGE.md](./ATTESTATION-BRIDGE.md) | How to enable attestation |
| [TESTNET-NOTES.md](./TESTNET-NOTES.md) | Pending vs Active when block time lags |

**In one sentence.** SCNID does not know the human behind network KYC; it knows an on-chain **person**. An honest member Joins once, links wallets, and has one ballot. Today Mock is demo-weak against farms; before nullifiers we suggest attestation plus Lab-style tenure / XP / Discord / allowlist on hard votes - then V3 nullifiers as the uniqueness destination.
