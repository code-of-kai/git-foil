#!/bin/bash
#
# git-foil rollback helper
# ========================
#
# Removes `filter.gitfoil.process` from git repositories so they work again
# with a git-foil binary that predates the long-running filter protocol
# (<= 1.0.10). RUN THIS *BEFORE* DOWNGRADING the git-foil binary.
#
# Why this is necessary
# ---------------------
# git >= 2.11 prefers `filter.gitfoil.process` and invokes it for every
# encrypted file. It does NOT fall back to `filter.gitfoil.clean`/`.smudge`
# when that process fails its handshake. So if you downgrade git-foil to a
# build that cannot speak the protocol while `.process` is still configured,
# git will keep invoking a `filter-process` the old binary does not understand
# and EVERY git operation in that repo will abort. Unsetting `.process` first
# restores the clean/smudge path (which the old binary handles), making the
# downgrade safe.
#
# This script uses only plain `git` -- no git-foil -- so it works even after
# git-foil has been downgraded or uninstalled. It leaves clean/smudge/required
# untouched and never touches keys, content, or history. It is idempotent.
#
# Usage:
#   gitfoil-rollback.sh DIR [DIR ...]
#       Walk each DIR for git repositories and unset filter.gitfoil.process
#       wherever it is set.
#
# Example:
#   gitfoil-rollback.sh ~/Documents/Coding
#
set -uo pipefail

if [ "$#" -eq 0 ]; then
  echo "usage: $0 DIR [DIR ...]" >&2
  echo "  Unsets filter.gitfoil.process in every git repo under each DIR," >&2
  echo "  making it safe to downgrade git-foil below the process-protocol version." >&2
  exit 2
fi

count=0

unset_one() {
  repo="$1"
  if git -C "$repo" config --local --get filter.gitfoil.process >/dev/null 2>&1; then
    git -C "$repo" config --local --unset-all filter.gitfoil.process
    echo "unset filter.gitfoil.process: $repo"
    count=$((count + 1))
  fi
}

for root in "$@"; do
  if [ ! -d "$root" ]; then
    echo "skip (not a directory): $root" >&2
    continue
  fi

  # `.git` is a directory in normal repos and a file in worktrees/submodules;
  # match both. The repo root is its parent directory.
  while IFS= read -r gitpath; do
    unset_one "$(dirname "$gitpath")"
  done < <(find "$root" -name .git 2>/dev/null)
done

echo "Done. Unset filter.gitfoil.process in $count repo(s)."
echo "You can now safely relink/downgrade git-foil to a pre-process-protocol version."
