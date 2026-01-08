@wit @domain
Feature: WIT Domain Model
  The WIT domain model provides a strongly-typed representation of
  WebAssembly Interface Types, avoiding primitive obsession and making
  invalid states unrepresentable through discriminated unions.

  Rule: Strong typing prevents invalid identifiers

    Scenario Outline: Identifier validation
      Given an identifier "<input>"
      When I attempt to create an Identifier
      Then the result should be "<expected>"
      And if successful the Identifier string value should be "<output>"

      Examples: Valid kebab-case identifiers
        | input          | expected | output         |
        | my-function    | success  | my-function    |
        | get-time       | success  | get-time       |
        | wall-clock     | success  | wall-clock     |
        | http-types     | success  | http-types     |
        | a              | success  | a              |
        | a-b-c-d-e      | success  | a-b-c-d-e      |
        | item123        | success  | item123        |
        | test-123-foo   | success  | test-123-foo   |
        | %special-case  | success  | %special-case  |

      Examples: Invalid identifiers
        | input          | expected | output |
        |                | error    |        |
        | MyFunction     | error    |        |
        | my_function    | error    |        |
        | my function    | error    |        |
        | 123-start      | error    |        |
        | -leading-dash  | error    |        |
        | trailing-dash- | error    |        |
        | UPPERCASE      | error    |        |
        | camelCase      | error    |        |

  Rule: Package identification with namespace and version

    Scenario Outline: Package identifier format
      Given a package with namespace "<namespace>", name "<name>", and version "<version>"
      When I create a Package
      Then the Package ident should be "<ident>"

      Examples:
        | namespace | name        | version | ident                        |
        | wasi      | clocks      | 0.2.0   | wasi:clocks@0.2.0            |
        | wasi      | http        | 1.0.0   | wasi:http@1.0.0              |
        | my-org    | my-package  |         | my-org:my-package            |
        | test      | simple      |         | test:simple                  |
        | foo       | bar         | 2.1.3   | foo:bar@2.1.3                |

  Rule: Use paths distinguish local and external references

    Scenario Outline: Use path construction
      Given a use path with namespace "<namespace>", package "<package>", interface "<interface>", and version "<version>"
      When I create a UsePath
      Then it should be of type "<path_type>"
      And it should reference the correct components

      Examples: Local references
        | namespace | package | interface  | version | path_type |
        |           |         | wall-clock |         | local     |
        |           |         | logger     |         | local     |
        |           |         | my-types   |         | local     |

      Examples: External references with versions
        | namespace | package | interface | version | path_type |
        | wasi      | http    | types     | 1.0.0   | external  |
        | wasi      | clocks  | monotonic | 0.2.0   | external  |
        | my-org    | utils   | helpers   | 2.1.0   | external  |

      Examples: External references without versions
        | namespace | package    | interface   | version | path_type |
        | wasi      | filesystem | types       |         | external  |
        | test      | mock       | interfaces  |         | external  |

      Examples: Package-level external references
        | namespace | package | interface | version | path_type |
        | wasi      | io      |           | 0.2.0   | external  |
        | my-org    | common  |           |         | external  |

  Rule: Type system primitives

    Scenario Outline: Primitive type creation
      Given a primitive kind "<kind>"
      When I create a PrimitiveType
      Then it should be a valid Type
      And it should not be a ContainerType
      And its kind should be "<kind>"

      Examples:
        | kind   |
        | u8     |
        | u16    |
        | u32    |
        | u64    |
        | s8     |
        | s16    |
        | s32    |
        | s64    |
        | f32    |
        | f64    |
        | bool   |
        | char   |
        | string |

  Rule: Container types hold other types

    Scenario Outline: Container type construction
      Given a <container_type> containing "<element_types>"
      When I create the container Type
      Then it should be a valid Type
      And it should be a ContainerType
      And it should contain the specified element types

      Examples:
        | container_type | element_types      |
        | list           | u8                 |
        | list           | string             |
        | list           | my-record          |
        | option         | string             |
        | option         | u64                |
        | option         | my-custom-type     |

    Scenario Outline: Result type variants
      Given a result with ok type "<ok>" and err type "<err>"
      When I create a ResultType
      Then it should be a valid Type
      And it should be a ContainerType
      And its ok type should be "<ok>"
      And its err type should be "<err>"

      Examples:
        | ok     | err        |
        | string | u32        |
        | u64    | error-code |
        | data   | io-error   |
        |        | u32        |
        | string |            |
        |        |            |

    Scenario Outline: Tuple type with multiple elements
      Given a tuple with types "<types>"
      When I create a TupleType
      Then it should be a valid Type
      And it should be a ContainerType
      And it should have <count> element types

      Examples:
        | types              | count |
        | u32,string         | 2     |
        | s32,s32            | 2     |
        | u32,u32,string     | 3     |
        | bool,string,u64,f32| 4     |

  Rule: Type definitions support multiple kinds

    Scenario Outline: TypeDef kind validation
      Given a TypeDef named "<name>" of kind "<kind>"
      When I create the TypeDef
      Then it should have name "<name>"
      And it should have kind "<kind>"

      Examples:
        | name        | kind     |
        | point       | record   |
        | result      | variant  |
        | color       | enum     |
        | permissions | flags    |
        | file        | resource |
        | my-size     | alias    |
