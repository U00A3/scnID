# SCNID vision

Community-facing inventory, sybil scorecard, and pre-V3 suggestions live in [`OVERVIEW-LIGHT.md`](./OVERVIEW-LIGHT.md).

## One sentence

Members get **Lab-like Join + link**, the chain stores a **Personhood `person` key**, voting is **one person one ballot** on-chain; adapters upgrade from mock -> attestation -> nullifier without rewriting the governor.

## Why combine SCN and Identity

| Source | Keep |
|--------|------|
| **SCN** ([Njaybby](https://github.com/Njaybby) / [scn-governance](https://github.com/Njaybby/scn-governance)) | On-chain person unit, adapter swap, `sybilBound()`, bicameral/SCN weights later |
| **Lab Identity** | Join UX, multi-wallet **link**, honest "no KYC map" framing |

Pure SCN today: one `voter` address + rebind, attestation-first.  
Pure Lab: Identity NFT + off-chain ballots + social gates.  
**SCNID:** link many wallets -> one on-chain `person` -> vote on-chain.

## Officer cancel

Officer UI exposes **Cancel vote** for Pending / Active proposals. On-chain, only the **proposer** or **owner** may call `cancel`.

**Why keep the button:** same escape hatch as OpenZeppelin Governor and Compound - guardian / proposer can stop a bad or mistaken proposal before it settles, instead of waiting out the full voting window. SCNID is signalling-only in v0, but the same ops hygiene still applies.

## Non-goals (v0)

- Draft / review office
- Cryptographic sealed ballots (commit-reveal) - UI Hidden is soft only; see SEALED-VOTING.md
- Full bicameral + base tier 0.1 (see ROADMAP-BICAMERAL)
- Mainnet production IAM

## Adapter ladder

1. **MockPersonhoodAdapter** - POV Join without attestors (sybil bound unbounded; demo only)
2. **AttestedPersonhoodAdapter** - bridge until network nullifiers exist
3. **ReceptorNullifierAdapter** - enabled when Redbelly ships iden3 V3

Attestation must not become permanent religion: publish `humanRef` rules, keep assurance honest, plan to demote attestors to corroborators when nullifiers land.
