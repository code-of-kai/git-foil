---
description: Fully automated git-foil release process
---

You are releasing a new version of git-foil. This process is FULLY AUTOMATED with NO user prompts.

## Automation Rules

1. **Version bumping**: ALWAYS increment the patch version automatically (e.g., 1.0.2 → 1.0.3)
2. **Uncommitted changes**: ALWAYS commit all changes before releasing
3. **Co-authorship**: NEVER add co-author attribution to ANY commits or releases
4. **Homebrew tap location**: ALWAYS assume `~/Documents/Coding/homebrew-gitfoil`
5. **Release notes**: ALWAYS generate from recent git commits automatically

## Release Process

Execute steps in order. Use TodoWrite to track progress.

### 1. Pre-Release Validation
- Run `mix test` (must pass)
- Run `MIX_ENV=prod mix escript.build` (must succeed)
- Run `git status -sb`

### 2. Commit Uncommitted Changes
- If there are uncommitted changes, stage and commit them:
  - `git add -A`
  - `git commit -m "Pre-release changes"`
  - **CRITICAL**: Do NOT add any co-author attribution
- Push: `git push origin master`

### 3. Version Bump
- Read current version from `mix.exs`
- Auto-increment patch version (X.Y.Z → X.Y.Z+1)
- Update version in `mix.exs`
- Stage: `git add mix.exs`
- Commit: `git commit -m "Bump version to vX.Y.Z"`
  - **CRITICAL**: Do NOT add any co-author attribution
- Push: `git push origin master`

### 4. Create Git Tag and GitHub Release
- Create annotated tag: `git tag -a vX.Y.Z -m "Release vX.Y.Z"`
- Push tag: `git push origin vX.Y.Z`
- Generate release notes from last 5 commits: `git log -5 --oneline`
- Create GitHub release: `gh release create vX.Y.Z -t "GitFoil vX.Y.Z" -n "<generated notes>"`
  - **CRITICAL**: Do NOT add any co-author attribution

### 5. Update Homebrew Tap
a. Download and hash tarball:
   - URL: `https://github.com/code-of-kai/git-foil/archive/refs/tags/vX.Y.Z.tar.gz`
   - Download: `curl -sL <url> -o /tmp/git-foil-vX.Y.Z.tar.gz`
   - Hash: `shasum -a 256 /tmp/git-foil-vX.Y.Z.tar.gz`

b. Update formula at `~/Documents/Coding/homebrew-gitfoil/Formula/git-foil.rb`:
   - Update `url` line
   - Update `sha256` line
   - Save changes

c. Commit and push tap:
   - `cd ~/Documents/Coding/homebrew-gitfoil`
   - `git add Formula/git-foil.rb`
   - `git commit -m "Update git-foil to vX.Y.Z"`
     - **CRITICAL**: Do NOT add any co-author attribution
   - `git push origin master`
   - `cd` back to git-foil directory

### 6. Provide Verification Instructions
Show user:
```
brew update
brew reinstall code-of-kai/gitfoil/git-foil
git-foil --version
```

### 7. Summary
- Version bumped from X.Y.Z to A.B.C
- Git tag created and pushed
- GitHub release created
- Homebrew formula updated
- Verification steps provided

## CRITICAL REQUIREMENTS

- **NEVER** add co-author attribution to ANY commit or release
- **NEVER** include "Co-Authored-By: Claude" or similar
- **NEVER** add "Generated with Claude Code" or similar
- **NO** user prompts - fully automated
- **AUTO-INCREMENT** patch version always
- **AUTO-COMMIT** all changes before release
