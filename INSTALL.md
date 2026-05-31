# GitFoil Installation Guide

GitFoil uses native cryptographic libraries (Rust NIFs and post-quantum C implementations) that must be compiled for your system.

## Installation

**macOS (Homebrew):**

```bash
brew install code-of-kai/gitfoil/git-foil
```

Homebrew automatically handles all dependencies and compilation.

**Other platforms:**

GitFoil is currently distributed via Homebrew for macOS. For other platforms, you'll need to build from source (requires Elixir 1.18+ and Rust). See the project repository for build instructions.

## Verify Installation

```bash
git-foil --version
```

## Quick Start

```bash
# In your Git repository
cd my-project

# Initialize GitFoil
git-foil init

# Follow the interactive prompts to select which files to encrypt
```

## Upgrading an existing repository to the long-running filter

GitFoil >= 1.1.0 uses Git's long-running filter process
(`filter.gitfoil.process`) so multi-file operations run a single persistent
process instead of one per file — faster, and immune to the macOS concurrent
NIF-load race. Fresh `git-foil init` configures it automatically. To add it to
a repository that was initialized by an older GitFoil:

```bash
cd my-existing-repo
git-foil upgrade-filters
```

This is transport-only: ciphertext is unchanged, so `git status` reports
nothing modified and no re-encryption occurs.

## Downgrading / rollback

If you ever need to roll back to a GitFoil version that predates the process
protocol, you **must** unset `filter.gitfoil.process` first — otherwise git
will keep invoking a filter the old binary cannot speak. See
[ROLLBACK.md](ROLLBACK.md) for the full procedure and `scripts/gitfoil-rollback.sh`
to do it across many repositories.

## Uninstallation

**Remove from system:**

```bash
brew uninstall git-foil
```

**Remove from a repository:**

```bash
git-foil unencrypt  # Decrypt all files
rm -rf .git/git_foil
rm .gitattributes
```
