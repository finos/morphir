#!/bin/bash
# Fetches morphir IR fixtures from upstream repositories
#
# Usage: ./fetch-fixtures.sh
#
# This script:
# 1. Clones morphir-elm and builds the reference model to generate morphir-ir.json
# 2. Creates V1/V2/V3 format variants of fixtures
# 3. Places all fixtures in the testdata directory

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTDATA_DIR="$SCRIPT_DIR/../testdata"

echo "=== Morphir IR Fixture Fetcher ==="
echo "Output directory: $TESTDATA_DIR"

# Check for required tools
check_requirements() {
    echo "Checking requirements..."

    if ! command -v npm &> /dev/null; then
        echo "Error: npm is required but not installed."
        echo "Please install Node.js and npm first."
        exit 1
    fi

    if ! command -v git &> /dev/null; then
        echo "Error: git is required but not installed."
        exit 1
    fi

    echo "All requirements met."
}

# Fetch and build morphir-elm reference model
fetch_morphir_elm() {
    echo ""
    echo "=== Fetching morphir-elm reference model ==="

    local TEMP_DIR=$(mktemp -d)
    echo "Working in: $TEMP_DIR"

    cd "$TEMP_DIR"

    echo "Cloning morphir-elm (shallow)..."
    git clone --depth 1 https://github.com/finos/morphir-elm.git

    cd morphir-elm/tests-integration/reference-model

    echo "Installing morphir-elm CLI..."
    npm install -g morphir-elm || {
        echo "Warning: Global install failed, trying local..."
        npm install morphir-elm
    }

    echo "Building reference model..."
    npx morphir-elm make || morphir-elm make

    if [ -f "morphir-ir.json" ]; then
        echo "Success! Copying morphir-ir.json..."
        mkdir -p "$TESTDATA_DIR/morphir-elm/reference-model"
        cp morphir-ir.json "$TESTDATA_DIR/morphir-elm/reference-model/"
        echo "Copied to: $TESTDATA_DIR/morphir-elm/reference-model/morphir-ir.json"
    else
        echo "Error: morphir-ir.json was not generated"
        exit 1
    fi

    # Cleanup
    cd /
    rm -rf "$TEMP_DIR"

    echo "Done fetching morphir-elm fixtures."
}

# Create minimal test fixtures for each format version
create_minimal_fixtures() {
    echo ""
    echo "=== Creating minimal test fixtures ==="

    # V3 format (PascalCase) - minimal library
    mkdir -p "$TESTDATA_DIR/v3"
    cat > "$TESTDATA_DIR/v3/simple-library.json" << 'EOF'
["Library",[["test"]],[],{"modules":[]}]
EOF
    echo "Created: $TESTDATA_DIR/v3/simple-library.json"

    # V1 format (snake_case) - minimal library
    mkdir -p "$TESTDATA_DIR/v1"
    cat > "$TESTDATA_DIR/v1/simple-library.json" << 'EOF'
["library",[["test"]],[],{"modules":[]}]
EOF
    echo "Created: $TESTDATA_DIR/v1/simple-library.json"

    # V3 type fixtures
    cat > "$TESTDATA_DIR/v3/type-unit.json" << 'EOF'
["Unit",[]]
EOF
    echo "Created: $TESTDATA_DIR/v3/type-unit.json"

    cat > "$TESTDATA_DIR/v3/type-variable.json" << 'EOF'
["Variable",[],["x"]]
EOF
    echo "Created: $TESTDATA_DIR/v3/type-variable.json"

    cat > "$TESTDATA_DIR/v3/type-record.json" << 'EOF'
["Record",[],[]]
EOF
    echo "Created: $TESTDATA_DIR/v3/type-record.json"

    # V1 type fixtures (snake_case tags)
    cat > "$TESTDATA_DIR/v1/type-unit.json" << 'EOF'
["unit",[]]
EOF
    echo "Created: $TESTDATA_DIR/v1/type-unit.json"

    cat > "$TESTDATA_DIR/v1/type-variable.json" << 'EOF'
["variable",[],["x"]]
EOF
    echo "Created: $TESTDATA_DIR/v1/type-variable.json"

    echo "Done creating minimal fixtures."
}

# Create README for attribution
create_readme() {
    echo ""
    echo "=== Creating README ==="

    cat > "$TESTDATA_DIR/README.md" << 'EOF'
# Test Fixtures

This directory contains morphir IR test fixtures for BDD testing.

## Sources

### morphir-elm/
Fixtures generated from the [finos/morphir-elm](https://github.com/finos/morphir-elm)
reference model using `morphir-elm make`.

### v1/, v2/, v3/
Hand-crafted minimal fixtures for testing format version compatibility:
- **v1**: Legacy format with snake_case tags (e.g., "unit", "variable")
- **v2**: Transitional format
- **v3**: Current format with PascalCase tags (e.g., "Unit", "Variable")

## Regenerating Fixtures

Run the fetch script to regenerate fixtures:
```bash
./scripts/fetch-fixtures.sh
```

## License

These fixtures are used for testing purposes only.
The morphir-elm fixtures are subject to the Apache 2.0 license from finos/morphir-elm.
EOF

    echo "Created: $TESTDATA_DIR/README.md"
}

# Main
main() {
    check_requirements

    # Always create minimal fixtures first (no external deps needed)
    create_minimal_fixtures

    # Try to fetch morphir-elm, but don't fail if it doesn't work
    if [ "$1" == "--skip-elm" ]; then
        echo ""
        echo "Skipping morphir-elm fetch (--skip-elm specified)"
    else
        fetch_morphir_elm || {
            echo ""
            echo "Warning: Failed to fetch morphir-elm fixtures."
            echo "Minimal fixtures are still available for testing."
            echo "Re-run without --skip-elm once morphir-elm CLI is available."
        }
    fi

    create_readme

    echo ""
    echo "=== Fixture setup complete ==="
    echo "Fixtures available in: $TESTDATA_DIR"
}

main "$@"
