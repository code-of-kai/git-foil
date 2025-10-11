#!/bin/bash
# Git Foil Release Automation Script
#
# This script automates the entire release process:
# 1. Creates a Git tag for the new version
# 2. Pushes the tag to GitHub
# 3. Updates the Homebrew formula with the new version and SHA256
# 4. Commits and pushes the formula update
#
# Usage: ./scripts/release.sh <version>
# Example: ./scripts/release.sh 0.7.4

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
error() {
    echo -e "${RED}❌ Error: $1${NC}" >&2
    exit 1
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

warn() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Check if version argument is provided
if [ -z "$1" ]; then
    error "Version number required. Usage: $0 <version> (e.g., 0.7.4)"
fi

VERSION="$1"
TAG="v${VERSION}"
REPO_ROOT="$(git rev-parse --show-toplevel)"
HOMEBREW_REPO_PATH="${REPO_ROOT}/../homebrew-gitfoil"
FORMULA_PATH="${HOMEBREW_REPO_PATH}/Formula/git-foil.rb"

info "Starting release process for version ${VERSION}"
echo ""

# Step 1: Verify we're in the git-foil repository
info "Step 1: Verifying repository..."
if [ ! -f "${REPO_ROOT}/mix.exs" ]; then
    error "Not in git-foil repository root"
fi
success "Repository verified"
echo ""

# Step 2: Check for uncommitted changes
info "Step 2: Checking for uncommitted changes..."
if ! git diff-index --quiet HEAD --; then
    warn "You have uncommitted changes. Please commit or stash them first."
    git status --short
    exit 1
fi
success "Working directory clean"
echo ""

# Step 3: Verify we're on master branch and up to date
info "Step 3: Verifying branch status..."
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT_BRANCH" != "master" ]; then
    warn "Not on master branch (currently on ${CURRENT_BRANCH})"
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi
success "Branch verified"
echo ""

# Step 4: Create and push Git tag
info "Step 4: Creating Git tag ${TAG}..."
if git rev-parse "$TAG" >/dev/null 2>&1; then
    error "Tag ${TAG} already exists"
fi

git tag -a "$TAG" -m "Release ${TAG} - Automated release"
success "Tag created: ${TAG}"

info "Pushing tag to GitHub..."
git push origin "$TAG"
success "Tag pushed to GitHub"
echo ""

# Step 5: Get commit SHA and calculate tarball SHA256
info "Step 5: Calculating release checksums..."
COMMIT_SHA=$(git rev-parse "$TAG")
info "Commit SHA: ${COMMIT_SHA}"

TARBALL_URL="https://github.com/code-of-kai/git-foil/archive/refs/tags/${TAG}.tar.gz"
info "Downloading tarball from: ${TARBALL_URL}"

# Wait a moment for GitHub to process the tag
sleep 3

TARBALL_SHA256=$(curl -sL "$TARBALL_URL" | shasum -a 256 | cut -d' ' -f1)
if [ -z "$TARBALL_SHA256" ]; then
    error "Failed to download or calculate SHA256 for tarball"
fi
success "Tarball SHA256: ${TARBALL_SHA256}"
echo ""

# Step 6: Clone or update Homebrew formula repository
info "Step 6: Preparing Homebrew formula repository..."
if [ ! -d "$HOMEBREW_REPO_PATH" ]; then
    info "Cloning homebrew-gitfoil repository..."
    cd "${REPO_ROOT}/.."
    git clone git@github.com:code-of-kai/homebrew-gitfoil.git
    success "Repository cloned"
else
    info "Updating existing homebrew-gitfoil repository..."
    cd "$HOMEBREW_REPO_PATH"
    git fetch origin
    git checkout main
    git pull origin main
    success "Repository updated"
fi
echo ""

# Step 7: Update Homebrew formula
info "Step 7: Updating Homebrew formula..."
cd "$HOMEBREW_REPO_PATH"

if [ ! -f "$FORMULA_PATH" ]; then
    error "Formula not found at ${FORMULA_PATH}"
fi

# Get current version from formula (macOS-compatible)
CURRENT_VERSION=$(grep -o 'v[0-9]*\.[0-9]*\.[0-9]*' "$FORMULA_PATH" | head -1 | sed 's/^v//')
info "Current formula version: ${CURRENT_VERSION}"
info "New version: ${VERSION}"

# Update the formula file
sed -i.bak "s|archive/refs/tags/v${CURRENT_VERSION}\.tar\.gz|archive/refs/tags/${TAG}.tar.gz|g" "$FORMULA_PATH"
sed -i.bak "s|sha256 \".*\"|sha256 \"${TARBALL_SHA256}\"|g" "$FORMULA_PATH"

# Remove backup file
rm -f "${FORMULA_PATH}.bak"

# Show the diff
info "Formula changes:"
git diff "$FORMULA_PATH"
echo ""

# Step 8: Commit and push formula update
info "Step 8: Committing and pushing formula update..."
git add "$FORMULA_PATH"
git commit -m "Update git-foil to ${TAG}"
git push origin main
success "Formula updated and pushed"
echo ""

# Step 9: Summary
echo ""
echo "═══════════════════════════════════════════════════════════════"
success "Release ${TAG} completed successfully!"
echo "═══════════════════════════════════════════════════════════════"
echo ""
info "Release details:"
echo "  • Version: ${VERSION}"
echo "  • Tag: ${TAG}"
echo "  • Commit: ${COMMIT_SHA}"
echo "  • Tarball SHA256: ${TARBALL_SHA256}"
echo ""
info "Users can now upgrade with:"
echo "  brew update && brew upgrade git-foil"
echo ""
info "GitHub Release URL:"
echo "  https://github.com/code-of-kai/git-foil/releases/tag/${TAG}"
echo ""
warn "Optional: Create a GitHub Release with release notes at the URL above"
echo ""
