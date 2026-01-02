@distribution @smoke
Feature: Decode Library Distribution
  As a morphir-go user
  I want to decode morphir-elm generated IR
  So that I can process Morphir packages in Go

  @v3
  Scenario: Decode V3 format simple library
    Given I have the fixture "v3/simple-library.json"
    When I decode as distribution format version 3
    Then the decoding should succeed
    And the distribution type should be "Library"

  @v1 @legacy
  Scenario: Decode V1 format legacy library
    Given I have the fixture "v1/simple-library.json"
    When I decode as distribution format version 1
    Then the decoding should succeed
    And the distribution type should be "Library"
