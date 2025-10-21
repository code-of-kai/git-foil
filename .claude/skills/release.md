# Git Foil Release Skill

Execute the complete Git Foil release process following the official checklist at `/Users/kaitaylor/Documents/Coding/docs/git-foil-release-steps.txt`.

## Instructions

When this skill is invoked, follow these steps **exactly** in order:

### Step 1: Tests & Build
- Run `mix test` to ensure all tests pass
- Run `MIX_ENV=prod mix escript.build` to verify production build works
- If either fails, STOP and report the errors

### Step 2: Ensure Git Repo Clean
- Run `git status -sb` to check repository status
- If there are uncommitted changes, STOP and ask the user what to do

### Step 3: Version Bump
- Ask the user what version number to release (e.g., "1.0.2")
- Update the version in `mix.exs` (line 7)
- Commit the change with message: `Bump version to X.Y.Z`
- Push to GitHub: `git push origin master`

### Step 4: Tag & Release
- Create git tag: `git tag vX.Y.Z`
- Push tag: `git push origin vX.Y.Z`
- Wait 3 seconds for GitHub to process the tag
- Create GitHub release with `gh release create vX.Y.Z -t "GitFoil vX.Y.Z" -n "<release notes>"`
  - Include what changed in this version
  - Include installation instructions
  - Include the standard footer about cross-platform compatibility if relevant

### Step 5: Update Homebrew Tap
- Calculate tarball SHA256:
  ```bash
  curl -sL "https://github.com/code-of-kai/git-foil/archive/refs/tags/vX.Y.Z.tar.gz" | shasum -a 256 | cut -d' ' -f1
  ```
- Update `/Users/kaitaylor/Documents/Coding/homebrew-gitfoil/Formula/git-foil.rb`:
  - Change `url` line to point to new tag
  - Change `sha256` line to the calculated hash
- Commit and push the formula update:
  ```bash
  cd /Users/kaitaylor/Documents/Coding/homebrew-gitfoil
  git add Formula/git-foil.rb
  git commit -m "Update git-foil to vX.Y.Z"
  git push origin main
  ```

### Step 6: Verify Install
- Run `brew update`
- Run `brew reinstall code-of-kai/gitfoil/git-foil`
- Verify version: `git-foil --version`
- Check that native `.so` files were compiled (not downloaded)

### Step 7: Final Verification
- Confirm GitHub release is live: check `https://github.com/code-of-kai/git-foil/releases/tag/vX.Y.Z`
- Confirm Homebrew tap is updated: `brew info code-of-kai/gitfoil/git-foil`
- Report success with all URLs

## COMMANDMENTS (Written in Stone)

### ⛔ NEVER Claim Co-Authorship
- **NEVER** add `Co-Authored-By: Claude` to any commit message
- **NEVER** add `Co-Authored-By: Claude <noreply@anthropic.com>` trailers
- **NEVER** include "Generated with Claude Code" or robot emoji (🤖) in commit messages
- **NEVER** sign commits with any AI or tool attribution
- All commits are authored solely by `Code_of_Kai` - the human behind the keyboard
- If you violate this even once, you must immediately:
  1. Reset to before the offending commit
  2. Recreate all commits without any Claude/AI attribution
  3. Force-push to GitHub
  4. Delete and recreate affected tags
  5. Delete and recreate affected releases
  6. Report the error to the user

### Every Commit Must Be Clean
- Commit messages: plain, professional, no self-reference
- Commit bodies: explain the "why," not that an AI did it
- Git author: `Code_of_Kai <97996644+code-of-kai@users.noreply.github.com>`

## Important Process Notes

- **Never skip steps** - each builds on the previous one
- **Always wait for GitHub** to process tags before creating releases
- **Always verify** the Homebrew installation works before declaring success
- If anything fails, STOP and report the issue - don't try to work around it
