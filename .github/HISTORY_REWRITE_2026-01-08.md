# Git History Rewrite - EasyCLA Compliance

## What Happened

The git history for this branch was rewritten on 2026-01-08 to remove EasyCLA-violating AI co-author references from commit messages.

## Why This Was Necessary

FINOS requires all contributors to sign the EasyCLA (Easy Contributor License Agreement). AI assistants (bots) cannot sign CLAs and therefore must not be listed as co-authors in commits.

## What Was Removed

The following line was removed from commit `342b8c9` (now `85c0cff`):
```
Co-authored-by: copilot-swe-agent[bot] <198982749+Copilot@users.noreply.github.com>
```

## What Was Preserved

All human co-authors remain intact:
- DamianReeves <957246+DamianReeves@users.noreply.github.com>

## Commit Mapping

| Original Commit | New Commit | Description |
|----------------|------------|-------------|
| d539687 | 24c9011 | fix: apply gofmt formatting and document future enhancements |
| fe30622 | 0906fed | Initial plan |
| 342b8c9 | 85c0cff | fix: update Docusaurus config (AI co-author removed) |

## Verification

- ✅ All tests pass
- ✅ Code unchanged
- ✅ Formatting valid
- ✅ Only human co-authors remain

## Tool Used

```bash
git filter-branch --msg-filter 'sed "/Co-authored-by:.*bot/d"' 61d3b85..HEAD
```

This rewrite complies with FINOS EasyCLA requirements and the guidance in `AGENTS.md`.
