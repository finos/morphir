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

  @node:Distribution @version:3 @spelling @compare:attributes
  Scenario: distributions-0012 A v3 Library with its dependencies and definitions
    The classic counterpart of distributions-0002 with content, in morphir-elm's member order. `Library` is followed by the package name, the dependencies and the package definition. Each dependency is a `[package name, package specification]` pair. A specification module holds `types`, `values` and `doc`; each type and value specification is documented as `{ "doc", "value" }`, and a value specification is `{ "inputs", "output" }`. Each definition module is access controlled, `{ "access", "value" }`, and so is each type and value definition inside it. A custom type definition puts its constructors under an access of their own, so that a public type can hide them. A module's `doc` is `null` when the module has none. A `Library`'s values are typed (distributions-0013), so the case compares attributes.

    Then its canonical JSON spelling is { "formatVersion": 3, "distribution": ["Library", [["my"], ["pkg"]], [[[["my"], ["dep"]], { "modules": [[[["util"]], { "types": [[["id"], { "doc": "An identifier.", "value": ["OpaqueTypeSpecification", []] }]], "values": [[["parse"], { "doc": "", "value": { "inputs": [[["text"], ["Reference", {}, [[["morphir"], ["s", "d", "k"]], [["string"]], ["string"]], []]]], "output": ["Reference", {}, [[["my"], ["dep"]], [["util"]], ["id"]], []] } }]], "doc": "Utilities." }]] }]], { "modules": [[[["domain"]], { "access": "Public", "value": { "types": [[["status"], { "access": "Public", "value": { "doc": "", "value": ["CustomTypeDefinition", [], { "access": "Private", "value": [[["active"], []], [["closed"], [[["reason"], ["Reference", {}, [[["morphir"], ["s", "d", "k"]], [["string"]], ["string"]], []]]]]] }] } }], [["user"], { "access": "Private", "value": { "doc": "A user.", "value": ["TypeAliasDefinition", [], ["Record", {}, [{ "name": ["id"], "tpe": ["Reference", {}, [[["my"], ["dep"]], [["util"]], ["id"]], []] }]]] } }]], "values": [[["is", "active"], { "access": "Public", "value": { "doc": "Whether the status is active.", "value": { "inputTypes": [[["s"], ["Reference", {}, [[["my"], ["pkg"]], [["domain"]], ["status"]], []], ["Reference", {}, [[["my"], ["pkg"]], [["domain"]], ["status"]], []]]], "outputType": ["Reference", {}, [[["morphir"], ["s", "d", "k"]], [["basics"]], ["bool"]], []], "body": ["PatternMatch", ["Reference", {}, [[["morphir"], ["s", "d", "k"]], [["basics"]], ["bool"]], []], ["Variable", ["Reference", {}, [[["my"], ["pkg"]], [["domain"]], ["status"]], []], ["s"]], [[["ConstructorPattern", ["Reference", {}, [[["my"], ["pkg"]], [["domain"]], ["status"]], []], [[["my"], ["pkg"]], [["domain"]], ["active"]], []], ["Literal", ["Reference", {}, [[["morphir"], ["s", "d", "k"]], [["basics"]], ["bool"]], []], ["BoolLiteral", true]]], [["WildcardPattern", ["Reference", {}, [[["my"], ["pkg"]], [["domain"]], ["status"]], []]], ["Literal", ["Reference", {}, [[["morphir"], ["s", "d", "k"]], [["basics"]], ["bool"]], []], ["BoolLiteral", false]]]]] } } }]], "doc": null } }]] }] }

  @node:Distribution @version:3 @semantic
  Scenario: distributions-0013 A v3 Library's values are typed
    morphir-elm's `Library` holds a `Package.Definition () (Type ())`: every value, pattern and input in it has a type as its attribute, where a standalone value may have `{}` (versions-0031). A `Library` whose value carries `{}` is refused with `invalid_type`, as versions-0012 refuses a malformed name.

    Then a reader of JSON rejects { "formatVersion": 3, "distribution": ["Library", [["my"], ["pkg"]], [], { "modules": [[[["m"]], { "access": "Public", "value": { "types": [], "values": [[["one"], { "access": "Public", "value": { "doc": "", "value": { "inputTypes": [], "outputType": ["Unit", {}], "body": ["Unit", {}] } } }]], "doc": null } }]] }] } with invalid_type

  @node:Distribution @version:3 @semantic
  Scenario Outline: distributions-0014 morphir-elm output reads as a Library
    These documents are morphir-elm 2.99.0's `morphir-ir.json` output, unedited, for projects in finos/morphir-scala's `examples/morphir-elm-projects` (commit c9d08e6). `evaluator-tests` exercises the widest range of value expressions; `example-project-tests-passing` has two dependencies, so it carries module and value specifications. A v3 reader reads each whole document. distributions-0015 checks what a reader makes of one of them.

    Then a reader of text reads <document> as a Library

    Examples:
      | document                                                    |
      | spec/ir/mck/documents/v3/evaluator-tests.json               |
      | spec/ir/mck/documents/v3/example-project-tests-passing.json |
      | spec/ir/mck/documents/v3/example-project.json               |

  @node:Distribution @version:3 @compare:attributes
  Scenario: distributions-0015 morphir-elm output survives reading
    `documents/v3/example-project.json` is one of the documents distributions-0014 reads. Compared with attributes, everything in it reads back as written, from module order and documentation strings to the type on every value and pattern. `documents/v3/example-project.canonical.json` holds the same JSON value in the canonical spelling. The Ion reference codec admits v4 values only, so this accepted check keeps the original form rather than `@semantic`.

    Then its canonical text spelling is spec/ir/mck/documents/v3/example-project.canonical.json
    And a reader of text accepts spec/ir/mck/documents/v3/example-project.json

  @node:Distribution @version:3 @semantic
  Scenario Outline: distributions-0016 A version 1 or 2 document is not a v3 document
    Offered as a version 3 `Distribution`, a document that declares another major version is refused with `version_mismatch`, as document-tree-0016 refuses a v4 one. Version 1 spells its tags in lowercase. Version 2 already spells them as version 3 does, so only `formatVersion` tells the two apart.

    Then a reader of JSON rejects <input> with version_mismatch

    Examples:
      | input                                                                                         |
      | { "formatVersion": 1, "distribution": ["library", [["my"], ["pkg"]], [], { "modules": [] }] } |
      | { "formatVersion": 2, "distribution": ["Library", [["my"], ["pkg"]], [], { "modules": [] }] } |

  @node:Distribution @version:3 @semantic
  Scenario: distributions-0017 A malformed v3 document is refused
    Text that is not JSON is refused with `invalid_json` before anything is read from it. Here the document's closing brace is missing.

    Then a reader of JSON rejects { "formatVersion": 3, "distribution": ["Library", [["my"], ["pkg"]], [], { "modules": [] }] with invalid_json

  @node:Distribution @version:3 @semantic
  Scenario: distributions-0018 A v3 document without a format version is refused
    morphir-elm always writes `formatVersion`. Without it a reader cannot tell a version 3 document from any other, so it refuses the document with `missing_format_version` (`docs/spec/ir/format-version.md`) rather than guessing.

    Then a reader of JSON rejects { "distribution": ["Library", [["my"], ["pkg"]], [], { "modules": [] }] } with missing_format_version

  @node:Distribution @version:3 @pending
  Scenario: distributions-0019 A v3 Bundle distribution
    morphir-scala's classic codec reads and writes a third distribution, `["Bundle", [[package name, { "dependencies": [[package name, package definition]], "packageDef": package definition }]]]`, which holds several libraries in one document. morphir-elm has no `Bundle`, and the Rust classic model has none either: it refuses the tag with `invalid_type`. Whether `Bundle` belongs to the v3 format at all is open, so this case is prose only until that is decided.
