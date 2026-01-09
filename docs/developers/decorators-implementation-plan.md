# Decorators Feature Implementation Plan

## Overview

This document outlines the implementation plan for the decorators feature in Morphir Go. Decorators allow users to attach additional metadata to Morphir IR elements (types, values, modules) that cannot be captured in the source language. The metadata is stored in sidecar files and its shape is defined using Morphir IR itself.

## Current Status

✅ **Completed:**
- Configuration parsing for decorations in `morphir.json` and `morphir.toml`
- `DecorationConfig` type with all required fields
- Integration with `ProjectSection` and `workspace.Project`
- Basic test coverage for configuration loading

## Architecture Overview

The decorators system consists of several components:

1. **Configuration Layer** (✅ Complete)
   - Parsing decoration configs from `morphir.json`/`morphir.toml`
   - Storing decoration metadata (displayName, ir, entryPoint, storageLocation)

2. **Decoration IR Loading** (⏳ TODO)
   - Load decoration schema IR files
   - Validate entry point references
   - Extract type definitions for decoration shapes

3. **Decoration Value Storage** (⏳ TODO)
   - Load/save decoration value files (JSON)
   - Map decoration values to IR nodes using FQNames
   - Validate values against decoration schemas

4. **IR Integration** (⏳ TODO)
   - Attach decorations to IR nodes (types, values, modules)
   - Support decoration queries/access
   - Maintain decoration-to-node mappings

5. **CLI Commands** (⏳ TODO)
   - `morphir decoration-setup` - Auto-configure decorations
   - `morphir decoration-validate` - Validate decoration values

6. **API Endpoints** (⏳ TODO)
   - `/server/attributes` - Expose decoration configs for develop UI
   - Decoration CRUD operations

7. **Test Fixtures** (⏳ TODO)
   - Extract test fixtures from morphir-elm
   - Create example decoration schemas
   - Create example decoration value files

## Implementation Phases

### Phase 1: Core Decoration Infrastructure

**Goal:** Build the foundation for loading and validating decorations.

**Beads Issues:**
- `morphir-om0` - Phase 1: Core Decoration Infrastructure (feature)
- `morphir-3cr` - Load and validate decoration IR files
- `morphir-zdb` - Implement decoration value file loader/saver
- `morphir-dmi` - Validate decoration values against schemas

**Tasks:**
1. Create decoration IR loader (`morphir-3cr`)
   - Load Morphir IR files for decoration schemas
   - Parse entry point FQNames (PackageName:ModuleName:TypeName)
   - Validate entry point exists in decoration IR
   - Extract type definitions for decoration shapes

2. Implement entry point validation (`morphir-3cr`)
   - Validate FQName format
   - Check package name matches decoration IR
   - Verify module exists in decoration IR
   - Verify type exists in module

3. Create decoration value file loader/saver (`morphir-zdb`)
   - Load JSON files keyed by FQName
   - Save decoration values to JSON files
   - Maintain FQName-to-value mappings
   - Support empty decoration files

4. Implement FQName-based node mapping (`morphir-zdb`)
   - Map decoration values to IR nodes using FQNames
   - Support types: `PackageName:ModuleName:TypeName`
   - Support values: `PackageName:ModuleName:ValueName`
   - Support modules: `PackageName:ModuleName`

5. Validate decoration values against schemas (`morphir-dmi`)
   - Load decoration IR for schema
   - Find entry point type definition
   - Validate values conform to type
   - Return clear validation errors with FQName context

**Dependencies:** None

**Estimated Effort:** Medium

**Reference Implementation:**
- morphir-elm: CustomAttribute configuration processing
- morphir-elm: Decoration IR loading and validation

### Phase 2: IR Integration

**Goal:** Integrate decorations with Morphir IR types.

**Beads Issues:**
- `morphir-msl` - Phase 2: IR Integration (feature)
- `morphir-86i` - Attach decorations to IR nodes
- `morphir-bxw` - Implement decoration queries and accessors

**Tasks:**
1. Design decoration attachment mechanism (`morphir-86i`)
   - Decide on decoration storage (separate map vs. embedded)
   - Ensure immutability of IR nodes
   - Support decoration-to-node mappings
   - Handle decoration updates

2. Extend IR types to support decoration metadata (`morphir-86i`)
   - Add decoration accessor methods
   - Maintain decoration-to-node mappings
   - Support decoration queries by FQName

3. Implement decoration queries/accessors (`morphir-bxw`)
   - Get all decorations for a node
   - Get specific decoration by ID
   - Check if node has decorations
   - Support filtering by decoration type

4. Add decoration validation during IR processing (`morphir-86i`)
   - Validate decorations when loading IR
   - Report validation errors
   - Support optional validation (warnings vs. errors)

**Dependencies:** Phase 1

**Estimated Effort:** Medium-High

**Reference Implementation:**
- morphir-elm: CustomAttribute attachment to IR nodes
- morphir-elm: Decoration query patterns

### Phase 3: CLI Commands

**Goal:** Provide command-line tools for decoration management.

**Beads Issues:**
- `morphir-p6n` - Phase 3: CLI Commands (feature)
- `morphir-snf` - Implement morphir decoration-setup command
- `morphir-hvp` - Implement morphir decoration-validate command

**Tasks:**
1. Implement `decoration-setup` command (`morphir-snf`)
   - Read decoration IR file
   - Detect entry point from decoration IR
   - Add decoration config to `morphir.json`/`morphir.toml`
   - Support `-i` flag for decoration IR path
   - Support `--storage-location` flag

2. Implement `decoration-validate` command (`morphir-hvp`)
   - Load all decoration configs from project
   - Load decoration value files
   - Validate all decoration values against schemas
   - Report validation errors with FQName context
   - Support `--json` flag for machine-readable output
   - Exit with non-zero code on validation failures

3. Add decoration-related flags to existing commands
   - Add `--with-decorations` flag to `morphir make`
   - Add decoration validation to `morphir validate`
   - Support decoration filtering in queries

**Dependencies:** Phase 1, Phase 2

**Estimated Effort:** Low-Medium

**Reference Implementation:**
- morphir-elm: `morphir decoration-setup` command
- morphir-elm: Decoration validation patterns

### Phase 4: API Endpoints

**Goal:** Enable develop UI integration.

**Beads Issues:**
- `morphir-p02` - Phase 4: API Endpoints (feature)
- `morphir-kes` - Create /server/attributes API endpoint
- `morphir-9w5` - Implement decoration CRUD operations API

**Tasks:**
1. Create `/server/attributes` endpoint (`morphir-kes`)
   - Expose processed decoration configuration
   - Return decoration configs with displayName, entryPoint, data, IR
   - Match morphir-elm API contract for compatibility
   - Support JSON response format

2. Implement decoration CRUD operations (`morphir-9w5`)
   - GET decorations for a node (by FQName)
   - POST/PUT to update decoration values
   - DELETE to remove decorations
   - Support FQName-based node identification
   - Validate values against schemas on write operations

3. Add decoration value validation endpoints
   - POST `/server/attributes/validate` - Validate single decoration value
   - POST `/server/attributes/validate-all` - Validate all decorations
   - Return validation errors with context

4. Support real-time decoration updates
   - Watch decoration value files for changes
   - Notify clients of decoration updates
   - Support WebSocket or polling for updates

**Dependencies:** Phase 1, Phase 2

**Estimated Effort:** Medium

**Reference Implementation:**
- morphir-elm: `/server/attributes` endpoint implementation
- morphir-elm: Decoration CRUD operations

### Phase 5: Test Fixtures and Examples

**Goal:** Provide comprehensive test coverage and examples.

**Beads Issues:**
- `morphir-zzc` - Phase 5: Test Fixtures and Examples (feature)
- `morphir-ckf` - Extract test fixtures from morphir-elm for decorations
- `morphir-nfo` - Create example decoration schemas and value files

**Tasks:**
1. Extract test fixtures from morphir-elm (`morphir-ckf`)
   - Find decoration schema examples in morphir-elm
   - Extract decoration value file examples
   - Extract integration test patterns
   - Adapt fixtures for Go testing
   - Place in `tests/bdd/testdata/decorations/` directory

2. Create example decoration schemas (`morphir-nfo`)
   - Simple decoration schema (e.g., boolean flag)
   - Complex decoration schema (e.g., structured metadata)
   - Place in `examples/decorations/` directory

3. Create example decoration value files (`morphir-nfo`)
   - Example value files with various FQName mappings
   - Include edge cases (empty files, invalid FQNames, etc.)
   - Place in `examples/decorations/` directory

4. Create integration tests
   - Test decoration loading end-to-end
   - Test decoration validation
   - Test decoration CRUD operations
   - Test CLI commands

5. Update documentation with examples
   - Add decoration examples to user guide
   - Add developer examples to developer guide
   - Include example decoration schemas in docs

**Dependencies:** All previous phases

**Estimated Effort:** Low-Medium

**Reference Sources:**
- morphir-elm: `tests-integration/cli/test-ir-files` directory
- morphir-elm: Example decoration schemas
- morphir-elm: Integration tests

## Key Design Decisions

### Decoration Storage Format

Decoration values are stored as JSON files with FQName keys:

```json
{
  "My.Package:Foo:bar": <decoration-value>,
  "My.Package:Baz:bat": <decoration-value>
}
```

### Entry Point Format

Entry points use FQName format: `PackageName:ModuleName:TypeName`

Example: `My.Amazing.Decoration:Foo:Shape`

### Decoration Schema Validation

Decoration values must conform to the type defined at the entry point in the decoration IR. This requires:
- Loading the decoration IR
- Finding the entry point type
- Validating values against that type

### IR Node Identification

IR nodes are identified using FQNames:
- Types: `PackageName:ModuleName:TypeName`
- Values: `PackageName:ModuleName:ValueName`
- Modules: `PackageName:ModuleName` (for module-level decorations)

### Immutability

All decoration operations must maintain immutability:
- IR nodes are not mutated
- Decorations are stored separately
- Accessors return defensive copies
- Updates create new instances

## Reference Implementation

The morphir-elm implementation provides the reference:

- **Configuration:** `morphir.json` with `decorations` field
- **Storage:** JSON files keyed by FQName
- **API:** `/server/attributes` endpoint
- **UI:** Morphir Web with "Decorations" tab

### Key Files in morphir-elm

1. **CustomAttribute Types:**
   - `src/Morphir/CustomAttribute/CustomAttribute.elm` - Core types
   - `src/Morphir/CustomAttribute/CustomAttributeConfig.elm` - Configuration types

2. **Decoration Processing:**
   - JavaScript: Decoration configuration processing
   - Elm: CustomAttributeConfigs decoding

3. **API Endpoints:**
   - `/server/attributes` route implementation

4. **CLI Commands:**
   - `decoration-setup` command implementation

## Test Fixtures from morphir-elm

The morphir-elm codebase contains:
- Example decoration schemas (IR files)
- Example decoration value files (JSON)
- Integration tests

These should be extracted and adapted for Go testing. Key locations:
- `tests-integration/cli/test-ir-files/` - IR test fixtures
- Example decoration schemas in morphir-elm source
- Integration test examples

## Success Criteria

1. ✅ Configuration parsing works (complete)
2. ⏳ Can load decoration IR files
3. ⏳ Can load/save decoration value files
4. ⏳ Can validate decoration values against schemas
5. ⏳ Can attach decorations to IR nodes
6. ⏳ CLI commands work
7. ⏳ API endpoints work
8. ⏳ Comprehensive test coverage

## Next Steps

1. ✅ Review this plan (complete)
2. ✅ Create beads issues for each phase (complete)
3. ⏳ Start with Phase 1 implementation
4. ⏳ Extract test fixtures from morphir-elm

## Beads Issues Summary

### Phase 1: Core Decoration Infrastructure
- `morphir-om0` - Phase 1 feature (depends on: morphir-3cr, morphir-zdb, morphir-dmi)
- `morphir-3cr` - Load and validate decoration IR files
- `morphir-zdb` - Implement decoration value file loader/saver
- `morphir-dmi` - Validate decoration values against schemas (depends on: morphir-3cr, morphir-zdb)

### Phase 2: IR Integration
- `morphir-msl` - Phase 2 feature (depends on: morphir-om0, morphir-86i, morphir-bxw)
- `morphir-86i` - Attach decorations to IR nodes
- `morphir-bxw` - Implement decoration queries and accessors (depends on: morphir-86i)

### Phase 3: CLI Commands
- `morphir-p6n` - Phase 3 feature (depends on: morphir-om0, morphir-msl, morphir-snf, morphir-hvp)
- `morphir-snf` - Implement morphir decoration-setup command (depends on: morphir-3cr)
- `morphir-hvp` - Implement morphir decoration-validate command (depends on: morphir-dmi)

### Phase 4: API Endpoints
- `morphir-p02` - Phase 4 feature (depends on: morphir-om0, morphir-msl, morphir-kes, morphir-9w5)
- `morphir-kes` - Create /server/attributes API endpoint (depends on: morphir-3cr, morphir-zdb)
- `morphir-9w5` - Implement decoration CRUD operations API (depends on: morphir-bxw, morphir-dmi)

### Phase 5: Test Fixtures and Examples
- `morphir-zzc` - Phase 5 feature (depends on: morphir-om0, morphir-msl, morphir-p6n, morphir-p02, morphir-ckf, morphir-nfo)
- `morphir-ckf` - Extract test fixtures from morphir-elm for decorations
- `morphir-nfo` - Create example decoration schemas and value files
