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
  Scenario Outline: Migrate Classic IR to V4 format (native mode)
    Given I have a Classic IR file from fixture "<fixture>"
    When I run "morphir migrate <fixture> output.json --target v4"
    Then the command should succeed
    And the file "output.json" should exist
    And the file "output.json" should be valid JSON
    And the file "output.json" should have V4 wrapper format
    And the file "output.json" should contain package "<package>"
    And the stderr should contain "Migration complete"

    Examples:
      | fixture                          | package           |
      | classic-simple.json              | com.example.test  |
      | classic-with-modules.json        | com.example.multi |
      | classic-with-types.json          | com.example.types |
      | classic-with-values.json         | com.example.funcs |
      | classic-empty-package.json       | com.example.empty |

  @native @p0
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
  Scenario: Migrate same format (Classic to Classic) is a no-op
    Given I have a Classic IR file "morphir-ir.json"
    When I run "morphir migrate morphir-ir.json output.json --target classic"
    Then the command should succeed
    And the file "output.json" should exist
    And the stderr should contain "Copying"

  @native @p0
  Scenario: Migrate same format (V4 to V4) is a no-op
    Given I have a V4 IR file "morphir-ir.json"
    When I run "morphir migrate morphir-ir.json output.json --target v4"
    Then the command should succeed
    And the file "output.json" should exist
    And the stderr should contain "Copying"

  @native @p0 @error-handling
  Scenario: Handle invalid target version
    Given I have a Classic IR file "morphir-ir.json"
    When I run "morphir migrate morphir-ir.json output.json --target invalid"
    Then the command should fail
    And the stderr should contain "Invalid target version"

  @native @p0 @error-handling
  Scenario: Handle missing input file
    When I run "morphir migrate nonexistent.json output.json --target v4"
    Then the command should fail
    And the stderr should contain "Failed to load input"

  @native @p0 @error-handling
  Scenario: Handle malformed IR
    Given I have a file "invalid-ir.json" with:
      """
      { "this": "is not valid IR" }
      """
    When I run "morphir migrate invalid-ir.json output.json --target v4"
    Then the command should fail
    And the stderr should contain "Failed to load input"

  @native @p0
  Scenario: Migrate to stdout with JSON mode
    Given I have a Classic IR file "morphir-ir.json"
    When I run "morphir migrate morphir-ir.json --target v4 --json"
    Then the command should succeed
    And stdout should contain valid JSON
    And stdout should contain "formatVersion"

  @native @p0
  Scenario: Migrate with dependency warning (Classic to V4)
    Given I have a Classic IR file "morphir-ir.json" with:
      """
      {
        "formatVersion": 1,
        "distribution": [
          "Library",
          "Library",
          ["com", "example", "test"],
          [
            {
              "packageName": ["com", "example", "dependency"],
              "packagePath": "/some/path"
            }
          ],
          {
            "modules": {}
          }
        ]
      }
      """
    When I run "morphir migrate morphir-ir.json output.json --target v4"
    Then the command should succeed
    And the stderr should contain "Warning"
    And the stderr should contain "dependencies"

  @native @p0
  Scenario: Migrate with expanded format option
    Given I have a Classic IR file "morphir-ir.json"
    When I run "morphir migrate morphir-ir.json output.json --target v4 --expanded"
    Then the command should succeed
    And the file "output.json" should exist
    # Note: Expanded format means non-compact JSON (more readable, more bytes)

  # ========================================================================
  # Remote Source Tests (P1)
  # ========================================================================

  @native @p1 @remote
  Scenario: Migrate from HTTP URL
    Given I have internet connectivity
    When I run "morphir migrate https://example.com/morphir-ir.json output.json --target v4"
    Then the command should succeed or fail gracefully
    # Note: May fail if URL not available, that's ok for test

  @native @p1 @remote
  Scenario: Migrate with force refresh
    Given I have a cached remote IR
    When I run "morphir migrate https://example.com/morphir-ir.json output.json --target v4 --force-refresh"
    Then the command should succeed or fail gracefully

  @native @p1 @remote
  Scenario: Migrate with no cache
    When I run "morphir migrate https://example.com/morphir-ir.json output.json --target v4 --no-cache"
    Then the command should succeed or fail gracefully

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

  @envelope @p0
  Scenario: Verify envelope protocol is used throughout
    Given I have debugging enabled for morphir-builtins
    And I have a Classic IR file "morphir-ir.json"
    When I run "morphir migrate morphir-ir.json output.json --target v4"
    Then the debug logs should show envelope creation
    And the debug logs should show envelope serialization
    And the debug logs should show envelope deserialization
    And the command should succeed

  @envelope @p0
  Scenario: Envelope contains proper metadata
    Given I have JSON output mode enabled
    And I have a Classic IR file "morphir-ir.json"
    When I run "morphir migrate morphir-ir.json output.json --target v4 --json"
    Then the JSON output should contain:
      | field          | type    |
      | success        | boolean |
      | source_format  | string  |
      | target_format  | string  |
      | warnings       | array   |

  # ========================================================================
  # Regression Tests (P1)
  # ========================================================================

  @regression @p1
  Scenario: Migrate preserves module structure
    Given I have a Classic IR with multiple modules
    When I run "morphir migrate morphir-ir.json output.json --target v4"
    Then the command should succeed
    And all modules should be present in output

  @regression @p1
  Scenario: Migrate preserves type definitions
    Given I have a Classic IR with type definitions
    When I run "morphir migrate morphir-ir.json output.json --target v4"
    Then the command should succeed
    And all type definitions should be present in output

  @regression @p1
  Scenario: Migrate preserves value definitions
    Given I have a Classic IR with value definitions
    When I run "morphir migrate morphir-ir.json output.json --target v4"
    Then the command should succeed
    And all value definitions should be present in output

  # ========================================================================
  # V4 Format Validation (Correctness Check)
  # ========================================================================

  @native @p0 @format-validation
  Scenario: V4 output uses correct wrapper object format
    Given I have a Classic IR file "classic-simple.json" with:
      """
      {
        "formatVersion": 1,
        "distribution": [
          "Library",
          "Library",
          ["com", "example", "test"],
          [],
          {
            "modules": {
              "Main": {
                "types": {},
                "values": {}
              }
            }
          }
        ]
      }
      """
    When I run "morphir migrate classic-simple.json output.json --target v4"
    Then the command should succeed
    And the file "output.json" should contain:
      """
      {
        "formatVersion": "4.0.0",
        "distribution": {
          "Library": {
            "packageName": "com/example/test",
            "dependencies": {},
            "def": {
              "modules": {
                "main": {
                  "types": {},
                  "values": {}
                }
              }
            }
          }
        }
      }
      """
    # Note: V4 canonical format uses:
    # - Wrapper objects: {"Library": {...}} not tuple arrays ["Library", ...]
    # - Canonical strings: "com/example/test" not ["com", "example", "test"]
    # - Kebab-case names: "main" not "Main" for module names

  @native @p0 @format-validation
  Scenario Outline: Verify V4 distribution variants use wrapper objects
    Given I have a V4 IR file with <variant> distribution
    When I parse the JSON structure
    Then the "distribution" field should be an object
    And the "distribution" object should have key "<wrapper>"
    And the "<wrapper>" value should be an object (not an array)

    Examples:
      | variant     | wrapper      |
      | Library     | Library      |
      | Specs       | Specs        |
      | Application | Application  |

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
