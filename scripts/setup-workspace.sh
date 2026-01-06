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
echo "✅ Workspace configured successfully!"
echo ""
echo "Modules in workspace:"
go work use | sed 's/^/  - /'
