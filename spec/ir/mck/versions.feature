Feature: Versions

  @node:Value @version:3
  Scenario: versions-0001 Reading a v3 literal into the model
    A v3 tagged array with capitalized tags decodes to the same value the v4 spelling does.

    Then its canonical JSON spelling is ["Literal", {}, ["WholeNumberLiteral", 42]]

  @node:Value @version:3 @pending
  Scenario: versions-0002 Writing a Hole to v3 is refused
    The CLI refuses a v4 to v3 downgrade with `unsupported_v4_downgrade`. The kit grammar has no role for a write refusal yet; bead morphir-diwy specifies the rules for adding one. Until then this case is prose only.

  @node:FormatVersion
  Scenario: versions-0003 One YAML document
    The YAML profile admits exactly one document. A second document after `---`, or content after `...`, is refused rather than silently reading the first. YAML profile page, "Reader restrictions".

    Then its canonical YAML spelling is 4
    And a reader of YAML rejects with invalid_yaml:
      """yaml
      4
      ---
      4
      """

  @node:Distribution
  Scenario: versions-0004 No anchors, tags, merge keys or directives
    Anchors, aliases, explicit tags, merge keys, and directives are presentation and schema machinery the profile does not carry: an IR document means the same thing wherever it is read, so nothing in it may be resolved against something else. Each is refused with `unsupported_yaml_feature`. YAML profile page, "Reader restrictions".

    Then its canonical YAML spelling is:
      """yaml
      formatVersion: 4
      distribution:
        Library:
          packageName: example
          dependencies: {}
          def:
            modules: {}
      """
    And its canonical JSON spelling is { "formatVersion": 4, "distribution": { "Library": { "packageName": "example", "dependencies": {}, "def": { "modules": {} } } } }
    And a reader of YAML rejects with unsupported_yaml_feature:
      """yaml
      formatVersion: 4
      distribution:
        Library:
          packageName: example
          dependencies: &empty {}
          def:
            modules: *empty
      """
    And a reader of YAML rejects with unsupported_yaml_feature:
      """yaml
      formatVersion: 4
      distribution:
        Library:
          packageName: example
          dependencies: !!map {}
          def:
            modules: {}
      """
    And a reader of YAML rejects with unsupported_yaml_feature:
      """yaml
      formatVersion: 4
      distribution:
        Library:
          packageName: example
          dependencies: {}
          def:
            <<: {}
            modules: {}
      """
    And a reader of YAML rejects with unsupported_yaml_feature:
      """yaml
      %YAML 1.2
      ---
      formatVersion: 4
      distribution:
        Library:
          packageName: example
          dependencies: {}
          def:
            modules: {}
      """

  @node:Distribution
  Scenario: versions-0005 Duplicate keys
    A repeated mapping key is refused with `duplicate_member`, the same diagnostic the JSON profile reports for a repeated object member: last-one-wins would make the same bytes mean different things in different readers. YAML profile page, "Reader restrictions".

    These are read and written at version 3 by any binding that declares version 3 (the Rust binding does; the reference declares only 4 and skips them). They pin the classic mirror against morphir-elm's codecs.

    Then its canonical YAML spelling is:
      """yaml
      formatVersion: 4
      distribution:
        Library:
          packageName: example
          dependencies: {}
          def:
            modules: {}
      """
    And its canonical JSON spelling is { "formatVersion": 4, "distribution": { "Library": { "packageName": "example", "dependencies": {}, "def": { "modules": {} } } } }
    And a reader of YAML rejects with duplicate_member:
      """yaml
      formatVersion: 4
      formatVersion: 4
      distribution:
        Library:
          packageName: example
          dependencies: {}
          def:
            modules: {}
      """

  @node:Literal @version:3
  Scenario: versions-0006 A v3 decimal literal keeps its text
    morphir-elm encodes `DecimalLiteral` as a string (`Decimal.toString`); a binding that reads it through a float and writes `10.5` fails this case.

    Then its canonical JSON spelling is ["DecimalLiteral", "10.50"]

  @node:TypeSpecification @version:3
  Scenario: versions-0007 A v3 derived type specification
    morphir-elm's fourth specification: `["DerivedTypeSpecification", params, { "baseType", "fromBaseType", "toBaseType" }]`, with the base type a v3 type and the two conversions v3 FQNames.

    Then its canonical JSON spelling is ["DerivedTypeSpecification", [], { "baseType": ["Reference", {}, [[["morphir"], ["s", "d", "k"]], [["string"]], ["string"]], []], "fromBaseType": [[["my"], ["org"]], [["module"]], ["from", "string"]], "toBaseType": [[["my"], ["org"]], [["module"]], ["to", "string"]] }]

  @node:Type @version:3
  Scenario: versions-0008 v3 record fields are objects
    morphir-elm writes a record field as `{ "name", "tpe" }`, never as a pair.

    Then its canonical JSON spelling is ["Record", {}, [{ "name": ["first"], "tpe": ["Reference", {}, [[["morphir"], ["s", "d", "k"]], [["string"]], ["string"]], []] }]]

  @node:FormatVersion @version:3
  Scenario: versions-0009 3.1.0 is supported
    IR 3.1.0 introduced the v3 `Specs` distribution (distributions-0006's classic counterpart) and the v3 document tree. Its baseline does not collapse to the bare integer `3`, the way distributions-0008 pins a later patch of a supported minor.

    Then its canonical JSON spelling is "3.1.0"

  @node:FormatVersion @version:3
  Scenario: versions-0010 3.2.0 is a later minor
    Governed by `docs/spec/ir/format-version.md`. The reader's support table names `[3.0.0,3.2.0)`, so `3.2.0` itself is refused the same way distributions-0001 refuses a v4 minor past its own table.

    Then a reader of JSON rejects "3.2.0" with unsupported_format_version_minor

  @node:Name @version:3 @spelling
  Scenario: versions-0011 A v3 name is an array of lowercase words
    morphir-elm writes a name as the list of its words, each in lowercase, and every capital of an acronym is a word of its own: `valueInUSD` is five words. The v4 single-string spelling (names.feature) is not a v3 name.

    Then its canonical JSON spelling is ["value", "in", "u", "s", "d"]

  @node:Name @version:3 @semantic
  Scenario: versions-0012 A v3 name is never a string
    A v3 payload that does not decode as the classic JSON of its kind is refused with `invalid_type`, the diagnostic the v3 document-tree validation rules give for the same fault (`docs/spec/ir/schemas/v3/document-tree-files.md`). A camel-case string is the commonest such name.

    Then a reader of JSON rejects "valueInUSD" with invalid_type

  @node:Path @version:3 @spelling
  Scenario: versions-0013 A v3 path is an array of names
    `Morphir.SDK` is two names, `morphir` and `s d k`.

    Then its canonical JSON spelling is [["morphir"], ["s", "d", "k"]]

  @node:FQName @version:3 @spelling
  Scenario: versions-0014 A v3 fully qualified name is three arrays
    Package path, module path and local name, in that order. v4 writes the same name as `morphir/SDK:basics#int`.

    Then its canonical JSON spelling is [[["morphir"], ["s", "d", "k"]], [["basics"]], ["int"]]

  @node:FQName @version:3 @semantic
  Scenario: versions-0015 A v3 fully qualified name has all three parts
    A package path and a module path without a local name is not a fully qualified name. It is refused with `invalid_type`, as versions-0012 refuses a malformed name.

    Then a reader of JSON rejects [[["morphir"], ["s", "d", "k"]], [["basics"]]] with invalid_type

  @node:Literal @version:3 @semantic
  Scenario Outline: versions-0016 The v3 literal tags
    The six literal tags morphir-elm writes, each read as its own kind. versions-0006 pins the text a `DecimalLiteral` keeps.

    Then a reader of JSON reads <input> as a <kind>

    Examples:
      | input                       | kind               |
      | ["BoolLiteral", true]       | BoolLiteral        |
      | ["CharLiteral", "f"]        | CharLiteral        |
      | ["StringLiteral", ""]       | StringLiteral      |
      | ["WholeNumberLiteral", 1]   | WholeNumberLiteral |
      | ["FloatLiteral", 1.5]       | FloatLiteral       |
      | ["DecimalLiteral", "10.50"] | DecimalLiteral     |

  @node:Literal @version:3 @semantic
  Scenario: versions-0017 An integral FloatLiteral is still a float
    morphir-elm writes a `Float` through JavaScript, so `1.0` comes out as `1`; `documents/v3/evaluator-tests.json` has many of them. The tag decides the kind, not the number's lexical form. This case pins the reading only. Which spelling a v3 writer gives an integral float is not decided here.

    Then a reader of JSON reads ["FloatLiteral", 1] as a FloatLiteral

  @node:Literal @version:3 @spelling
  Scenario: versions-0018 A v3 char literal is a one-character string
    morphir-elm encodes a `Char` with `String.fromChar`.

    Then its canonical JSON spelling is ["CharLiteral", "f"]

  @node:Type @version:3 @semantic
  Scenario Outline: versions-0019 The v3 type tags
    The seven type expression tags morphir-elm writes, each read as its own kind.

    Then a reader of JSON reads <input> as a <kind>

    Examples:
      | input                                                                              | kind             |
      | ["Variable", {}, ["a"]]                                                            | Variable         |
      | ["Reference", {}, [[["morphir"], ["s", "d", "k"]], [["basics"]], ["int"]], []]     | Reference        |
      | ["Tuple", {}, []]                                                                  | Tuple            |
      | ["Record", {}, []]                                                                 | Record           |
      | ["ExtensibleRecord", {}, ["r"], []]                                                | ExtensibleRecord |
      | ["Function", {}, ["Unit", {}], ["Unit", {}]]                                       | Function         |
      | ["Unit", {}]                                                                       | Unit             |

  @node:Type @version:3 @spelling
  Scenario: versions-0020 A v3 type carries its attributes second
    Every v3 type expression is a tagged array whose second element is its attributes. morphir-elm writes `{}` there in every document it produces, typed or not. An extensible record names its variable and lists its fields the way versions-0008 lists a record's.

    Then its canonical JSON spelling is ["Function", {}, ["ExtensibleRecord", {}, ["r"], [{ "name": ["email"], "tpe": ["Reference", {}, [[["morphir"], ["s", "d", "k"]], [["string"]], ["string"]], []] }]], ["Tuple", {}, [["Variable", {}, ["r"]], ["Unit", {}]]]]

  @node:Pattern @version:3 @semantic
  Scenario Outline: versions-0021 The v3 pattern tags
    The eight pattern tags morphir-elm writes, each read as its own kind.

    Then a reader of JSON reads <input> as a <kind>

    Examples:
      | input                                                                        | kind               |
      | ["WildcardPattern", {}]                                                      | WildcardPattern    |
      | ["AsPattern", {}, ["WildcardPattern", {}], ["x"]]                            | AsPattern          |
      | ["TuplePattern", {}, []]                                                     | TuplePattern       |
      | ["ConstructorPattern", {}, [[["morphir"], ["s", "d", "k"]], [["maybe"]], ["nothing"]], []] | ConstructorPattern |
      | ["EmptyListPattern", {}]                                                     | EmptyListPattern   |
      | ["HeadTailPattern", {}, ["WildcardPattern", {}], ["WildcardPattern", {}]]    | HeadTailPattern    |
      | ["LiteralPattern", {}, ["BoolLiteral", true]]                                | LiteralPattern     |
      | ["UnitPattern", {}]                                                          | UnitPattern        |

  @node:Pattern @version:3 @spelling
  Scenario: versions-0022 A v3 pattern carries its attributes second
    A pattern is a tagged array with its attributes second, like a type or a value. A constructor pattern's arguments and a tuple pattern's elements are arrays of patterns.

    Then its canonical JSON spelling is ["TuplePattern", {}, [["HeadTailPattern", {}, ["AsPattern", {}, ["WildcardPattern", {}], ["head"]], ["EmptyListPattern", {}]], ["ConstructorPattern", {}, [[["morphir"], ["s", "d", "k"]], [["maybe"]], ["just"]], [["LiteralPattern", {}, ["WholeNumberLiteral", 1]]]], ["UnitPattern", {}]]]

  @node:Pattern @version:3 @spelling @compare:attributes
  Scenario: versions-0023 A typed v3 pattern keeps its type
    In morphir-elm's typed IR each pattern's attribute is the type it matches; this one is taken from `documents/v3/evaluator-tests.json`. Compared with attributes, a reader keeps it.

    Then its canonical JSON spelling is ["AsPattern", ["Unit", {}], ["WildcardPattern", ["Unit", {}]], ["to", "destructure"]]

  @node:Value @version:3 @semantic
  Scenario Outline: versions-0024 The v3 value tags
    The eighteen value expression tags morphir-elm writes, each read as its own kind. A record update is `UpdateRecord`, the only spelling morphir-elm reads or writes.

    Then a reader of JSON reads <input> as a <kind>

    Examples:
      | input                                                                                                      | kind          |
      | ["Literal", {}, ["BoolLiteral", true]]                                                                     | Literal       |
      | ["Constructor", {}, [[["morphir"], ["s", "d", "k"]], [["maybe"]], ["nothing"]]]                            | Constructor   |
      | ["Tuple", {}, []]                                                                                          | Tuple         |
      | ["List", {}, []]                                                                                           | List          |
      | ["Record", {}, []]                                                                                         | Record        |
      | ["Variable", {}, ["x"]]                                                                                    | Variable      |
      | ["Reference", {}, [[["morphir"], ["s", "d", "k"]], [["basics"]], ["pi"]]]                                  | Reference     |
      | ["Field", {}, ["Variable", {}, ["r"]], ["x"]]                                                              | Field         |
      | ["FieldFunction", {}, ["x"]]                                                                               | FieldFunction |
      | ["Apply", {}, ["Variable", {}, ["f"]], ["Unit", {}]]                                                       | Apply         |
      | ["Lambda", {}, ["WildcardPattern", {}], ["Unit", {}]]                                                      | Lambda        |
      | ["LetDefinition", {}, ["y"], { "inputTypes": [], "outputType": ["Unit", {}], "body": ["Unit", {}] }, ["Unit", {}]] | LetDefinition |
      | ["LetRecursion", {}, [], ["Unit", {}]]                                                                     | LetRecursion  |
      | ["Destructure", {}, ["WildcardPattern", {}], ["Unit", {}], ["Unit", {}]]                                   | Destructure   |
      | ["IfThenElse", {}, ["Variable", {}, ["b"]], ["Unit", {}], ["Unit", {}]]                                    | IfThenElse    |
      | ["PatternMatch", {}, ["Variable", {}, ["m"]], [[["WildcardPattern", {}], ["Unit", {}]]]]                   | PatternMatch  |
      | ["UpdateRecord", {}, ["Variable", {}, ["r"]], []]                                                          | UpdateRecord  |
      | ["Unit", {}]                                                                                               | Unit          |

  @node:Value @version:3 @spelling
  Scenario: versions-0025 v3 let forms carry value definitions
    `LetDefinition` names one definition and `LetRecursion` lists `[name, definition]` pairs. Each definition is the object versions-0034 pins.

    Then its canonical JSON spelling is ["LetRecursion", {}, [[["f"], { "inputTypes": [[["x"], {}, ["Variable", {}, ["a"]]]], "outputType": ["Variable", {}, ["a"]], "body": ["Variable", {}, ["x"]] }]], ["LetDefinition", {}, ["y"], { "inputTypes": [], "outputType": ["Reference", {}, [[["morphir"], ["s", "d", "k"]], [["basics"]], ["int"]], []], "body": ["Apply", {}, ["Variable", {}, ["f"]], ["Literal", {}, ["WholeNumberLiteral", 2]]] }, ["Variable", {}, ["y"]]]]

  @node:Value @version:3 @spelling
  Scenario: versions-0026 v3 lambdas, matches and destructuring carry patterns
    A lambda's argument and a destructuring's left side are patterns, and a pattern match lists `[pattern, value]` pairs in source order.

    Then its canonical JSON spelling is ["Lambda", {}, ["AsPattern", {}, ["WildcardPattern", {}], ["m"]], ["PatternMatch", {}, ["Variable", {}, ["m"]], [[["ConstructorPattern", {}, [[["morphir"], ["s", "d", "k"]], [["maybe"]], ["just"]], [["AsPattern", {}, ["WildcardPattern", {}], ["pair"]]]], ["Destructure", {}, ["TuplePattern", {}, [["AsPattern", {}, ["WildcardPattern", {}], ["a"]], ["WildcardPattern", {}]]], ["Variable", {}, ["pair"]], ["Variable", {}, ["a"]]]], [["WildcardPattern", {}], ["Literal", {}, ["WholeNumberLiteral", 0]]]]]]

  @node:Value @version:3 @spelling
  Scenario: versions-0027 v3 records are lists of name and value pairs
    A record lists `[name, value]` pairs; field access and a field function name the field.

    Then its canonical JSON spelling is ["Apply", {}, ["FieldFunction", {}, ["truth"]], ["Field", {}, ["Record", {}, [[["inner"], ["Record", {}, [[["name"], ["Literal", {}, ["StringLiteral", "x"]]], [["truth"], ["Literal", {}, ["BoolLiteral", false]]]]]]]], ["inner"]]]

  @node:Value @version:3 @pending
  Scenario: versions-0028 A v3 record update is written UpdateRecord
    morphir-elm writes and reads a record update only as `UpdateRecord`, so the canonical v3 spelling of this node is `["UpdateRecord", {}, ["Variable", {}, ["initial"]], [[["number"], ["Literal", {}, ["WholeNumberLiteral", 5]]]]]`. The Rust classic writer emits the tag `Update`, which morphir-elm refuses. This case stays pending until that writer agrees; versions-0024 holds every v3 reader to reading `UpdateRecord` meanwhile.

  @node:Value @version:3 @spelling
  Scenario: versions-0029 The remaining v3 value forms
    Conditionals, lists, tuples, constructors, references, applications and unit, nested as morphir-elm writes them.

    Then its canonical JSON spelling is ["IfThenElse", {}, ["Variable", {}, ["b"]], ["List", {}, [["Tuple", {}, [["Constructor", {}, [[["morphir"], ["s", "d", "k"]], [["maybe"]], ["just"]]], ["Unit", {}]]]]], ["Apply", {}, ["Reference", {}, [[["morphir"], ["s", "d", "k"]], [["list"]], ["singleton"]]], ["Literal", {}, ["CharLiteral", "f"]]]]

  @node:Value @version:3 @spelling @compare:attributes
  Scenario: versions-0030 A typed v3 value keeps its type
    morphir-elm's typed IR puts each value's inferred type where its attributes go. This body of `addOne` comes from `documents/v3/example-project.json`. Compared with attributes, a reader keeps every type, inner values included.

    Then its canonical JSON spelling is ["Apply", ["Reference", {}, [[["morphir"], ["s", "d", "k"]], [["basics"]], ["int"]], []], ["Apply", ["Function", {}, ["Reference", {}, [[["morphir"], ["s", "d", "k"]], [["basics"]], ["int"]], []], ["Reference", {}, [[["morphir"], ["s", "d", "k"]], [["basics"]], ["int"]], []]], ["Reference", ["Function", {}, ["Reference", {}, [[["morphir"], ["s", "d", "k"]], [["basics"]], ["int"]], []], ["Function", {}, ["Reference", {}, [[["morphir"], ["s", "d", "k"]], [["basics"]], ["int"]], []], ["Reference", {}, [[["morphir"], ["s", "d", "k"]], [["basics"]], ["int"]], []]]], [[["morphir"], ["s", "d", "k"]], [["basics"]], ["add"]]], ["Variable", ["Reference", {}, [[["morphir"], ["s", "d", "k"]], [["basics"]], ["int"]], []], ["x"]]], ["Literal", ["Reference", {}, [[["morphir"], ["s", "d", "k"]], [["basics"]], ["int"]], []], ["WholeNumberLiteral", 1]]]

  @node:Value @version:3
  Scenario: versions-0031 A typed v3 value is read under the default comparison
    Under the default comparison a reader clears attributes before writing, so a type in a value's attribute position reads back as `{}`. A reader therefore accepts either form in a standalone v3 value; inside a `Library` the attribute must be a type (distributions-0013). The Ion reference codec admits v4 values only, so this accepted check keeps the original form rather than `@semantic`.

    Then its canonical JSON spelling is ["Variable", {}, ["x"]]
    And a reader of JSON accepts ["Variable", ["Reference", {}, [[["morphir"], ["s", "d", "k"]], [["basics"]], ["int"]], []], ["x"]]

  @node:Value @version:3 @semantic
  Scenario Outline: versions-0032 An unknown v3 value tag is refused
    A tag morphir-elm does not write, including a v4 tag such as `Hole`, is not a v3 value. It is refused with `invalid_type`, as versions-0012 refuses a malformed name.

    Then a reader of JSON rejects <input> with invalid_type

    Examples:
      | input                                                  |
      | ["Lambada", {}, ["WildcardPattern", {}], ["Unit", {}]] |
      | ["Hole", {}]                                           |

  @node:Value @version:3 @semantic
  Scenario Outline: versions-0033 A v3 value of the wrong shape is refused
    A known tag with a missing element, a name given as a string, or the v4 object spelling is refused with `invalid_type`.

    Then a reader of JSON rejects <input> with invalid_type

    Examples:
      | input                                  |
      | ["Apply", {}, ["Variable", {}, ["f"]]] |
      | ["Variable", {}, "x"]                  |
      | { "Variable": "x" }                    |

  @node:ValueDefinition @version:3 @spelling
  Scenario: versions-0034 A v3 value definition lists its inputs as triples
    `inputTypes` lists `[name, attributes, type]` triples, then `outputType` and `body` follow.

    Then its canonical JSON spelling is { "inputTypes": [[["x"], {}, ["Reference", {}, [[["morphir"], ["s", "d", "k"]], [["basics"]], ["int"]], []]]], "outputType": ["Reference", {}, [[["morphir"], ["s", "d", "k"]], [["basics"]], ["int"]], []], "body": ["Variable", {}, ["x"]] }

  @node:ValueDefinition @version:3 @spelling @compare:attributes
  Scenario: versions-0035 A typed v3 value definition keeps its types
    In typed IR each input's attributes are its type, as each value's are (versions-0030).

    Then its canonical JSON spelling is { "inputTypes": [[["x"], ["Reference", {}, [[["morphir"], ["s", "d", "k"]], [["basics"]], ["int"]], []], ["Reference", {}, [[["morphir"], ["s", "d", "k"]], [["basics"]], ["int"]], []]]], "outputType": ["Reference", {}, [[["morphir"], ["s", "d", "k"]], [["basics"]], ["int"]], []], "body": ["Variable", ["Reference", {}, [[["morphir"], ["s", "d", "k"]], [["basics"]], ["int"]], []], ["x"]] }

  @node:TypeSpecification @version:3 @semantic
  Scenario Outline: versions-0036 The v3 type specification tags
    The four specification tags, each read as its own kind. versions-0007 pins the derived one's spelling.

    Then a reader of JSON reads <input> as a <kind>

    Examples:
      | input                                                                                                                                                                                                       | kind                     |
      | ["TypeAliasSpecification", [], ["Unit", {}]]                                                                                                                                                               | TypeAliasSpecification   |
      | ["OpaqueTypeSpecification", []]                                                                                                                                                                             | OpaqueTypeSpecification  |
      | ["CustomTypeSpecification", [], []]                                                                                                                                                                         | CustomTypeSpecification  |
      | ["DerivedTypeSpecification", [], { "baseType": ["Unit", {}], "fromBaseType": [[["my"], ["org"]], [["module"]], ["from"]], "toBaseType": [[["my"], ["org"]], [["module"]], ["to"]] }]                      | DerivedTypeSpecification |

  @node:TypeSpecification @version:3 @spelling
  Scenario: versions-0037 A v3 custom type specification lists its constructors
    Constructors are `[name, arguments]` pairs, and each argument is a `[name, type]` pair. A specification's constructors carry no access; a definition's do (distributions-0012).

    Then its canonical JSON spelling is ["CustomTypeSpecification", [["a"]], [[["just"], [[["value"], ["Variable", {}, ["a"]]]]], [["nothing"], []]]]
