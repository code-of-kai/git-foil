# Git Foil Scripts

This directory contains scripts for Git Foil development and release.

## Development Scripts

### Simple Development Workflow

**Daily development (from the git-foil project root):**
```bash
mix foil init              # Mix auto-recompiles
mix foil configure "*.env"
# Edit code, run again - always fresh
```

**Pre-release QA:**
```bash
MIX_ENV=prod mix escript.build
./git_foil --version   # Test actual escript
```

**How it works:**
- `mix foil` → development runner (auto-recompiles before each call)
- `mix release --overwrite` → build a release in-place when you need the CLI
- `mix escript.build` → builds production escript for QA

No special tools needed. Works everywhere.

---

## Release Scripts

### release.sh - Automated Release

Automates the entire Git Foil release process.

**Usage:**
```bash
./scripts/release.sh <version>
```

**Examples:**
```bash
./scripts/release.sh 0.8.0
./scripts/release.sh 1.0.0
```

**What it does:**
1. Creates Git tag (e.g., v0.8.0)
2. Pushes tag to GitHub
3. Calculates SHA256 for release tarball
4. Updates Homebrew formula with new version and SHA256
5. Commits and pushes formula update

**Requirements:**
- Clean working directory (no uncommitted changes)
- SSH access to GitHub
- Write access to both repos:
  - `code-of-kai/git-foil`
  - `code-of-kai/homebrew-gitfoil`

**After release, users can upgrade with:**
```bash
brew update && brew upgrade git-foil
```

---

## Other Scripts

### run-tests-local.sh

Runs the test suite with coverage reporting.
