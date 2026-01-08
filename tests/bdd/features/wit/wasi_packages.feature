@wit @wasi @integration
Feature: WASI Package Parsing
  Parse and validate real WASI packages to ensure the domain model
  correctly represents actual WIT specifications used in production.

  Rule: WASI clocks package

    Scenario: Parse wasi:clocks/wall-clock interface
      Given the WASI package "wasi:clocks@0.2.0"
      When I parse the package
      Then it should contain an interface "wall-clock"
      And the interface should have the following types:
        | name     | kind   |
        | datetime | record |
      And the interface should have the following functions:
        | name       | params | returns  |
        | now        |        | datetime |
        | resolution |        | datetime |

    Scenario: Parse wasi:clocks/monotonic-clock interface
      Given the WASI package "wasi:clocks@0.2.0"
      When I parse the package
      Then it should contain an interface "monotonic-clock"
      And the interface should have the following type aliases:
        | name     | target |
        | instant  | u64    |
        | duration | u64    |

  Rule: WASI HTTP package

    Scenario: Parse wasi:http/types interface
      Given the WASI package "wasi:http/types@0.2.0"
      When I parse the package
      Then it should contain an interface "types"
      And the interface should have resources
      And the interface should have enums
      And the interface should have records
      And the interface should have variants

    Scenario Outline: Verify HTTP types structure
      Given the WASI package "wasi:http/types@0.2.0"
      When I parse the interface "types"
      Then it should have a type "<type_name>" of kind "<kind>"

      Examples:
        | type_name | kind     |
        | method    | variant  |
        | scheme    | variant  |
        | fields    | resource |
        | request   | resource |
        | response  | resource |

  Rule: WASI filesystem package

    Scenario: Parse wasi:filesystem/types interface
      Given the WASI package "wasi:filesystem/types@0.2.0"
      When I parse the package
      Then it should contain an interface "types"
      And the interface should define resources for file operations

    Scenario Outline: Verify filesystem error handling
      Given the WASI package "wasi:filesystem/types@0.2.0"
      When I parse the interface "types"
      Then functions should use result types with error variants
      And the error type "<error_type>" should exist

      Examples:
        | error_type    |
        | error-code    |
        | errno         |

  Rule: Package metadata validation

    Scenario Outline: Verify WASI package metadata
      Given the WASI package "<package_id>"
      When I parse the package
      Then the package namespace should be "wasi"
      And the package name should be "<name>"
      And the package version should be "<version>"

      Examples:
        | package_id                   | name       | version |
        | wasi:clocks@0.2.0            | clocks     | 0.2.0   |
        | wasi:http@0.2.0              | http       | 0.2.0   |
        | wasi:filesystem@0.2.0        | filesystem | 0.2.0   |
        | wasi:sockets@0.2.0           | sockets    | 0.2.0   |
        | wasi:random@0.2.0            | random     | 0.2.0   |

  Rule: Interface discovery and navigation

    Scenario Outline: Count interfaces in WASI packages
      Given the WASI package "<package_id>"
      When I parse the package
      Then it should have at least <min_interfaces> interfaces

      Examples:
        | package_id            | min_interfaces |
        | wasi:clocks@0.2.0     | 2              |
        | wasi:http@0.2.0       | 1              |
        | wasi:filesystem@0.2.0 | 1              |

  Rule: World definitions

    Scenario: Parse WASI world with imports
      Given a WASI world definition
      When I parse the world
      Then it should have imports
      And imports should reference WASI interfaces

    Scenario: Verify world import/export structure
      Given a world with mixed imports and exports
      When I parse the world
      Then each import should be either an interface or function
      And each export should be either an interface or function
      And interface imports should have valid use paths
