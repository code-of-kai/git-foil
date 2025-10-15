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
