#!/usr/bin/env bash
# Changelog Suggestion Helper
# Analyzes git commits since last release and suggests changelog entries

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "Morphir Changelog Suggestion Tool"
echo "=================================="
echo ""

# Get last release tag
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")

if [ -z "$LAST_TAG" ]; then
    echo "No previous tags found. Showing all commits."
    COMMIT_RANGE="HEAD"
else
    echo "Last release: $LAST_TAG"
    COMMIT_RANGE="$LAST_TAG..HEAD"
fi

echo ""
echo "Analyzing commits since last release..."
echo ""

# Get all commits
COMMITS=$(git log $COMMIT_RANGE --oneline --no-merges)

if [ -z "$COMMITS" ]; then
    echo "No new commits since last release."
    exit 0
fi

echo "Total commits: $(echo "$COMMITS" | wc -l)"
echo ""

# Categorize commits using conventional commit format
echo -e "${BLUE}=== Suggested Changelog Entries ===${NC}"
echo ""

# Features (Added)
FEATURES=$(git log $COMMIT_RANGE --oneline --no-merges --grep="^feat" || true)
if [ -n "$FEATURES" ]; then
    echo -e "${GREEN}### Added${NC}"
    echo "$FEATURES" | sed 's/^[a-f0-9]* feat[:(]/- /' | sed 's/):/:/g'
    echo ""
fi

# Fixes (Fixed)
FIXES=$(git log $COMMIT_RANGE --oneline --no-merges --grep="^fix" || true)
if [ -n "$FIXES" ]; then
    echo -e "${GREEN}### Fixed${NC}"
    echo "$FIXES" | sed 's/^[a-f0-9]* fix[:(]/- /' | sed 's/):/:/g'
    echo ""
fi

# Changes (Changed)
CHANGES=$(git log $COMMIT_RANGE --oneline --no-merges --grep="^refactor\|^perf\|^chore.*update" || true)
if [ -n "$CHANGES" ]; then
    echo -e "${GREEN}### Changed${NC}"
    echo "$CHANGES" | sed 's/^[a-f0-9]* [^:]*[:(]/- /' | sed 's/):/:/g'
    echo ""
fi

# Documentation (if significant)
DOCS=$(git log $COMMIT_RANGE --oneline --no-merges --grep="^docs" || true)
if [ -n "$DOCS" ]; then
    echo -e "${GREEN}### Documentation${NC}"
    echo "$DOCS" | sed 's/^[a-f0-9]* docs[:(]/- /' | sed 's/):/:/g'
    echo ""
fi

# Breaking changes
BREAKING=$(git log $COMMIT_RANGE --oneline --no-merges --grep="BREAKING CHANGE\|!" || true)
if [ -n "$BREAKING" ]; then
    echo -e "${YELLOW}⚠️  BREAKING CHANGES DETECTED${NC}"
    echo "$BREAKING" | sed 's/^[a-f0-9]* /- /'
    echo ""
    echo -e "${YELLOW}This suggests a MAJOR version bump!${NC}"
    echo ""
fi

# Non-conventional commits
echo -e "${BLUE}=== Other Commits (review manually) ===${NC}"
echo ""
git log $COMMIT_RANGE --oneline --no-merges --invert-grep --grep="^feat\|^fix\|^docs\|^style\|^refactor\|^perf\|^test\|^chore" || echo "None"
echo ""

# Suggest version bump
echo -e "${BLUE}=== Version Bump Suggestion ===${NC}"
echo ""

if [ -n "$BREAKING" ]; then
    echo -e "${YELLOW}Suggested: MAJOR version bump (breaking changes)${NC}"
elif [ -n "$FEATURES" ]; then
    echo -e "${GREEN}Suggested: MINOR version bump (new features)${NC}"
elif [ -n "$FIXES" ]; then
    echo -e "${GREEN}Suggested: PATCH version bump (bug fixes only)${NC}"
else
    echo "Suggested: PATCH version bump (changes detected)"
fi

echo ""
echo "To update CHANGELOG.md:"
echo "  1. Edit CHANGELOG.md"
echo "  2. Move items from [Unreleased] to [X.Y.Z] - $(date +%Y-%m-%d)"
echo "  3. Add entries suggested above"
echo "  4. Commit: git commit -m 'chore: prepare release vX.Y.Z'"
echo ""
