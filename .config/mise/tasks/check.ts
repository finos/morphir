#!/usr/bin/env bun
// #MISE description="Run all checks (format, lint, typecheck)"
// #MISE alias="c"
// #MISE depends=["fmt-check", "lint", "typecheck"]

// This task aggregates all pre-commit/CI checks:
// - fmt-check: Go code formatting
// - lint: Go linting (golangci-lint)
// - typecheck: Type checking (WIT verification, etc.)

console.log("All checks passed!");
