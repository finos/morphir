@ir @v4 @compliance
Feature: IR V4 Schema Compliance
  As a Morphir IR consumer
  I want to decode and validate V4 format IR
  So that I can process IR with V4-specific constructs

  Background:
    Given the V4 schema specification from morphir.finos.org

  # ============================================================
  # HoleReason Variants
  # ============================================================

  @hole-reason @unresolved-reference
  Scenario: Decode HoleReason with UnresolvedReference
    Given I have the V4 fixture "ir/v4/hole-reason-examples.json"
    When I extract the "unresolvedReference" example
    Then the HoleReason should have variant "UnresolvedReference"
    And it should have a "target" field with an FQName value
    And the target should be "my-org/my-package:domain/users#get-user"

  @hole-reason @deleted-during-refactor
  Scenario: Decode HoleReason with DeletedDuringRefactor
    Given I have the V4 fixture "ir/v4/hole-reason-examples.json"
    When I extract the "deletedDuringRefactor" example
    Then the HoleReason should have variant "DeletedDuringRefactor"
    And it should have a "tx-id" field
    And the tx-id should be "refactor-2026-01-30-001"

  @hole-reason @type-mismatch
  Scenario: Decode HoleReason with TypeMismatch
    Given I have the V4 fixture "ir/v4/hole-reason-examples.json"
    When I extract the "typeMismatch" example
    Then the HoleReason should have variant "TypeMismatch"
    And it should have an "expected" field
    And it should have a "found" field
    And the expected type should be "morphir/sdk:basics#int"
    And the found type should be "morphir/sdk:string#string"

  @hole-reason @backward-compatibility
  Scenario Outline: Accept legacy string format HoleReason
    Given I have a legacy string HoleReason "<string_value>"
    When I decode as HoleReason
    Then the decoding should succeed
    And the variant should be "<variant>"
    And missing fields should use default values

    Examples:
      | string_value          | variant               |
      | DeletedDuringRefactor | DeletedDuringRefactor |
      | TypeMismatch          | TypeMismatch          |

  # ============================================================
  # Incompleteness
  # ============================================================

  @incompleteness @hole
  Scenario: Decode Incompleteness Hole variant
    Given I have the V4 fixture "ir/v4/incompleteness-examples.json"
    When I extract the "holeWithUnresolvedReference" example
    Then the Incompleteness should have variant "Hole"
    And it should contain a "reason" field
    And the reason should be a HoleReason with variant "UnresolvedReference"

  @incompleteness @draft
  Scenario: Decode Incompleteness Draft variant
    Given I have the V4 fixture "ir/v4/incompleteness-examples.json"
    When I extract the "draft" example
    Then the Incompleteness should have variant "Draft"
    And it should serialize as {"Draft": {}}

  # ============================================================
  # NativeHint
  # ============================================================

  @native-hint @simple
  Scenario Outline: Decode simple NativeHint variants
    Given I have the V4 fixture "ir/v4/native-hint-examples.json"
    When I extract the "<example>" example
    Then the NativeHint should have variant "<variant>"

    Examples:
      | example      | variant      |
      | arithmetic   | Arithmetic   |
      | comparison   | Comparison   |
      | stringOp     | StringOp     |
      | collectionOp | CollectionOp |

  @native-hint @platform-specific
  Scenario: Decode NativeHint PlatformSpecific with platform field
    Given I have the V4 fixture "ir/v4/native-hint-examples.json"
    When I extract the "platformSpecificWasm" example
    Then the NativeHint should have variant "PlatformSpecific"
    And it should have a "platform" field
    And the platform should be "wasm"

  @native-hint @backward-compatibility
  Scenario: Accept legacy string format PlatformSpecific
    Given I have a legacy string NativeHint "PlatformSpecific"
    When I decode as NativeHint
    Then the decoding should succeed
    And the variant should be "PlatformSpecific"
    And the platform field should default to "unknown"

  # ============================================================
  # IncompleteTypeDefinition
  # ============================================================

  @incomplete-type @hole
  Scenario: Decode IncompleteTypeDefinition with Hole incompleteness
    Given I have the V4 fixture "ir/v4/incomplete-type-definition-example.json"
    When I extract the "holeWithUnresolvedReference" example
    Then the TypeDefinition should have variant "IncompleteTypeDefinition"
    And it should have "typeParams" as ["a"]
    And it should have an "incompleteness" field with variant "Hole"
    And it should have a null "partialTypeExp"

  @incomplete-type @draft
  Scenario: Decode IncompleteTypeDefinition with Draft and partial body
    Given I have the V4 fixture "ir/v4/incomplete-type-definition-example.json"
    When I extract the "draftWithPartialBody" example
    Then the TypeDefinition should have variant "IncompleteTypeDefinition"
    And it should have empty "typeParams"
    And it should have an "incompleteness" field with variant "Draft"
    And it should have a non-null "partialTypeExp" with Record type

  # ============================================================
  # Complete V4 Distribution
  # ============================================================

  @distribution @v4-format
  Scenario: Decode complete V4 format distribution
    Given I have the V4 fixture "ir/v4/v4-library-distribution.json"
    When I decode as distribution format version 4
    Then the decoding should succeed
    And the distribution type should be "Library"
    And the package name should be "example/v4-test"
    And the modules should include "domain"

  @distribution @incomplete-types
  Scenario: V4 distribution with IncompleteTypeDefinition
    Given I have the V4 fixture "ir/v4/v4-library-distribution.json"
    When I decode as distribution format version 4
    And I navigate to module "domain"
    Then the types should include "incomplete-user"
    And "incomplete-user" should be an IncompleteTypeDefinition

  @distribution @hole-values
  Scenario: V4 distribution with Hole value expression
    Given I have the V4 fixture "ir/v4/v4-library-distribution.json"
    When I decode as distribution format version 4
    And I navigate to module "domain"
    Then the values should include "get-user-name"
    And "get-user-name" body should be a Hole expression

  @distribution @native-body
  Scenario: V4 distribution with NativeBody value definition
    Given I have the V4 fixture "ir/v4/v4-library-distribution.json"
    When I decode as distribution format version 4
    And I navigate to module "domain"
    Then the values should include "native-add"
    And "native-add" should have a nativeBody
    And the nativeBody hint should be "Arithmetic"

  # ============================================================
  # Round-trip Serialization
  # ============================================================

  @round-trip @hole-reason
  Scenario: Round-trip HoleReason serialization
    Given I have a HoleReason with variant "UnresolvedReference"
    And target "test/pkg:mod#func"
    When I serialize to JSON
    And I deserialize back to HoleReason
    Then the result should equal the original

  @round-trip @incompleteness
  Scenario: Round-trip Incompleteness serialization
    Given I have an Incompleteness with variant "Hole"
    And reason with variant "TypeMismatch"
    When I serialize to JSON
    And I deserialize back to Incompleteness
    Then the result should equal the original

  @round-trip @native-hint
  Scenario: Round-trip NativeHint PlatformSpecific serialization
    Given I have a NativeHint "PlatformSpecific" with platform "javascript"
    When I serialize to JSON
    And I deserialize back to NativeHint
    Then the result should equal the original
    And the platform should be "javascript"

  # ============================================================
  # IntegerLiteral (V4 literal change)
  # ============================================================

  @literal @integer
  Scenario: Decode V4 IntegerLiteral format
    Given I have a V4 literal {"IntegerLiteral": 42}
    When I decode as Literal
    Then the Literal should have variant "IntegerLiteral"
    And the value should be 42

  @literal @integer @negative
  Scenario: Decode negative IntegerLiteral
    Given I have a V4 literal {"IntegerLiteral": -100}
    When I decode as Literal
    Then the Literal should have variant "IntegerLiteral"
    And the value should be -100

  @literal @backward-compatibility
  Scenario: Accept legacy WholeNumberLiteral in V4 decoder
    Given I have a V4 literal {"WholeNumberLiteral": 99}
    When I decode as Literal with V4 decoder
    Then the decoding should succeed
    And the value should be 99
