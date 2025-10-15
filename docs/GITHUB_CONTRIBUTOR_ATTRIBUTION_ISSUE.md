# GitHub Contributor Attribution Issue

**Repository:** `code-of-kai/git-foil`
**Issue:** Claude (AI tool) incorrectly listed as a contributor
**Expected:** Only code-of-kai should appear as contributor
**Status:** Awaiting GitHub cache refresh after implementing fixes

---

## Problem Statement

GitHub's contributor graph incorrectly displays "Claude" (email: `noreply@anthropic.com`) as a contributor to the git-foil repository. Claude is an AI coding assistant tool, not a human author, and should not appear in the contributors list.

The sole author and maintainer of this repository is **code-of-kai**.

---

## Root Cause

Historical commits contained `Co-authored-by: Claude <noreply@anthropic.com>` trailers in commit messages. These were added automatically by an AI coding tool during development. While these trailers have since been removed from all commit messages, GitHub's contributor cache continues to display Claude as a contributor.

---

## Actions Taken

### 1. Removed Co-authored-by Trailers (Completed)

All `Co-authored-by: Claude` attributions have been removed from commit messages throughout the repository's history. Verification:

```bash
git log --all --grep="Co-authored-by: Claude" --oneline
# Returns: 0 commits
```

**Result:** No commits in the repository contain Claude co-authorship attributions.

### 2. Added .mailmap File (Completed - October 15, 2025)

Created `.mailmap` file to explicitly map all commits from Claude's email to the actual author:

**File:** `.mailmap`
**Commit:** `57f946b` - "[META] Add .mailmap to ensure proper contributor attribution"
**Date:** October 15, 2025

**Contents:**
```
# GitFoil Contributors Mapping
# This file ensures proper attribution on GitHub

# Main author
code-of-kai <97996644+code-of-kai@users.noreply.github.com>

# Claude is a tool, not a contributor
# Map any Claude attributions to the actual author
code-of-kai <97996644+code-of-kai@users.noreply.github.com> <noreply@anthropic.com>
```

This is the standard Git/GitHub mechanism for correcting contributor attribution.

### 3. Forced Cache Refresh (Completed - October 15, 2025)

Created empty commit to trigger GitHub's contributor cache recalculation:

**Commit:** `0ce8622` - "[META] Force GitHub contributors cache refresh"
**Date:** October 15, 2025

---

## Expected Outcome

According to GitHub's documentation, the `.mailmap` file should:
1. Retroactively remap all commits from `noreply@anthropic.com` to code-of-kai
2. Trigger a recalculation of the repository's contributor graph
3. Remove Claude from the contributors list within 24-48 hours

---

## Current Status (48+ Hours Later)

Despite implementing the standard `.mailmap` solution and waiting 48+ hours for GitHub's cache to refresh:

- ✅ `.mailmap` file is present and correctly formatted
- ✅ No commits contain `Co-authored-by: Claude` attributions
- ✅ Empty commit pushed to force cache refresh
- ❌ Claude still appears in the contributors list on GitHub

**GitHub Repository URL:** https://github.com/code-of-kai/git-foil/graphs/contributors

---

## Request for GitHub Support

The standard `.mailmap` solution has been implemented correctly but has not resolved the issue after 48+ hours. We respectfully request that GitHub Support manually clear the contributor cache for this repository.

### Verification Steps for GitHub Support

1. **Verify .mailmap exists:**
   ```bash
   curl https://raw.githubusercontent.com/code-of-kai/git-foil/master/.mailmap
   ```

2. **Verify no Co-authored-by trailers remain:**
   ```bash
   git clone https://github.com/code-of-kai/git-foil.git
   cd git-foil
   git log --all --grep="Co-authored-by: Claude"
   # Should return no results
   ```

3. **Verify mapping is correct:**
   The `.mailmap` file correctly maps `noreply@anthropic.com` → `code-of-kai <97996644+code-of-kai@users.noreply.github.com>`

### What We Need

Please manually refresh/clear the contributor cache for repository `code-of-kai/git-foil` so that:
- Claude (`noreply@anthropic.com`) is removed from the contributors list
- All commits are correctly attributed to code-of-kai (the sole author)

---

## Additional Context

### Why This Matters

1. **Accurate Attribution:** AI tools are assistants, not authors. Proper attribution reflects the actual human who created this work.

2. **Professional Credibility:** This is a security-focused cryptography project. Having an AI tool listed as a contributor undermines the professional credibility of the repository.

3. **Ethical AI Use:** We believe in transparent AI tool usage without misrepresenting tools as human contributors. The README and documentation clearly describe the project's development process.

### Repository Details

- **Repository:** code-of-kai/git-foil
- **Primary Branch:** master
- **Total Commits:** ~150+
- **Sole Author:** code-of-kai <97996644+code-of-kai@users.noreply.github.com>
- **Language:** Elixir (cryptographic Git filter tool)

---

## Technical Details for Support

### .mailmap Specification

According to Git documentation (git-shortlog(1)), the `.mailmap` format we're using is:

```
<proper-name> <proper-email> <commit-email>
```

Our mapping:
```
code-of-kai <97996644+code-of-kai@users.noreply.github.com> <noreply@anthropic.com>
```

This should map all commits from `noreply@anthropic.com` to the proper author.

### GitHub's Contributor Graph Calculation

GitHub's contributor graph is derived from:
1. Git commit author/committer information
2. Email address mapping via `.mailmap`
3. Co-authored-by trailers in commit messages

We have addressed all three:
- ✅ All commits authored by code-of-kai
- ✅ `.mailmap` added to remap Claude's email
- ✅ All Co-authored-by trailers removed

---

## References

- [Git Shortlog Documentation (mailmap)](https://git-scm.com/docs/git-shortlog#_mapping_authors)
- [GitHub Documentation: Commit Attribution](https://docs.github.com/en/repositories/working-with-files/using-files/viewing-a-file#viewing-the-line-by-line-revision-history-for-a-file)

---

## Contact Information

**Repository Owner:** code-of-kai
**Repository:** https://github.com/code-of-kai/git-foil
**Issue Date:** October 15, 2025
**Support Request Date:** October 17, 2025 (48 hours after fix implementation)

---

*This document was created to provide comprehensive context for GitHub Support regarding incorrect contributor attribution in the git-foil repository.*
