# GitFoil rollback & version compatibility

This document explains how the long-running filter process
(`filter.gitfoil.process`, added in the version that introduced the
`filter-process` subcommand) interacts with git and binary versions, and how to
roll back **safely**.

## The transport is purely about *how* git invokes the filter

GitFoil configures a repository with two transports that produce **byte-for-byte
identical ciphertext**:

| Config key                  | Used by            | Mechanism                                   |
| --------------------------- | ------------------ | ------------------------------------------- |
| `filter.gitfoil.process`    | git >= 2.11        | one persistent process, pkt-line protocol   |
| `filter.gitfoil.clean/.smudge` | older git / fallback | a fresh `git-foil` process per file       |

Switching between them never rewrites history and never churns the working
tree, because the ciphertext is the same. The clean/smudge logic, AEAD
construction, nonce derivation, key handling, and serialization are unchanged.

## Two compatibility axes — they are NOT symmetric

These are different situations and the "both keys configured" arrangement
covers only one of them. Do not conflate them.

### Axis 1 — old git, new binary  ✅ covered automatically

git < 2.11 does not understand the `filter.gitfoil.process` key, silently
ignores it, and uses `filter.gitfoil.clean`/`.smudge`. A repository that was
never reconfigured also keeps working on clean/smudge. Nothing to do.

### Axis 2 — new git, rolled-back binary  ⚠️ requires an explicit step

git >= 2.11 **prefers** `filter.gitfoil.process` and invokes it for every
encrypted file. If that process fails its handshake, git **aborts the
operation** — it does **not** fall back to clean/smudge.

So if you downgrade git-foil to a build that predates the protocol (e.g.
1.0.10) while `filter.gitfoil.process` is still set, git will keep invoking a
`filter-process` subcommand the old binary does not understand, and **every git
operation in that repo will fail**. The "both keys configured" net does NOT
save you here.

## Safe rollback procedure

**Unset `.process` first, then downgrade the binary.** In that order.

1. Unset the process key in every affected repo (uses plain git, so it works
   even after git-foil is downgraded/uninstalled):

   ```bash
   # one repo:
   git config --unset filter.gitfoil.process

   # many repos under a directory:
   /path/to/git-foil/scripts/gitfoil-rollback.sh ~/Documents/Coding
   ```

2. Relink/downgrade the git-foil binary (Homebrew keeps the old version in the
   Cellar until `brew cleanup`):

   ```bash
   brew unlink git-foil && brew link --overwrite git-foil   # if multiple versions present
   # or reinstall the pinned old formula from the tap
   ```

After step 1 the repo is back on clean/smudge, which any git-foil version
handles. After step 2 you are fully on the old binary.

> Tip: keep the new version installed until you've confirmed the new binary
> handles your real repositories for a few days. Do not run `brew cleanup`
> until then — that is what keeps 1.0.10 recoverable.
