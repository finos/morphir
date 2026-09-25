Feature: Distributions

  @node:FormatVersion
  Scenario Outline: distributions-0001 Format version spellings
    Governed by `docs/spec/ir/format-version.md` and its corpus. Integer 4 is canonical for 4.0.0; a later minor is not supported.

    Then its canonical <format> spelling is <spelling>

    Examples:
      | format | spelling |
      | YAML   | 4        |
      | JSON   | 4        |

  @node:FormatVersion
  Scenario: distributions-0001 Format version spellings
    Then a reader of JSON accepts "4.0.0"

  @node:FormatVersion
  Scenario Outline: distributions-0001 Format version spellings
    Then a reader of <format> rejects <input> with <diagnostic>

    Examples:
      | format | input        | diagnostic                       |
      | JSON   | "4.0.0-beta" | invalid_format_version_syntax    |
      | JSON   | "4.1.0"      | unsupported_format_version_minor |

  @node:Distribution
  Scenario: distributions-0002 Empty library
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
    And a reader of JSON accepts { "distribution": { "Library": { "packageName": "example", "dependencies": {}, "def": { "modules": {} } } }, "formatVersion": 4 }

  @node:Distribution
  Scenario: distributions-0003 A v3 tagged-array distribution is not a v4 document
    `tests/bdd/fixtures/ir/v4/v4-library-distribution.json` carried this shape. Bead morphir-ir-v4-stabilize.11.

    Then a reader of JSON rejects { "formatVersion": 4, "distribution": ["Library", "example/v4-test", {}, { "modules": [] }] } with invalid_distribution_shape

  @node:Distribution
  Scenario: distributions-0004 Complete library, JSON and YAML agree
    The published complete example and its YAML rendering are the same distribution. Both write record fields under `fields` (decision 0004), the SDK as `morphir/SDK` (decision 0011), and the list function's `parameterType` (decision 0007).

    `website/static/ir/examples/v4/complete-example.json` is the human-readable form the docs site publishes: it is pretty-printed and spells its format version `"4.0.0"`, both of which a reader accepts and a writer never emits, so it is an `accepted` spelling. The `json canonical` fence below is the writer's own output for the same distribution, on one line with the integer format version (distributions-0001). The YAML file stays canonical: it is the reference text form.

    Then a reader of text accepts website/static/ir/examples/v4/complete-example.json

  @node:Distribution
  Scenario Outline: distributions-0004 Complete library, JSON and YAML agree
    Then its canonical <format> spelling is <spelling>

    Examples:
      | format | spelling                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
      | JSON   | { "formatVersion": 4, "distribution": { "Library": { "packageName": "regulation", "dependencies": { "morphir/SDK": { "modules": { "basics": { "types": { "int": { "OpaqueTypeSpecification": {} }, "float": { "OpaqueTypeSpecification": {} }, "bool": { "OpaqueTypeSpecification": {} } }, "values": { "add": { "inputs": { "a": "morphir/SDK:basics#int", "b": "morphir/SDK:basics#int" }, "output": "morphir/SDK:basics#int" } } }, "list": { "types": { "list": { "TypeAliasSpecification": { "typeParams": ["a"], "typeExp": { "Reference": ["morphir/SDK:list#list", "a"] } } } }, "values": { "map": { "inputs": { "f": { "Function": { "parameterType": "a", "returnType": "b" } }, "list": { "Reference": ["morphir/SDK:list#list", "a"] } }, "output": { "Reference": ["morphir/SDK:list#list", "b"] } } } } } } }, "def": { "modules": { "u-s/f-r-2052-a/data-tables": { "Public": { "types": { "data-tables": { "Public": { "TypeAliasDefinition": { "typeParams": [], "typeExp": { "Record": { "fields": { "inflows": "regulation:u-s/f-r-2052-a/data-tables#inflows", "outflows": "regulation:u-s/f-r-2052-a/data-tables#outflows", "supplemental": "regulation:u-s/f-r-2052-a/data-tables#supplemental" } } } } } }, "inflows": { "Public": { "TypeAliasDefinition": { "typeParams": [], "typeExp": { "Record": { "fields": { "assets": { "Reference": ["morphir/SDK:list#list", "regulation:u-s/f-r-2052-a/data-tables/inflows#assets"] } } } } } } } }, "values": { "calculate-total": { "Public": { "ExpressionBody": { "inputTypes": { "tables": "regulation:u-s/f-r-2052-a/data-tables#data-tables" }, "outputType": "morphir/SDK:basics#float", "body": { "Literal": { "FloatLiteral": 0.0 } } } } } }, "doc": "Data tables module for regulatory reporting" } } } } } } } |
      | text   | spec/ir/mck/documents/complete-example.yaml                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |

  @node:Distribution
  Scenario: distributions-0005 The SDK dependency is keyed morphir/SDK
    Decision 0011. `morphir/sdk` is a valid name for some other package, so it is not rejected; it is simply not the SDK.

    Then its canonical YAML spelling is:
      """yaml
      formatVersion: 4
      distribution:
        Library:
          packageName: example
          dependencies:
            morphir/SDK:
              modules: {}
          def:
            modules: {}
      """
    And its canonical JSON spelling is { "formatVersion": 4, "distribution": { "Library": { "packageName": "example", "dependencies": { "morphir/SDK": { "modules": {} } }, "def": { "modules": {} } } } }

  @node:Distribution
  Scenario: distributions-0006 Specs distribution
    A `Specs` distribution publishes a package's public face and nothing else: its member is `spec`, a package specification, where a `Library` carries `def`, a package definition. `packageName`, `dependencies` and `spec` are the three members the reader accepts; `dependencies` and `spec` may be omitted and default to empty, and a writer emits all three regardless (distributions-0002).

    A `Specs` document has no `def`: an implementation is exactly what it does not carry.

    Then its canonical YAML spelling is:
      """yaml
      formatVersion: 4
      distribution:
        Specs:
          packageName: example
          dependencies:
            morphir/SDK:
              modules: {}
          spec:
            modules:
              main:
                types: {}
                values:
                  greet:
                    inputs:
                      name: morphir/SDK:string#string
                    output: morphir/SDK:string#string
      """
    And its canonical JSON spelling is { "formatVersion": 4, "distribution": { "Specs": { "packageName": "example", "dependencies": { "morphir/SDK": { "modules": {} } }, "spec": { "modules": { "main": { "types": {}, "values": { "greet": { "inputs": { "name": "morphir/SDK:string#string" }, "output": "morphir/SDK:string#string" } } } } } } } }
    And a reader of JSON rejects { "formatVersion": 4, "distribution": { "Specs": { "packageName": "example", "dependencies": {}, "def": { "modules": {} } } } } with unknown_member

  @node:Distribution
  Scenario: distributions-0007 Application distribution with entry points
    An `Application` is an executable package. It carries `packageName`, `dependencies`, `def` and `entryPoints`; `entryPoints` is required, because an application with no way in is not one. The dependency map holds package definitions rather than specifications, because an application links its dependencies statically. An entry point is keyed by a name the author chooses and holds `target`, `kind`, and an optional `doc`; the writer emits `doc` only when it is present, so `build` below has none.

    `doc` belongs to an entry point, not to the distribution. An `Application` accepts exactly the four members above, so a `doc` beside them is an unknown member rather than package documentation.

    `kind` is drawn from a fixed set: `main`, `command`, `handler`, `job`, `policy`.

    Then its canonical YAML spelling is:
      """yaml
      formatVersion: 4
      distribution:
        Application:
          packageName: example
          dependencies: {}
          def:
            modules:
              main:
                Public:
                  types: {}
                  values:
                    run:
                      Public:
                        ExpressionBody:
                          inputTypes: {}
                          outputType: morphir/SDK:basics#unit
                          body:
                            Unit: {}
          entryPoints:
            start:
              target: example:main#run
              kind: main
              doc: The application entry point
            build:
              target: example:main#run
              kind: command
      """
    And its canonical JSON spelling is { "formatVersion": 4, "distribution": { "Application": { "packageName": "example", "dependencies": {}, "def": { "modules": { "main": { "Public": { "types": {}, "values": { "run": { "Public": { "ExpressionBody": { "inputTypes": {}, "outputType": "morphir/SDK:basics#unit", "body": { "Unit": {} } } } } } } } } }, "entryPoints": { "start": { "target": "example:main#run", "kind": "main", "doc": "The application entry point" }, "build": { "target": "example:main#run", "kind": "command" } } } } }

  @node:Distribution
  Scenario Outline: distributions-0007 Application distribution with entry points
    Then a reader of <format> rejects <input> with <diagnostic>

    Examples:
      | format | input                                                                                                                                                                                                                       | diagnostic     |
      | JSON   | { "formatVersion": 4, "distribution": { "Application": { "packageName": "example", "dependencies": {}, "def": { "modules": {} }, "entryPoints": {}, "doc": "Applications document their entry points, not themselves" } } } | unknown_member |
      | JSON   | { "formatVersion": 4, "distribution": { "Application": { "packageName": "example", "dependencies": {}, "def": { "modules": {} }, "entryPoints": { "start": { "target": "example:main#run", "kind": "startup" } } } } }      | invalid_type   |

  @node:FormatVersion
  Scenario Outline: distributions-0008 Later patch of a supported minor
    A patch of a supported minor is read; its canonical spelling stays the release string, since only the baseline collapses to the integer. Governed by `docs/spec/ir/format-version.md`, Revisions.

    Then its canonical <format> spelling is <spelling>

    Examples:
      | format | spelling |
      | YAML   | 4.0.1    |
      | JSON   | "4.0.1"  |

  @node:Distribution
  Scenario: distributions-0009 A reserved $meta member belongs to document-tree files only
    `$meta` is reserved in the files of a document tree (document-tree-0005). A single document has no such member: at its root it is unknown.

    Then a reader of JSON rejects { "formatVersion": 4, "$meta": { "generator": "example" }, "distribution": { "Library": { "packageName": "example", "dependencies": {}, "def": { "modules": {} } } } } with unknown_member

  @node:Distribution
  Scenario: distributions-0010 An application's dependencies are package definitions
    An `Application` links its dependencies statically (distributions-0007), so each entry of its `dependencies` is a package definition — access-controlled modules carrying definitions — where a `Library` or `Specs` entry is a package specification (distributions-0005, 0006).

    Then its canonical YAML spelling is:
      """yaml
      formatVersion: 4
      distribution:
        Application:
          packageName: example
          dependencies:
            my-org/shared:
              modules:
                util:
                  Public:
                    types: {}
                    values:
                      identity:
                        Public:
                          ExpressionBody:
                            inputTypes:
                              x: morphir/SDK:basics#int
                            outputType: morphir/SDK:basics#int
                            body:
                              Variable: x
          def:
            modules:
              main:
                Public:
                  types: {}
                  values:
                    run:
                      Public:
                        ExpressionBody:
                          inputTypes: {}
                          outputType: morphir/SDK:basics#unit
                          body:
                            Unit: {}
          entryPoints:
            start:
              target: example:main#run
              kind: main
      """
    And its canonical JSON spelling is { "formatVersion": 4, "distribution": { "Application": { "packageName": "example", "dependencies": { "my-org/shared": { "modules": { "util": { "Public": { "types": {}, "values": { "identity": { "Public": { "ExpressionBody": { "inputTypes": { "x": "morphir/SDK:basics#int" }, "outputType": "morphir/SDK:basics#int", "body": { "Variable": "x" } } } } } } } } } }, "def": { "modules": { "main": { "Public": { "types": {}, "values": { "run": { "Public": { "ExpressionBody": { "inputTypes": {}, "outputType": "morphir/SDK:basics#unit", "body": { "Unit": {} } } } } } } } } }, "entryPoints": { "start": { "target": "example:main#run", "kind": "main" } } } } }

  @node:Distribution @version:3
  Scenario: distributions-0011 A v3 Specs distribution
    The classic counterpart of distributions-0006: a v3 `Specs` distribution publishes a package's public face, tagged-array style, with no `def` anywhere. document-tree-0013 lays the same shape out as a tree.

    Then its canonical JSON spelling is { "formatVersion": "3.1.0", "distribution": ["Specs", [["my"], ["pkg"]], [], { "modules": [[[["basics"]], { "types": [[["int"], { "doc": "", "value": ["OpaqueTypeSpecification", []] }]], "values": [], "doc": "Basics." }]] }] }
