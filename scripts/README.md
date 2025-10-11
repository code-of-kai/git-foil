# Git Foil Scripts

This directory contains automation scripts for Git Foil development and release.

## Development Scripts

### mix-run.sh - Development Installation

**Purpose:** Installs your local development version so you can test code changes immediately without releasing to Homebrew.

#### Usage

```bash
./scripts/mix-run.sh
```

#### What It Does

1. **Verifies** you're in the git-foil repository
2. **Compiles** your latest code changes with `mix compile`
3. **Creates** a wrapper script at `bin/git-foil`
4. **Wrapper executes**: `cd <repo> && MIX_ENV=prod mix run -e "GitFoil.CLI.main(...)"`
5. **Verifies** the installation works correctly

The wrapper lives in your repository's `bin/` directory (which is gitignored), so it doesn't conflict with your Homebrew installation.

#### Development Workflow

```bash
# 1. Make code changes in your editor
vim lib/git_foil/commands/init.ex

# 2. Run mix-run.sh to compile and update wrapper
cd /Users/kaitaylor/Documents/Coding/git-foil
./scripts/mix-run.sh

# 3. Test your changes FROM ANY DIRECTORY using the full path
cd /tmp/test_repo  # or wherever you're testing
/Users/kaitaylor/Documents/Coding/git-foil/bin/git-foil init
/Users/kaitaylor/Documents/Coding/git-foil/bin/git-foil encrypt test.txt

# 4. Repeat steps 1-3 until satisfied

# 5. When ready, release to Homebrew
./scripts/release.sh 0.7.3
```

**Important:** You MUST use the full path to test from other directories (like test repos). The relative path `./bin/git-foil` only works from the git-foil source directory.

#### How the Wrapper Works

- **No PATH conflicts**: Wrapper is in `bin/` (not system directories)
- **Always current**: Uses `mix run` to execute your latest compiled code
- **Mix handles compilation**: Code changes are compiled automatically by Mix
- **No rebuild needed**: Unlike escript/Burrito, no need to regenerate executables

#### Testing Examples

```bash
# Create a test directory
cd /tmp && mkdir test_repo && cd test_repo
git init

# Test init (use FULL PATH)
/Users/kaitaylor/Documents/Coding/git-foil/bin/git-foil init

# Test encryption
echo "secret data" > test.txt
/Users/kaitaylor/Documents/Coding/git-foil/bin/git-foil encrypt test.txt

# Test version
/Users/kaitaylor/Documents/Coding/git-foil/bin/git-foil --version
```

## Release Scripts

### release.sh - Automated Release

Automates the entire Git Foil release process.

**Usage:**
```bash
./scripts/release.sh <version>
```

**Examples:**

```bash
# Release version 0.7.4
./scripts/release.sh 0.7.4

# Release version 0.8.0
./scripts/release.sh 0.8.0

# Release version 1.0.0
./scripts/release.sh 1.0.0
```

**What it does:**
1. Creates Git tag (e.g., v0.7.4)
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
