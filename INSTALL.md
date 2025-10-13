# GitFoil Installation Guide

GitFoil uses native cryptographic libraries (Rust NIFs and post-quantum C implementations) that must be compiled for your system. Choose one of the installation methods below.

## Method 1: Homebrew (Recommended for macOS)

Homebrew will automatically handle all dependencies and compilation:

```bash
# Add the GitFoil tap
brew tap code-of-kai/gitfoil

# Install git-foil
brew install git-foil

# Verify installation
git-foil --version
```

## Method 2: Source Installation

If you don't use Homebrew, you can install from source. This requires Elixir and Rust to be installed first.

### Prerequisites

- **Elixir** 1.18+ (includes Erlang/OTP 28+)
- **Rust** (for compiling native crypto libraries)
- **Git** 2.x+

```bash
# macOS (without Homebrew)
# Install via asdf or from https://elixir-lang.org/install.html
asdf install elixir 1.18.4
asdf install rust latest

# Ubuntu/Debian
sudo apt-get install elixir erlang rust-all

# Arch Linux
sudo pacman -S elixir rust
```

### Install from Source

```bash
# Clone the repository
git clone https://github.com/code-of-kai/git-foil.git
cd git-foil

# Install dependencies and compile
mix deps.get
MIX_ENV=prod mix compile

# Build escript
MIX_ENV=prod mix escript.build

# Install to system
sudo cp git-foil /usr/local/bin/git-foil
sudo chmod +x /usr/local/bin/git-foil

# Verify installation
git-foil --version
```

## Quick Start

```bash
# In your Git repository
cd my-project

# Initialize GitFoil
git-foil init

# Add encryption patterns
git-foil add-pattern "*.env"
git-foil add-pattern "config/secrets.yml"

# Files matching these patterns will now be automatically encrypted when committed
```

## Troubleshooting

### "pqclean_nif is not available" Error

This means the NIFs didn't compile. Run:

```bash
mix deps.compile pqclean --force
mix deps.compile rustler --force
```

### "Function not available" Errors

Make sure you compiled with `MIX_ENV=prod`:

```bash
MIX_ENV=prod mix compile
MIX_ENV=prod mix escript.build
```

## Uninstallation

```bash
sudo rm /usr/local/bin/git-foil
```

To remove GitFoil from a repository:

```bash
git-foil unencrypt  # Decrypt all files
rm -rf .git/git_foil
rm .gitattributes
```
