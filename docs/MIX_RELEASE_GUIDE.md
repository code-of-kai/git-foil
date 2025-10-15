# GitFoil Mix Release Quickstart

This project now ships a standard Mix release so the CLI can load the Rust NIFs that power the six-layer encryption pipeline. Use this guide when you need an executable that works outside of `mix run`.

## Build the release

```bash
MIX_ENV=prod mix deps.get
MIX_ENV=prod mix compile
MIX_ENV=prod mix release
```

You will find the packaged binary at `_build/prod/rel/git_foil/bin/git-foil`.

## Using the release binary with Git filters

1. Build the release (see above).
2. Point Git’s clean/smudge filters at the release executable:
   ```bash
   git config filter.gitfoil.clean \
     "$(pwd)/_build/prod/rel/git_foil/bin/git-foil clean %f"
   git config filter.gitfoil.smudge \
     "$(pwd)/_build/prod/rel/git_foil/bin/git-foil smudge %f"
   ```
3. Verify the filters by staging a file that should be encrypted. The command will succeed without the previous `UndefinedFunctionError`.

## Notes

- The release currently targets Unix-like systems (macOS & Linux). Windows support would require additional configuration.
- The legacy escript remains available for development, but Git filters should point at the release binary to ensure NIFs load correctly.
- When rebuilding the release after code changes, re-run the `git config` commands so Git points at the latest path.

