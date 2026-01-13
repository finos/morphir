#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

"$SCRIPT_DIR/sync-changelog.sh"

echo "Testing external consumption (no go.work)..."
echo "This verifies that module versions in go.mod are correct."

cd "$REPO_ROOT/cmd/morphir"

# Backup go.mod for restoration
cp go.mod go.mod.backup

# Find internal morphir modules that don't have published versions
# and add temporary replace directives for them
echo ""
echo "Checking for unpublished internal modules..."

UNPUBLISHED_MODULES=()

while IFS= read -r line; do
    # Extract module path and version from require lines
    if [[ "$line" =~ github\.com/finos/morphir/([^[:space:]]+)[[:space:]]+([^[:space:]]+) ]]; then
        module_path="${BASH_REMATCH[1]}"
        version="${BASH_REMATCH[2]}"
        full_module="github.com/finos/morphir/$module_path"

        # Check if this version exists by trying to list it
        # Use GOPROXY=direct to bypass cache
        if ! GOPROXY=direct go list -m "$full_module@$version" &>/dev/null 2>&1; then
            echo "  ⚠ Unpublished: $full_module@$version"
            UNPUBLISHED_MODULES+=("$module_path:$version")
        fi
    fi
done < <(grep "github.com/finos/morphir/" go.mod | grep -v "^module")

# Add replace directives for unpublished modules
if [ ${#UNPUBLISHED_MODULES[@]} -gt 0 ]; then
    echo ""
    echo "Adding temporary replace directives for ${#UNPUBLISHED_MODULES[@]} unpublished module(s)..."

    for entry in "${UNPUBLISHED_MODULES[@]}"; do
        module_path="${entry%:*}"
        version="${entry#*:}"
        full_module="github.com/finos/morphir/$module_path"
        local_path="../../$module_path"

        # Check if local path exists
        if [ -d "$local_path" ]; then
            echo "  → replace $full_module $version => $local_path"
            go mod edit -replace="$full_module@$version=$local_path"
        else
            echo "  ✗ Local path not found: $local_path"
            # Restore and fail
            mv go.mod.backup go.mod
            exit 1
        fi
    done

    echo ""
    echo "Note: These modules are new and will be published with this release."
    echo "      The replace directives simulate what will happen after tagging."
fi

echo ""
echo "Downloading dependencies..."
go mod download

echo "Building cmd/morphir..."
go build .

# Restore original go.mod
mv go.mod.backup go.mod

echo ""
echo "✅ cmd/morphir builds successfully as external consumer would use it"
