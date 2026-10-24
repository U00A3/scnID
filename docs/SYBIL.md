# Sybil model - Lab vs SCN vs SCNID

Readable narrative (what ships, scorecard, soft gates before nullifiers): [`OVERVIEW-LIGHT.md`](./OVERVIEW-LIGHT.md).

Redbelly Permission / CAT answers: *may this address write?*  
It does **not** answer: *is this a unique human?* One KYC can hold several addresses; the grouping is not on-chain.

## Comparison

| | Lab (shelved POV) | Pure SCN (repo) | SCNID (this) |
|--|-------------------|-----------------|--------------|
| Ballot unit | Identity NFT / DB | `person` on-chain | `person` on-chain |
| Multi-wallet | `linkWallet` | rebind only | **link** (+ rebind kept) |
| Entry | CAT -> Join | CAT + adapter | CAT + adapter |
| Default uniqueness | Soft (tenure, Discord...) | Attestation / later nullifier | Mock -> attest -> nullifier |
| Vote storage | Off-chain hybrid | On-chain bicameral | On-chain person chamber (v0) |
| Weight maths | 1 or RBNT | Paper 0.1; code 0/1 | 0/1 now; 0.1 later |

## What SCNID claims

- Honest member: one Join, link other wallets -> **one** person vote.
- Farm of Joins under Mock adapter: still N persons (same honesty gap as Lab Join).
- Attestation / nullifier: raise the cost of N fake persons.
- Never: 1 network KYC = 1 vote (map not exposed).

## Lab reference

Community write-up of the shelved Lab compromise:  
https://github.com/U00A3/daoLab/blob/main/docs/OVERVIEW-LIGHT.md  
(section "How we defend one ballot per person")
