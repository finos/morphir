# Pending BDD Tests

This document describes the `@pending` tag usage in the BDD test suite.

## Overview

Some BDD feature files are tagged with `@pending` to indicate that their step definitions are not yet implemented. These scenarios are automatically skipped during test runs.

## Configuration

The `bdd_test.go` file is configured to skip `@pending` tagged scenarios:

```go
Options: &godog.Options{
    Tags: "~@pending", // Skip scenarios tagged with @pending
    // ... other options
}
```

The `~` prefix means "NOT" - so `~@pending` means "skip any scenario tagged with @pending".

## Current Pending Features

### Docling Features

The following docling features are tagged as `@pending` because their step definitions (`docling_steps.go`) have not been implemented yet:

- `features/docling/document.feature` - Document creation and manipulation
- `features/docling/navigation.feature` - Document hierarchy navigation
- `features/docling/serialization.feature` - JSON serialization/deserialization
- `features/docling/traversal.feature` - Document tree traversal

**Total pending scenarios:** ~30 scenarios across 328 lines of feature specifications

## Implementing Pending Features

To implement a pending feature:

1. Create the necessary step definition file (e.g., `steps/docling_steps.go`)
2. Implement all step functions matching the feature specifications
3. Add appropriate context types to manage state
4. Register the steps in `bdd_test.go` (add `steps.RegisterDoclingSteps(sc)`)
5. Remove the `@pending` tag from the feature file
6. Run tests to verify: `go test -v`

## Running Only Pending Tests

To see what scenarios are pending without running them:

```bash
# List all pending scenarios
cd tests/bdd
go test -v --tags="@pending" --dry-run
```

To run pending tests (which will fail with undefined steps):

```bash
cd tests/bdd
go test -v --tags="@pending"
```

## Related Documentation

- [Godog Tags Documentation](https://github.com/cucumber/godog#tags)
- [BDD Test Structure](./README.md)
- [Morphir IR Testing Guide](../../docs/testing.md)
