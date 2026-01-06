@wit @traversal
Feature: WIT Type Traversal
  Functional utilities for traversing and transforming WIT type trees,
  including WalkType, MapType, FoldType, and helper functions.

  Background:
    Given the following type definitions:
      | name     | structure                              |
      | simple   | u32                                    |
      | nested   | list<option<string>>                   |
      | deep     | result<list<u8>, option<error-code>>   |
      | tuple    | tuple<u32, string, bool>               |

  Rule: WalkType traverses all types in a tree

    Scenario Outline: Count types in type tree
      Given the type "<type_name>"
      When I walk the type tree
      Then I should visit <count> types

      Examples:
        | type_name | count |
        | simple    | 1     |
        | nested    | 3     |
        | deep      | 5     |
        | tuple     | 4     |

    Scenario Outline: Collect specific type kinds
      Given the type "<type_name>"
      When I collect all types of kind "<kind>"
      Then I should find <count> types

      Examples:
        | type_name | kind      | count |
        | simple    | primitive | 1     |
        | simple    | container | 0     |
        | nested    | list      | 1     |
        | nested    | option    | 1     |
        | nested    | primitive | 1     |
        | deep      | result    | 1     |
        | deep      | list      | 1     |
        | deep      | option    | 1     |
        | tuple     | tuple     | 1     |
        | tuple     | primitive | 3     |

  Rule: MapType transforms type trees

    Scenario Outline: Replace primitive types
      Given the type "<input_type>"
      When I map all "string" primitives to "u64" primitives
      Then the resulting type should be "<output_type>"

      Examples:
        | input_type              | output_type             |
        | string                  | u64                     |
        | list<string>            | list<u64>               |
        | option<string>          | option<u64>             |
        | result<string, u32>     | result<u64, u32>        |
        | tuple<string, u32>      | tuple<u64, u32>         |
        | tuple<string, string>   | tuple<u64, u64>         |

    Scenario: Wrap types in option
      Given the type "u32"
      When I map each type to wrap it in option
      Then the resulting type should be "option<option<u32>>"

  Rule: FoldType accumulates results

    Scenario Outline: Calculate type depth
      Given the type "<type_expr>"
      When I calculate the type depth
      Then the depth should be <depth>

      Examples:
        | type_expr                         | depth |
        | u32                               | 1     |
        | list<u8>                          | 2     |
        | option<string>                    | 2     |
        | list<option<string>>              | 3     |
        | result<list<u8>, option<u32>>     | 3     |
        | list<list<list<u8>>>              | 4     |
        | tuple<u32, list<option<string>>>  | 4     |

    Scenario Outline: Count total type nodes
      Given the type "<type_expr>"
      When I fold to count all type nodes
      Then the total count should be <count>

      Examples:
        | type_expr                         | count |
        | u32                               | 1     |
        | list<u8>                          | 2     |
        | list<option<string>>              | 3     |
        | result<string, u32>               | 3     |
        | tuple<u32, string, bool>          | 4     |
        | list<result<string, option<u32>>> | 5     |

  Rule: Helper functions for type analysis

    Scenario Outline: ContainsType predicate
      Given the type "<type_expr>"
      When I check if it contains a "<target_kind>" type
      Then the result should be <contains>

      Examples:
        | type_expr                      | target_kind | contains |
        | u32                            | primitive   | true     |
        | u32                            | list        | false    |
        | list<u8>                       | list        | true     |
        | list<u8>                       | option      | false    |
        | option<list<string>>           | list        | true     |
        | option<list<string>>           | option      | true     |
        | result<string, option<u32>>    | option      | true     |
        | tuple<u32, u64, bool>          | primitive   | true     |
        | tuple<u32, list<u8>>           | list        | true     |

  Rule: Visitor pattern support

    Scenario: Custom visitor collects statistics
      Given the type "result<list<u8>, option<error-code>>"
      And a statistics visitor
      When I accept the visitor
      Then the visitor should report:
        | metric              | count |
        | primitive_types     | 2     |
        | container_types     | 3     |
        | list_types          | 1     |
        | option_types        | 1     |
        | result_types        | 1     |
        | named_types         | 1     |

    Scenario: Visitor with early termination
      Given the type "list<option<string>>"
      And a visitor that stops at option types
      When I accept the visitor
      Then the visitor should have visited:
        | type_kind |
        | list      |
        | option    |
      And should not have visited "string"
