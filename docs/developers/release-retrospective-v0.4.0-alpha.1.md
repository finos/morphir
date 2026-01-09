# Release Retrospective: v0.4.0-alpha.1

## Summary

Release v0.4.0-alpha.1 was successfully published on 2026-01-08, but required multiple iterations (8+ workflow runs) due to various configuration issues. This document captures the issues encountered and recommendations for improvement.

## Issues Encountered

### 1. sum.golang.org Timing Issues

**Problem**: The Go checksum database (sum.golang.org) hadn't indexed newly created module tags, causing `go mod tidy` to fail during the release workflow.

**Error**:
```
github.com/finos/morphir/pkg/bindings/wit@v0.4.0-alpha.1: reading https://sum.golang.org/lookup/...: 404 Not Found
```

**Root Cause**: Tags were created and pushed, but sum.golang.org takes time to index new versions. The goreleaser hooks ran `go mod tidy` which tried to verify checksums.

**Fix Applied**: Added `GONOSUMDB=github.com/finos/morphir/*` to `.goreleaser.yaml` env section.

**Recommendation**:
- This fix should be permanent for self-referential module dependencies
- Document this in release manager skill

### 2. Stale Pseudo-versions in tests/bdd

**Problem**: `tests/bdd/go.mod` contained a stale pseudo-version for `pkg/docling-doc`:
```
github.com/finos/morphir/pkg/docling-doc v0.4.0-alpha.1-20260107094914-effc3f95fab5
```

**Root Cause**: When developing locally with go.work, pseudo-versions can get written to go.mod files. These become stale after tagging.

**Fix Applied**: Updated to proper version `v0.4.0-alpha.1`.

**Recommendation**:
- Add pre-release validation script to check for pseudo-versions
- Remove tests/bdd from goreleaser hooks (not a publishable module)

### 3. go.work Not Available in CI

**Problem**: Goreleaser hooks included `go work sync` which failed because go.work doesn't exist in CI.

**Error**:
```
go: no go.work file found
```

**Root Cause**: go.work is gitignored and only exists in local development. The release process ran in CI without it.

**Fix Applied**: Removed `go work sync` from goreleaser hooks.

**Recommendation**:
- Never include go.work-dependent commands in release hooks
- The hook was unnecessary anyway - go work sync is for development, not releases

### 4. Multi-Module Build Directory Not Configured

**Problem**: GoReleaser couldn't find the main module because the repo root has no go.mod.

**Error**:
```
go: cannot find main module, but found .git/config in /home/runner/work/morphir/morphir
```

**Root Cause**: In a multi-module monorepo, GoReleaser needs explicit `dir` configuration to know which directory to build from.

**Fix Applied**: Added `dir: cmd/morphir` and changed `main: .` in `.goreleaser.yaml`.

**Recommendation**:
- This is documented in GoReleaser docs but easy to miss for multi-module repos
- Add to release manager skill checklist

### 5. CHANGELOG.md Embed Missing for go install

**Problem**: `go install github.com/finos/morphir/cmd/morphir@v0.4.0-alpha.1` failed because the embedded CHANGELOG.md wasn't in the repo.

**Error**:
```
pattern CHANGELOG.md: no matching files found
```

**Root Cause**: The goreleaser hook copies CHANGELOG.md to cmd/morphir/cmd/, but this file was gitignored. When users run `go install`, they get the code from git which lacks this file.

**Fix Applied**:
- Removed gitignore entry for cmd/morphir/cmd/CHANGELOG.md
- Committed the file to git

**Recommendation**:
- Always commit files required by go:embed directives
- The goreleaser hook now serves as a sync mechanism, not a generator

### 6. Tag Recreation Workflow

**Problem**: Each fix required deleting and recreating all 13 tags, then re-triggering the release workflow.

**Root Cause**: Tags pointed to commits that needed fixes. New commits meant tags had to move.

**Impact**: Manual, error-prone process repeated 5+ times.

**Recommendation**:
- Create a script to automate tag deletion/recreation
- Consider using draft releases that can be edited before publishing

## Release Process Timeline

| Attempt | Issue | Resolution Time |
|---------|-------|-----------------|
| 1 | sum.golang.org 404 | ~5 min |
| 2 | sum.golang.org 404 (retry) | ~3 min |
| 3 | sum.golang.org 404 (retry) | ~3 min |
| 4 | Added GONOSUMDB, tests/bdd pseudo-version | ~5 min |
| 5 | go work sync failed | ~3 min |
| 6 | Multi-module build dir | ~3 min |
| 7 | **SUCCESS** | 2m 12s |

Total time: ~45 minutes for a release that should take less than 5 minutes.

## Recommendations

### Immediate Actions

1. **Pre-release Validation Script** (`scripts/release-validate.sh`):
   - Check for pseudo-versions in all go.mod files
   - Verify no replace directives exist
   - Verify CHANGELOG.md is committed in cmd/morphir/cmd/
   - Verify goreleaser config is valid
   - Run `goreleaser check`

2. **Tag Management Script** (`scripts/release-tags.sh`):
   - Create all module tags consistently
   - Delete and recreate tags when needed
   - Push tags with proper verification

3. **Release Verification Script** (`scripts/release-verify.sh`):
   - Wait for sum.golang.org indexing
   - Test `go install` with GONOSUMDB
   - Verify release assets exist
   - Check that all expected binaries are present

### Skill Updates

1. **release-manager skill**:
   - Add pre-release checklist
   - Add validation commands
   - Add tag management automation
   - Add verification steps

2. **morphir-developer skill**:
   - Add guidance on avoiding pseudo-versions
   - Add pre-commit checks for release-blocking issues

### CI/CD Updates

1. **release.yml workflow**:
   - Add pre-flight validation step
   - Consider two-phase release (validate, then release)
   - Add notification on failure with specific error guidance

2. **.goreleaser.yaml**:
   - Already fixed, but add comments explaining each section
   - Document the multi-module setup requirements

### CI External Consumption Test

The CI workflow includes a "Test External Consumption (Release PRs)" job that only runs when:
- The PR title contains "release", OR
- The PR has a "release" label

This test validates that `cmd/morphir` can be built without `go.work`, which catches:
- Missing go.sum entries for internal modules
- Incorrect module version references

**When to use this test:**
- Actual release PRs where module versions are being updated
- PRs that modify go.mod files with internal module dependencies

**Not needed for:**
- Regular feature/bugfix PRs (go.work handles cross-module development)
- Documentation or configuration changes

The pre-release validation script (`scripts/release-validate.sh`) complements this by checking for configuration issues (replace directives, pseudo-versions, etc.) that would cause release failures. Both checks serve different purposes:

| Check | Purpose | When to Run |
|-------|---------|-------------|
| External Consumption Test | Validates build without go.work | Release PRs only |
| Pre-release Validation | Checks configuration and setup | Before creating tags |

**Note**: The external consumption test may fail even on valid release PRs if the module versions in go.mod refer to the previous release (which is correct - they should reference the last published version, not the version being released). The release process updates versions before creating tags.

## Metrics

- **Release attempts**: 7
- **Unique issues encountered**: 5
- **Time to successful release**: ~45 minutes
- **Expected time (with automation)**: less than 10 minutes

## Action Items

- [ ] Create `scripts/release-validate.sh`
- [ ] Create `scripts/release-tags.sh`
- [ ] Create `scripts/release-verify.sh`
- [ ] Update release-manager skill with automation
- [ ] Update morphir-developer skill with release guidance
- [ ] Update AGENTS.md with release process reference
- [ ] Add pre-flight validation to release.yml workflow
- [ ] Create beads issue for each action item (if needed for tracking)
