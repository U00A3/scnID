# Sealed voting (Hidden) and commit-reveal

## What SCNID ships now (UI Hidden)

Officer can open a vote as **Live** or **Hidden until end**.

| Mode | During the vote | After `voteEnd` |
|------|-----------------|-----------------|
| **Live** | Tallies visible in the ballot UI | Tallies visible |
| **Hidden** | Ballot UI hides the share axis and counts | Tallies visible |

**Honest limit:** votes are still written on-chain immediately. Anyone who reads the governor contract (RPC, explorer) can still see running tallies. Hidden is a **product / anti-suggestion** control for normal UI users, not cryptographic secrecy.

That is why we treat Hidden as a bridge and **commit-reveal as the desirable next step** for person-chamber signalling.

---

## What commit-reveal is

A two-phase voting scheme:

1. **Commit** - while the vote is open, each person submits only a hash, e.g.  
   `commit = keccak256(choice, salt, person, proposalId)`  
   Nobody (including the UI and casual chain readers) can see whether that was For / Against / Abstain.
2. **Reveal** - after the commit window closes, each person publishes `(choice, salt)`. The contract checks the hash matches the commit, then adds the ballot to the tally.

Until reveal, there is **no public running score** to follow or pressure.

---

## How it would work in SCNID (sketch)

```text
propose(..., disclosure = CommitReveal)
  -> Commit window (voteStart .. voteEnd)
       castCommit(id, bytes32 commit)
  -> Reveal window (voteEnd .. revealEnd)
       reveal(id, support, salt)
  -> state / result uses revealed tallies only
```

UI sketch:

- During commit: "Ballot sealed - cast a commit. Tallies unlock after reveal."
- During reveal: "Reveal your choice. Unrevealed commits do not count."
- After reveal end: normal Lab-style axis and totals.

Salt stays in the browser (local storage) or is shown once for the voter to save - same class of UX as other commit-reveal DAOs.

---

## Benefits (why we want it)

1. **No bandwagon / underdog theatre** - voters cannot see who is "winning" mid-vote.
2. **Less social pressure** - especially on small DAOs where everyone watches the same ballot.
3. **Still on-chain and auditable** - after reveal, the full set of ballots is public and checkable.
4. **Fits person chamber** - one commit per `person` key; link wallets do not get extra commits.
5. **Honest about Redbelly** - we already say CAT is not a uniqueness map; sealed commit avoids pretending live on-chain tallies are "private" when they are not.

---

## Trade-offs (short, so they are not invisible)

| Cost | Why it exists |
|------|----------------|
| Two transactions (commit + reveal) | Secrecy needs a later unveil step |
| Salt UX | User must keep the salt until reveal (or the dapp stores it for that browser) |
| Unrevealed ballots | A commit with no reveal usually counts as no vote (must be explicit in rules) |
| Slightly longer lifecycle | Need a reveal window after the commit window |

None of these are reasons to skip commit-reveal for high-stakes signalling; they are reasons to ship **UI Hidden first**, then upgrade the governor when the POV is ready.

---

## Roadmap stance

1. **Now:** UI Hidden (soft) + this note.  
2. **Next:** on-chain `disclosure` enum on `PersonGovernor` (no description tag).  
3. **Desired:** commit-reveal for `Hidden` / a dedicated `CommitReveal` mode; Live stays as today.

SCN paper weights / stake chamber stay on the bicameral roadmap; sealed person ballots are independent and can land earlier.
