# Attestation bridge (not the destination)

## Role

`AttestedPersonhoodAdapter` is a **temporary** primary (or corroborator) while Redbelly lacks iden3 V3 nullifiers.

It proves uniqueness only as far as named attestors are honest and derive `humanRef` the same way for the same person.

## How SCNID uses it

| Stage | Primary adapter | Notes |
|-------|-----------------|-------|
| POV local | `MockPersonhoodAdapter` | Unbounded sybil bound - demo Join |
| Bridge | `AttestedPersonhoodAdapter` | Owner sets attestors + threshold; publish `humanRef` rule |
| Target | `ReceptorNullifierAdapter` | Deployed disabled; enable when V3 exists |

Swap primary with `PersonhoodRegistry.setPrimaryAdapter(address)` (owner).

## Enabling attestation on a deploy

1. Deploy already includes `attestedAdapter` (see `broadcast/local-addresses.json`).
2. Owner: `attested.setAttestor(addr, true)` (and threshold).
3. Owner: `registry.setPrimaryAdapter(attested)`.
4. Publish derivation rule for `humanRef` (roster id, salted account id, etc.).
5. Join evidence: `abi.encode(humanRef, deadline, signatures[])` - signatures sorted by signer.

## What we refuse to pretend

- Attestation is not 1 KYC = 1 vote.
- Colluding attestors can mint fake persons; `assurance` should stay honest (<< 10000).
- When nullifiers land, demote attestation to **corroborator** (raise assurance only), do not keep it as the uniqueness source.
