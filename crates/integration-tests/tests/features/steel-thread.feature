@steel-thread
Feature: Steel Thread - Migrate Command via Extension Architecture
  As a Morphir developer
  I want to validate the extension architecture end-to-end
  Using the migrate command as the steel thread

  Background:
    Given the morphir CLI is built and available
    And I have a temporary test directory

  # ========================================================================
  # Native Mode Tests (P0 - Steel Thread MVP)
  # ========================================================================

  @native @p0
  Scenario Outline: Migrate Classic IR fixtures to V4 format
    Given I have a Classic IR file from fixture "<fixture>"
    When I run "morphir migrate <fixture> --output output.json --target-version v4"
    Then the command should succeed
    And the file "output.json" should have V4 Library package "<package>"
    And the file "output.json" should have <modules> modules, <types> types, and <values> values
    And the stderr should contain "Migration complete"

    Examples:
      | fixture                   | package        | modules | types | values |
      | greeting-example.json     | elm-compat     | 2       | 8     | 7      |
      | rule-set-example.json     | morphir/sample | 1       | 3     | 2      |
      | direct-rules-example.json | morphir/sample | 1       | 6     | 2      |
      | lcr-morphir-ir.json       | regulation     | 84      | 103   | 635    |

  @native @p0 @wip
  Scenario Outline: Migrate V4 IR to Classic format (native mode)
    Given I have a V4 IR file from fixture "<fixture>"
    When I run "morphir migrate <fixture> output.json --target classic"
    Then the command should succeed
    And the file "output.json" should exist
    And the file "output.json" should be valid JSON
    And the file "output.json" should have Classic tuple format
    And the file "output.json" should contain '"formatVersion": 1'
    And the stderr should contain "Migration complete"

    Examples:
      | fixture                        |
      | v4-simple.json                 |
      | v4-with-modules.json           |
      | v4-with-types.json             |
      | v4-with-values.json            |
      | v4-empty-package.json          |

  @native @p0
  Scenario: Re-encode Classic IR as Classic IR
    Given I have a Classic IR file from fixture "greeting-example.json"
    When I run "morphir migrate greeting-example.json --output output.json --target-version v3"
    Then the command should succeed
    And the file "output.json" should have Classic Library package "elm-compat"
    And the stderr should contain "Migration complete"

  @native @p0
  Scenario: Re-encode V4 IR as V4 IR
    Given I have a V4 IR file from fixture "complete-example.json"
    When I run "morphir migrate complete-example.json --output output.json --target-version v4"
    Then the command should succeed
    And the file "output.json" should have V4 Library package "regulation"
    And the stderr should contain "Migration complete"

  @native @p0 @error-handling
  Scenario: Handle invalid target version
    Given I have a Classic IR file from fixture "greeting-example.json"
    When I run "morphir migrate greeting-example.json --output output.json --target-version invalid"
    Then the command should fail
    And the stderr should contain "morphir::ir::migration::invalid_target_version"

  @native @p0 @error-handling
  Scenario: Handle missing input file
    When I run "morphir migrate nonexistent.json --output output.json --target-version v4"
    Then the command should fail
    And the stderr should contain "morphir::ir::detection::read_failed"

  @native @p0 @error-handling
  Scenario: Handle malformed IR
    Given I have a file "invalid-ir.json" with:
      """
      { "this": "is not valid IR" }
      """
    When I run "morphir migrate invalid-ir.json --output output.json --target-version v4"
    Then the command should fail
    And the stderr should contain "morphir::ir::detection::missing_format_version"

  @native @p0
  Scenario: Migrate to stdout with JSON mode
    Given I have a Classic IR file from fixture "greeting-example.json"
    When I run "morphir migrate greeting-example.json --target-version v4 --json"
    Then the command should succeed
    And stdout should have V4 Library package "elm-compat"

  @native @p0
  Scenario: Migrate preserves Classic dependencies
    Given I have a Classic IR file with dependency "acme/shared"
    When I run "morphir migrate input.json --output output.json --target-version v4"
    Then the command should succeed
    And the file "output.json" should have V4 dependency "acme/shared"

  @native @p0
  Scenario: Migrate with expanded format option
    Given I have a Classic IR file from fixture "greeting-example.json"
    When I run "morphir migrate greeting-example.json --output output.json --target-version v4 --expanded"
    Then the command should succeed
    And the file "output.json" should have V4 Library package "elm-compat"
    And the file "output.json" should use expanded type references

  # ========================================================================
  # Remote Source Tests (P1)
  # ========================================================================

  @native @p1 @remote
  Scenario: Migrate from HTTP URL
    Given a local HTTP source serves the Classic IR greeting fixture
    When I migrate the HTTP fixture to "output.json"
    Then the command should succeed
    And the file "output.json" should have V4 Library package "elm-compat"
    And the HTTP source should have received 1 request

  @native @p1 @remote
  Scenario: Migrate with force refresh
    Given a local HTTP source serves the Classic IR greeting fixture
    When I migrate the HTTP fixture to "first.json"
    And I migrate the HTTP fixture to "cached.json"
    And I migrate the HTTP fixture to "output.json" with "--force-refresh"
    Then the command should succeed
    And the file "output.json" should have V4 Library package "elm-compat"
    And the HTTP source should have received 2 requests

  @native @p1 @remote
  Scenario: Migrate with no cache
    Given a local HTTP source serves the Classic IR greeting fixture
    When I migrate the HTTP fixture to "first.json"
    And I migrate the HTTP fixture to "cached.json"
    And I migrate the HTTP fixture to "output.json" with "--no-cache"
    Then the command should succeed
    And the file "output.json" should have V4 Library package "elm-compat"
    And the HTTP source should have received 2 requests

  # ========================================================================
  # WASM Mode Tests (P2 - Future)
  # ========================================================================

  @wasm @p2 @wip
  Scenario: Migrate Classic to V4 via WASM extension
    Given I have morphir-builtins compiled to WASM
    And I have a Classic IR file "morphir-ir.json"
    When I run "morphir migrate morphir-ir.json output.json --target v4 --mode wasm"
    Then the command should succeed
    And the file "output.json" should exist
    And the file "output.json" should match native mode output

  @wasm @p2 @wip
  Scenario: WASM mode produces identical results to native mode
    Given I have morphir-builtins compiled to WASM
    And I have a Classic IR file "morphir-ir.json"
    When I run "morphir migrate morphir-ir.json native-output.json --target v4"
    And I run "morphir migrate morphir-ir.json wasm-output.json --target v4 --mode wasm"
    Then both commands should succeed
    And the files "native-output.json" and "wasm-output.json" should be identical

  @wasm @p2 @wip @performance
  Scenario: Compare native vs WASM performance
    Given I have morphir-builtins compiled to WASM
    And I have a large Classic IR file "large-ir.json"
    When I measure time for "morphir migrate large-ir.json native.json --target v4"
    And I measure time for "morphir migrate large-ir.json wasm.json --target v4 --mode wasm"
    Then WASM mode should be within 50% of native mode performance
    # Note: WASM has overhead, but should be reasonable

  # ========================================================================
  # Envelope Protocol Validation (P0 - Architecture Proof)
  # ========================================================================

  @envelope @p0 @wip
  Scenario: Verify envelope protocol is used throughout
    Given I have debugging enabled for morphir-builtins
    And I have a Classic IR file "morphir-ir.json"
    When I run "morphir migrate morphir-ir.json output.json --target v4"
    Then the debug logs should show envelope creation
    And the debug logs should show envelope serialization
    And the debug logs should show envelope deserialization
    And the command should succeed

  @native @p0
  Scenario: JSON result reports migration metadata
    Given I have a Classic IR file from fixture "greeting-example.json"
    When I run "morphir migrate greeting-example.json --output output.json --target-version v4 --json"
    Then the command should succeed
    And stdout JSON should contain:
      | pointer  | expected JSON         |
      | /success | true                  |
      | /input   | "greeting-example.json" |
      | /output  | "output.json"         |
      | /source  | "v3/json/single-file" |
      | /target  | "v4/json/single-file" |
      | /error   | <absent>              |
    And the file "output.json" should have V4 Library package "elm-compat"

  # ========================================================================
  # Regression Tests (P1)
  # ========================================================================

  @regression @p1
  Scenario: Migrate preserves module structure
    Given I have a Classic IR file from fixture "greeting-example.json"
    When I run "morphir migrate greeting-example.json --output output.json --target-version v4"
    Then the command should succeed
    And the file "output.json" should contain exactly these V4 modules:
      | module |
      | api    |
      | main   |

  @regression @p1
  Scenario: Migrate preserves type definitions
    Given I have a Classic IR file from fixture "greeting-example.json"
    When I run "morphir migrate greeting-example.json --output output.json --target-version v4"
    Then the command should succeed
    And the file "output.json" should contain exactly these V4 types:
      | module | name           |
      | api    | api-error      |
      | api    | request        |
      | api    | response       |
      | main   | customer-order |
      | main   | order-status   |
      | main   | product        |
      | main   | product-id     |
      | main   | quantity       |

  @regression @p1
  Scenario: Migrate preserves value definitions
    Given I have a Classic IR file from fixture "greeting-example.json"
    When I run "morphir migrate greeting-example.json --output output.json --target-version v4"
    Then the command should succeed
    And the file "output.json" should contain exactly these V4 values:
      | module | name                   |
      | api    | create-order           |
      | api    | get-order-status       |
      | api    | process-request        |
      | main   | apply-discount         |
      | main   | calculate-total        |
      | main   | is-valid-order         |
      | main   | order-status-to-string |

  # ========================================================================
  # V4 Format Validation (Correctness Check)
  # ========================================================================

  @native @p0 @format-validation
  Scenario: V4 output uses correct wrapper object format
    Given I have a Classic IR file from fixture "greeting-example.json"
    When I run "morphir migrate greeting-example.json --output output.json --target-version v4"
    Then the command should succeed
    And the file "output.json" should use the canonical V4 Library wrapper

  @native @p0 @format-validation
  Scenario Outline: Verify V4 distribution variants use wrapper objects
    Given I have a minimal V4 <variant> IR document
    When I run "morphir migrate input.json --output output.json --target-version v4"
    Then the command should succeed
    And the file "output.json" should preserve the V4 <wrapper> wrapper

    Examples:
      | variant     | wrapper     |
      | Library     | Library     |
      | Specs       | Specs       |
      | Application | Application |

  # ========================================================================
  # JSONL Format Tests (P1 - Fast Follower)
  # ========================================================================

  @native @p1 @jsonl @fast-follower @wip
  Scenario Outline: Migrate to JSONL format
    Given I have a <format> IR file from fixture "<fixture>"
    When I run "morphir migrate <fixture> output.jsonl --target v4 --format jsonl"
    Then the command should succeed
    And the file "output.jsonl" should exist
    And each line in "output.jsonl" should be valid JSON
    And line 1 should contain package metadata
    And subsequent lines should contain module definitions

    Examples:
      | format  | fixture                     |
      | Classic | classic-simple.json         |
      | Classic | classic-with-modules.json   |
      | V4      | v4-simple.json              |
      | V4      | v4-with-modules.json        |

  @native @p1 @jsonl @fast-follower @wip
  Scenario: JSONL format enables directory tree reconstruction
    Given I have a Classic IR file "classic-with-modules.json"
    When I run "morphir migrate classic-with-modules.json output.jsonl --target v4 --format jsonl"
    Then the command should succeed
    And I can reconstruct directory tree from "output.jsonl"
    And each JSONL line maps to a file path
    # Note: Line 1 = package.json, Line N = modules/path/to/module.json

  @native @p1 @jsonl @fast-follower @wip
  Scenario: JSONL line structure validation
    Given I have a Classic IR file "classic-simple.json"
    When I run "morphir migrate classic-simple.json output.jsonl --target v4 --format jsonl"
    Then the command should succeed
    And line 1 should match JSONL package schema:
      | field         | type   | required |
      | packageName   | string | true     |
      | dependencies  | object | true     |
      | formatVersion | string | true     |
    And subsequent lines should match JSONL module schema:
      | field      | type   | required |
      | modulePath | string | true     |
      | types      | object | false    |
      | values     | object | false    |

  @native @p1 @jsonl @fast-follower @wip @roundtrip
  Scenario: JSONL roundtrip produces equivalent IR
    Given I have a Classic IR file "classic-with-modules.json"
    When I run "morphir migrate classic-with-modules.json v4-standard.json --target v4"
    And I run "morphir migrate classic-with-modules.json v4-jsonl.jsonl --target v4 --format jsonl"
    And I reconstruct "v4-reconstructed.json" from "v4-jsonl.jsonl"
    Then both commands should succeed
    And "v4-standard.json" and "v4-reconstructed.json" should be semantically equivalent
