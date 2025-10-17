# Development Guide

## Project Structure

```
git-foil/              # Source code (this directory)
├── lib/                      # Elixir source code
├── native/                   # Rust NIFs
└── _build/dev/rel/git_foil/  # Build output (dev mode)
```

## Best Practice Workflow

### Development Cycle

```bash
# 1. Make code changes
# 2. Run directly with Mix (auto recompiles)
mix foil init

# Optional: build a local release for CLI testing
mix release --overwrite

# 3. Test the built binary (release output)
_build/dev/rel/git_foil/bin/git-foil --version
```

### Production Installation

Build a release when you need to install or package the CLI:

```bash
mix release --overwrite
```

The release will be available under `_build/dev/rel/git_foil/` (or `_build/prod/…` if you use `MIX_ENV=prod`). Install/copy it wherever you choose; no bundled installer is provided.

## Why This Approach?

✅ **Fast iteration**: `mix foil` auto-recompiles – no wrapper scripts
✅ **Simple packaging**: `mix release` builds the deployable artifact
✅ **Clean separation**: Source and build outputs stay in the repo

## Troubleshooting

- **Permission denied** when copying releases: use a destination you own or `sudo` when appropriate.
- **Need a different install prefix?** Copy `_build/.../git_foil` wherever you prefer and symlink the `bin/git-foil` executable into your PATH.
