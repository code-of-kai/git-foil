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

2. Activate the old git-foil binary. If both kegs are present in the Cellar
   (the prebuilt 1.0.10 keg is kept as the rollback target), switch instantly
   with a symlink swap — no rebuild, no download:

   ```bash
   ls /opt/homebrew/Cellar/git-foil/            # confirm 1.0.10 is present
   brew unlink git-foil
   ln -sf /opt/homebrew/Cellar/git-foil/1.0.10/bin/git-foil /opt/homebrew/bin/git-foil
   git-foil --version                           # -> GitFoil version 1.0.10
   ```

   To go back to the new version:

   ```bash
   brew unlink git-foil && brew link --overwrite git-foil   # links the formula version (newest keg)
   ```

   (Modern Homebrew removed `brew switch`; `brew link` always links the
   formula's current version, so the symlink swap above is how you pin an older
   *installed* keg.) If the old keg is **not** in the Cellar, rebuild it from
   the tag instead: point the tap formula at the `v1.0.10` tarball and
   `HOMEBREW_NO_INSTALL_CLEANUP=1 brew reinstall code-of-kai/gitfoil/git-foil`.

After step 1 the repo is back on clean/smudge, which any git-foil version
handles. After step 2 you are fully on the old binary.

> ⚠️ **`brew reinstall`/`brew upgrade` auto-run `brew cleanup git-foil`**, which
> deletes old Cellar kegs (this is on by default and is how the 1.0.10 keg was
> lost once during the 1.1.0 rollout). To keep 1.0.10 recoverable as a prebuilt
> keg, **prefix brew commands with `HOMEBREW_NO_INSTALL_CLEANUP=1`** (or export
> it in your shell profile). Never run a bare `brew cleanup` until you've
> confirmed the new binary handles your real repositories.
