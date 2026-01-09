#!/usr/bin/env bash
# Dynamically set up go.work for local module development
# This script discovers all Go modules in the repository and adds them to go.work

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

echo "🔍 Discovering Go modules..."

# Find all go.mod files (excluding vendor and node_modules)
MODULES=()
while IFS= read -r modfile; do
    moddir=$(dirname "$modfile")
    # Convert to relative path from project root
    reldir=$(realpath --relative-to="$PROJECT_ROOT" "$moddir" 2>/dev/null || python -c "import os.path; print(os.path.relpath('$moddir', '$PROJECT_ROOT'))")
    MODULES+=("$reldir")
    echo "  ✓ Found module: $reldir"
done < <(find . -name "go.mod" -type f -not -path "*/vendor/*" -not -path "*/node_modules/*" | sort)

if [ ${#MODULES[@]} -eq 0 ]; then
    echo "❌ No Go modules found!"
    exit 1
fi

echo ""
echo "📦 Setting up go.work with ${#MODULES[@]} modules..."

# Remove existing go.work if present (idempotent operation)
rm -f go.work go.work.sum

# Initialize go.work
go work init

# Add all discovered modules
for module in "${MODULES[@]}"; do
    echo "  ✓ Adding: $module"
    go work use "./$module"
done

echo ""
echo "🔁 Syncing workspace..."
if go work sync 2>/dev/null; then
    echo "  ✓ Workspace synced successfully"
else
    echo "  ⚠ Workspace sync failed (local dev still works without sync)"
fi

echo ""
echo "🔧 Workspace location:"
echo "  $(go env GOWORK)"

echo ""
echo "🔎 Sanity checks..."
if rg -n "^replace " --glob "*/go.mod" >/dev/null 2>&1; then
    echo "  ⚠ Found replace directives in go.mod files (remove them and use go.work)"
else
    echo "  ✓ No replace directives in go.mod files"
fi

if git status --short | rg -q "go.work"; then
    echo "  ⚠ go.work or go.work.sum is staged (do not commit workspace files)"
else
    echo "  ✓ go.work files are not staged"
fi

echo ""
echo "🏷️  Checking internal module tags..."
missing_tags=0
missing_replaces=0
replace_specs=()
while IFS= read -r modfile; do
    while read -r module version; do
        if [[ -z "$module" || -z "$version" ]]; then
            continue
        fi
        if [[ "$module" != github.com/finos/morphir/* ]]; then
            continue
        fi
        path="${module#github.com/finos/morphir/}"
        tag="${path}/${version}"
        if ! git tag -l "$tag" | rg -q .; then
            echo "  ⚠ Missing tag for ${module} (${version}) -> expected tag ${tag}"
            missing_tags=$((missing_tags + 1))
            if [[ -d "$PROJECT_ROOT/$path" ]]; then
                replace_specs+=("${module}@${version}=./${path}")
            fi
        fi
    done < <(awk '/github.com\/finos\/morphir\// {print $1, $2}' "$modfile")
done < <(find . -name "go.mod" -type f -not -path "*/vendor/*" -not -path "*/node_modules/*" | sort)

if [ "$missing_tags" -eq 0 ]; then
    echo "  ✓ All internal module version tags found"
else
    echo "  ⚠ ${missing_tags} internal module tag(s) missing (workspace will not override invalid versions)"
    if [ "${#replace_specs[@]}" -gt 0 ]; then
        echo "  🔧 Adding go.work replace directives for missing tags..."
        for spec in "${replace_specs[@]}"; do
            go work edit -replace="$spec"
            echo "    ✓ replace ${spec}"
            missing_replaces=$((missing_replaces + 1))
        done
        echo "  ✅ Added ${missing_replaces} local-only replace directive(s) to go.work"
    fi
fi

echo ""
echo "✅ Workspace configured successfully!"
echo ""
echo "Modules in workspace:"
go work use | sed 's/^/  - /'
