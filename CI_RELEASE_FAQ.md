# CI and Release Workflow FAQ

> **Quick Answer**: Our CI always tests **your actual PR code**, not old published versions. This is guaranteed by automated `go.work` setup in all CI jobs.

This document answers common questions about how our CI and release workflows handle Go's multi-module repository structure.

## Table of Contents

- [Core Concepts](#core-concepts)
- [CI Workflow Questions](#ci-workflow-questions)
- [Release Workflow Questions](#release-workflow-questions)
- [Developer Workflow Questions](#developer-workflow-questions)
- [Troubleshooting](#troubleshooting)

---

## Core Concepts

### What is go.work and why do we use it?

**go.work** is Go's official workspace file that tells the Go toolchain to use **local copies** of modules instead of downloading them from the module proxy.

**Why we use it:**
- ✅ **Local development**: Make changes across multiple modules instantly
- ✅ **CI consistency**: Ensures CI tests your actual PR code, not published versions
- ✅ **No replace directives**: Keeps go.mod files clean for `go install` compatibility
- ✅ **Official solution**: This is Go's recommended approach for multi-module repos

**What it does:**
```go
// go.work tells Go: "Use these local directories"
use (
    ./cmd/morphir
    ./pkg/config
    ./pkg/models
    ./pkg/pipeline
    ./pkg/sdk
    ./pkg/tooling
    ./tests/bdd
)
```

When `cmd/morphir` imports `github.com/finos/morphir/pkg/config`, Go uses the **local `./pkg/config` directory** instead of downloading `v0.3.1` from the internet.

### Why is go.work git-ignored?

**go.work files are local-only and never committed to git.**

**Reasons:**
1. **Developer flexibility**: Each developer's workspace setup may differ (worktrees, different paths, etc.)
2. **External consumption**: External users don't have a local workspace - they download published versions
3. **Release verification**: We need to verify that external users can consume our modules

**Instead of committing go.work:**
- **Local development**: Run `mise run setup-workspace` to create go.work locally
- **CI**: Automatically runs `mise run setup-workspace` before every build/test job
- **Release**: Tests work **without** go.work (simulating external consumption)

### What are "replace directives" and why don't we use them?

**Replace directives** redirect module imports to local paths:

```go
// go.mod (DON'T DO THIS)
replace github.com/finos/morphir/pkg/config => ../pkg/config
```

**Problems with replace directives:**
- ❌ **Breaks `go install`**: Users can't install with `go install github.com/finos/morphir/cmd/morphir@latest`
- ❌ **Committed to git**: Must be removed before release
- ❌ **Error-prone**: Easy to forget to remove, causing release failures

**Our solution: go.work instead of replace directives**
- ✅ **Local only**: Never committed to git
- ✅ **No cleanup needed**: Doesn't affect go.mod files
- ✅ **CI compatible**: Works in CI via automatic setup
- ✅ **Release compatible**: Modules work without it

---

## CI Workflow Questions

### Q: Does CI test my actual PR code or download old published versions?

**A: CI tests your actual PR code.**

**How it works:**

1. **Every CI job** runs `mise run setup-workspace` as the first step
2. This creates a `go.work` file that includes all modules in the PR
3. When tests/builds run, Go uses **local code from the PR checkout**, not published versions

**Example:**

```yaml
# .github/workflows/ci.yml
- name: Checkout code
  uses: actions/checkout@v6

- name: Set up Go workspace
  run: mise run setup-workspace  # ← Creates go.work with all modules

- name: Run tests
  run: mise run test  # ← Uses local code via go.work
```

**Proof you can verify:**

Run this in CI logs and you'll see workspace modules listed:
```bash
$ go work use | sed 's/^/  - /'
  - ./cmd/morphir
  - ./pkg/config
  - ./pkg/models
  # ... (all local modules)
```

### Q: If go.mod references v0.3.1, won't CI download v0.3.1 instead of my changes?

**A: No. go.work takes precedence over go.mod version requirements.**

**Go's module resolution order:**

1. **Check go.work first** - If a module is listed in go.work, use the local directory
2. **Check go.mod require** - Only if not in go.work, download the specified version

**Example:**

```go
// cmd/morphir/go.mod
require (
    github.com/finos/morphir/pkg/config v0.3.1  // ← This version is IGNORED when go.work exists
)

// go.work (created by CI)
use (
    ./pkg/config  // ← THIS is used instead
)
```

**Visual flow:**

```
CI Job starts
  └─> Checkout PR code (has your new changes in pkg/config)
      └─> Run mise run setup-workspace
          └─> Creates go.work listing ./pkg/config
              └─> Run tests
                  └─> Import github.com/finos/morphir/pkg/config
                      └─> Go checks: "Is pkg/config in go.work?"
                          └─> YES: Use ./pkg/config (your PR code)
                          └─> Tests run with YOUR changes ✅
```

### Q: Can I modify multiple modules in a single PR?

**A: Yes! That's exactly what go.work is designed for.**

**Example PR changing pkg/config + cmd/morphir:**

```bash
# Your PR contains:
pkg/config/config.go         # New function added
cmd/morphir/main.go          # Uses the new function
```

**CI workflow:**
1. Checkout: Gets both changed files
2. Setup workspace: Creates go.work with both modules
3. Build cmd/morphir: Uses local pkg/config with your new function
4. Tests: Run against your actual changes

**No version coordination needed!** CI automatically uses your local changes.

### Q: How does the external consumption test work?

**A: Release PRs get an additional test that builds WITHOUT go.work.**

**When it runs:**
- Only on PRs with "release" in the title or a `release` label
- See `.github/workflows/ci.yml` job: `test-external-consumption`

**What it does:**

```yaml
test-external-consumption:
  if: contains(github.event.pull_request.title, 'release')
  steps:
    - name: Checkout code
      uses: actions/checkout@v6

    # NOTE: No mise run setup-workspace step!

    - name: Test cmd/morphir builds without go.work
      working-directory: cmd/morphir
      run: |
        go mod download  # Downloads versions from go.mod
        go build .       # Builds using downloaded versions
```

**Why this matters:**

This simulates how an **external user** would consume your modules:

```bash
# External user runs:
go install github.com/finos/morphir/cmd/morphir@v0.3.2

# This downloads:
# - cmd/morphir@v0.3.2
# - pkg/config@v0.3.1 (from go.mod require statement)
# - pkg/tooling@v0.3.1 (from go.mod require statement)

# External consumption test verifies this works BEFORE release
```

**Regular vs Release PRs:**

| PR Type | Regular Jobs (with go.work) | External Consumption Test (no go.work) |
|---------|----------------------------|----------------------------------------|
| **Feature PR** | ✅ Runs | ❌ Skipped |
| **Release PR** | ✅ Runs | ✅ Runs |

### Q: What does mise run setup-workspace actually do?

**A: Dynamically discovers all Go modules and creates a workspace.**

**Script behavior:**

```bash
#!/usr/bin/env bash
# 1. Find all go.mod files in the repository
find . -name "go.mod" -type f -not -path "*/vendor/*" -not -path "*/node_modules/*"

# 2. Initialize workspace
go work init

# 3. Add each module to workspace
for module in "${MODULES[@]}"; do
    go work use "./$module"
done

# Result: go.work file with all modules listed
```

**Output example:**

```
🔍 Discovering Go modules...
  ✓ Found module: cmd/morphir
  ✓ Found module: pkg/config
  ✓ Found module: pkg/models
  ✓ Found module: pkg/pipeline
  ✓ Found module: pkg/sdk
  ✓ Found module: pkg/tooling
  ✓ Found module: tests/bdd

📦 Setting up go.work with 7 modules...
  ✓ Adding: cmd/morphir
  ✓ Adding: pkg/config
  ...

✅ Workspace configured successfully!
```

**Why dynamic discovery?**

- ✅ **Automatic**: New modules are automatically detected
- ✅ **No hardcoding**: No manual list to maintain
- ✅ **Reliable**: Works across different branches and worktrees

---

## Release Workflow Questions

### Q: Does the release workflow use go.work or the actual version tags?

**A: The release workflow builds from a git tag, which is a snapshot of all code at that commit.**

**Release process:**

1. **Create release PR** with CHANGELOG and any needed updates
2. **Merge PR** to main (triggers CI with go.work)
3. **Create git tags** pointing to the merged commit:
   ```bash
   git tag -a v0.3.2 -m "Release v0.3.2"
   git tag -a pkg/config/v0.3.2 -m "Release pkg/config v0.3.2"
   # ... (one tag per module)
   ```
4. **Push tags** to trigger GitHub release workflow
5. **GoReleaser checks out the tag** and builds

**Key insight: Git tags are commit snapshots**

When GoReleaser checks out tag `v0.3.2`:

```
v0.3.2 tag checkout (complete snapshot):
├── cmd/morphir/
│   ├── main.go (NEW v0.3.2 code)
│   └── go.mod (requires pkg/config v0.3.1)
├── pkg/config/
│   └── config.go (NEW v0.3.2 code)  ← This local code is used!
```

**Go's path-based resolution during release:**

```bash
# In the tag checkout, when building cmd/morphir:
cd cmd/morphir
go build .

# Go resolves imports:
import "github.com/finos/morphir/pkg/config"
  ├─> Check: Is there a local directory "../pkg/config"?
  ├─> YES: Directory structure matches import path
  └─> Use local directory (with v0.3.2 code from tag)
```

**This is path-based resolution, NOT go.work**

Go uses local directories when:
1. The directory structure matches the import path
2. You're building from that repository root

This is **implicit behavior** that always worked. We made CI **explicit** by adding go.work.

### Q: Why do release PR go.mod files reference v0.3.1 when we're releasing v0.3.2?

**A: Because v0.3.2 doesn't exist yet when the PR is created.**

**Timeline:**

```
1. Create release PR
   └─> go.mod still references v0.3.1 (current published version)
   └─> CI uses go.work → tests local v0.3.2 code ✅
   └─> External consumption test → verifies v0.3.1 references work ✅

2. Merge PR to main
   └─> Commit on main has go.mod referencing v0.3.1

3. Create tags v0.3.2 pointing to that commit
   └─> Tags create a snapshot with v0.3.2 code

4. GoReleaser builds from tag
   └─> Uses path-based resolution → v0.3.2 code from tag ✅
   └─> Publishes v0.3.2 to module registry

5. Now v0.3.2 exists
   └─> External users can download it
   └─> Future PRs reference v0.3.2
```

**Why not update go.mod to v0.3.2 before release?**

```bash
# ❌ WRONG - External consumption test would fail
require (
    github.com/finos/morphir/pkg/config v0.3.2  # Doesn't exist yet!
)

# When external consumption test runs:
$ go mod download
# Error: unknown revision pkg/config/v0.3.2

# ✅ CORRECT - External consumption test passes
require (
    github.com/finos/morphir/pkg/config v0.3.1  # Current published version
)

# After release, go.mod versions are irrelevant because:
# - Tag contains all the code
# - Path-based resolution uses local code
# - GoReleaser builds successfully
```

### Q: How do I verify the release will work before creating tags?

**A: Test with a local tag checkout.**

**Verification steps:**

```bash
# 1. Create a test tag locally (don't push)
git tag -a test-v0.3.2 -m "Test release"

# 2. Check out the tag in a temp directory
cd /tmp
git clone /path/to/morphir morphir-test
cd morphir-test
git checkout test-v0.3.2

# 3. Build WITHOUT go.work (like GoReleaser does)
cd cmd/morphir
go build .

# 4. Verify it built successfully
./morphir --version

# 5. Clean up
cd /tmp
rm -rf morphir-test
cd /path/to/morphir
git tag -d test-v0.3.2
```

**If step 3 succeeds**, the release will work.

**Common issues this catches:**
- Missing dependencies in go.mod
- Incorrect module paths
- Build errors

### Q: What happens after the release is created?

**A: Modules are published to the Go module proxy automatically.**

**Post-release flow:**

1. **GitHub Release created** with binaries and checksums
2. **Git tags pushed** to GitHub
3. **Go module proxy** detects new tags
4. **Modules become available** at https://pkg.go.dev

**Verification:**

```bash
# Wait 5-10 minutes, then:

# Check module availability
go list -m github.com/finos/morphir/pkg/config@v0.3.2

# Test installation
go install github.com/finos/morphir/cmd/morphir@v0.3.2

# Verify in a test project
mkdir /tmp/test-morphir
cd /tmp/test-morphir
go mod init example.com/test
go get github.com/finos/morphir/pkg/config@v0.3.2
```

**Expected result:**
- All commands succeed
- go.mod shows v0.3.2 versions (not pseudo-versions)
- No "unknown revision" errors

---

## Developer Workflow Questions

### Q: How do I set up my local development environment?

**A: Run the setup script once.**

```bash
# Clone repository
git clone https://github.com/finos/morphir.git
cd morphir

# Set up workspace
mise run setup-workspace

# Verify setup
mise run verify
```

**What this does:**
- ✅ Creates go.work with all modules
- ✅ Syncs workspace
- ✅ Enables cross-module development

**You only need to run this:**
- Once after initial clone
- After pulling changes that add new modules
- If you accidentally delete go.work

### Q: Can I work on multiple branches simultaneously?

**A: Yes, using git worktrees.**

**Worktree setup:**

```bash
# Create worktree for feature branch
git worktree add ../morphir-feature-x feature/feature-x

# Each worktree needs its own go.work
cd ../morphir-feature-x
mise run setup-workspace

# Now you have:
# - morphir/ (main branch) with go.work
# - morphir-feature-x/ (feature branch) with go.work
```

**Both worktrees work independently:**

```bash
# In morphir/
cd morphir
mise run test  # Uses local go.work

# In morphir-feature-x/
cd ../morphir-feature-x
mise run test  # Uses its own go.work
```

### Q: What should I NEVER commit?

**A: Never commit go.work or go.work.sum files.**

**.gitignore includes:**
```gitignore
# Go workspace (local only)
go.work
go.work.sum
```

**Pre-commit checklist:**

```bash
# Check what's staged
git status

# If you see go.work or go.work.sum:
git reset go.work go.work.sum

# Verify they're not staged
git status | grep -E "go.work"  # Should output nothing
```

**Why this matters:**
- ❌ **Different paths**: Each developer may have different workspace configurations
- ❌ **CI doesn't need it**: CI creates its own go.work
- ❌ **External users**: Don't have local workspace

### Q: How do I know if CI will pass before pushing?

**A: Run the same checks locally.**

**Pre-push checklist:**

```bash
# 1. Ensure go.work exists
ls go.work || mise run setup-workspace

# 2. Format code
mise run fmt

# 3. Run linters
mise run lint

# 4. Verify all modules build
mise run verify

# 5. Run tests
mise run test

# 6. Check for uncommitted changes
git status

# 7. Verify go.work not staged
git status --short | grep go.work && echo "❌ go.work is staged!" || echo "✅ Clean"
```

**If all pass locally, CI will likely pass.**

**CI runs the same commands:**
- Creates go.work via `mise run setup-workspace`
- Runs `mise run lint`, `mise run test`, `mise run verify`
- Uses the same Go version (1.25.5)

---

## Troubleshooting

### "Package not found" errors locally

**Symptom:**
```bash
$ go build ./cmd/morphir
package github.com/finos/morphir/pkg/config is not in std
```

**Diagnosis:**

```bash
# Check if go.work exists
ls go.work

# If missing, create it:
mise run setup-workspace

# If exists, verify it has the module:
grep "pkg/config" go.work
```

**Solutions:**

```bash
# Solution 1: Recreate workspace
mise run setup-workspace

# Solution 2: Manually add missing module
go work use ./pkg/config

# Solution 3: Sync workspace
go work sync

# Verify fix
go build ./cmd/morphir
```

### "Unknown revision" errors in CI

**Symptom:**
```
Error: unknown revision pkg/config/v0.3.2
```

**Cause:** go.mod references a version that doesn't exist yet.

**Common scenarios:**

1. **Regular PR**: Shouldn't happen (go.work is used)
2. **Release PR**: External consumption test fails

**Solution for release PRs:**

```bash
# go.mod should reference CURRENT version, not new version
# ❌ WRONG
require github.com/finos/morphir/pkg/config v0.3.2

# ✅ CORRECT
require github.com/finos/morphir/pkg/config v0.3.1
```

Update go.mod files to reference the **currently published** version.

### CI passes but local build fails

**Symptom:**
```bash
$ mise run verify
# Fails locally but CI shows ✅
```

**Common causes:**

1. **Stale dependencies**

```bash
# Sync workspace
go work sync

# Update all modules
mise run mod-tidy

# Retry
mise run verify
```

2. **Missing go.work**

```bash
# Recreate workspace
mise run setup-workspace

# Retry
mise run verify
```

3. **Different Go version**

```bash
# Check version
go version  # Should be 1.25.5 or later

# Update if needed
# https://go.dev/doc/install
```

### Local build passes but CI fails

**Symptom:**
```bash
$ mise run verify
✅ Success

# But CI shows ❌
```

**Common causes:**

1. **Uncommitted changes**

```bash
# Check for uncommitted files
git status

# CI doesn't have your uncommitted changes
git add . && git commit
```

2. **Platform-specific issues**

```bash
# CI runs on Linux, macOS, Windows
# Your local: probably one platform

# Check CI logs for which platform failed
gh run view --log-failed
```

3. **go.work accidentally committed**

```bash
# Check if committed
git ls-files | grep go.work

# If found, remove from git:
git rm --cached go.work go.work.sum
git commit -m "fix: remove go.work from git"
```

### External consumption test fails on release PR

**Symptom:**
```
test-external-consumption job fails
Error: go build failed
```

**Diagnosis:**

```bash
# Test locally WITHOUT go.work
mv go.work go.work.backup
cd cmd/morphir
go mod download
go build .

# Restore workspace
cd ../..
mv go.work.backup go.work
```

**Common causes and fixes:**

1. **go.mod references future version**

```bash
# Fix: Update to current version
cd cmd/morphir
go mod edit -require=github.com/finos/morphir/pkg/config@v0.3.1
```

2. **Missing dependency in go.mod**

```bash
# Fix: Add dependency
cd cmd/morphir
go get github.com/finos/morphir/pkg/models@v0.3.1
```

3. **Invalid module version**

```bash
# Fix: Check for v0.0.0 or pseudo-versions
grep "v0.0.0\|00010101000000" cmd/morphir/go.mod

# Update to real version
go mod edit -require=github.com/finos/morphir/pkg/config@v0.3.1
```

---

## Quick Reference

### For Regular Development

```bash
# Setup (once)
mise run setup-workspace

# Daily workflow
mise run verify  # Build + test
mise run test    # Run tests only
mise run fmt     # Format code
mise run lint    # Run linters

# Pre-commit
git status   # Check what's staged
# Ensure go.work NOT in staged files
```

### For Release PRs

```bash
# go.mod should reference CURRENT version
# ✅ v0.3.1 if releasing v0.3.2
# ❌ NOT v0.3.2 (doesn't exist yet)

# External consumption test will verify this
```

### For CI Understanding

```bash
# CI always runs:
1. mise run setup-workspace  # Create go.work
2. mise run test          # Use local code
3. mise run verify        # Build local code

# Release PRs additionally run:
4. go build (no go.work)  # Test external consumption
```

---

## Key Takeaways

1. ✅ **CI uses your PR code** via automatic go.work setup
2. ✅ **Multi-module PRs work** because go.work includes all modules
3. ✅ **Releases use path-based resolution** from git tag snapshots
4. ✅ **go.work is never committed** - it's local-only and auto-generated
5. ✅ **No replace directives** - go.work provides a cleaner solution
6. ✅ **External consumption is tested** before release via dedicated CI job

**Bottom line:** The workflow is designed to give you confidence that:
- Your changes are tested as you wrote them
- Multiple modules can be changed together safely
- Releases will work for external users
- Everything is automated and consistent

---

## Additional Resources

- [DEVELOPING.md](./DEVELOPING.md) - Development workflow guide
- [AGENTS.md](./AGENTS.md) - Detailed release process
- [Go Workspaces](https://go.dev/doc/tutorial/workspaces) - Official documentation
- [Morphir Developer Skill](./.claude/skills/morphir-developer.md) - AI assistant for development
- [Release Manager Skill](./.claude/skills/release-manager.md) - AI assistant for releases

**Questions not answered here?**

Open an issue: https://github.com/finos/morphir/issues/new
