@type
Feature: Decode Type IR
  As a morphir-go user
  I want to decode various type IR structures
  So that I can work with Morphir type definitions

  @v3 @smoke
  Scenario: Decode V3 Unit type
    Given I have the fixture "v3/type-unit.json"
    When I decode as type format version 3
    Then the decoding should succeed
    And the type should be a "Unit"

  @v3
  Scenario: Decode V3 Variable type
    Given I have the fixture "v3/type-variable.json"
    When I decode as type format version 3
    Then the decoding should succeed
    And the type should be a "Variable"

  @v3
  Scenario: Decode V3 Record type
    Given I have the fixture "v3/type-record.json"
    When I decode as type format version 3
    Then the decoding should succeed
    And the type should be a "Record"

  @v1 @legacy
  Scenario: Decode V1 Unit type
    Given I have the fixture "v1/type-unit.json"
    When I decode as type format version 1
    Then the decoding should succeed
    And the type should be a "Unit"

  @v1 @legacy
  Scenario: Decode V1 Variable type
    Given I have the fixture "v1/type-variable.json"
    When I decode as type format version 1
    Then the decoding should succeed
    And the type should be a "Variable"
