# Document tree

## document-tree-0001: Manifest file {node=DistributionManifestFile}

The root file is `manifest`, never `format`. `pathBudget` is required per decision 0001.

```yaml canonical
formatVersion: 4
distribution: Library
package: my-org/my-project
pathBudget: 4000
```

```json canonical
{ "formatVersion": 4, "distribution": "Library", "package": "my-org/my-project", "pathBudget": 4000 }
```

## document-tree-0002: Module manifest, names only {node=ModuleManifestFile}

```yaml canonical
formatVersion: 4
path: my-org/domain
types: [user, user-ID]
values: [get-user]
```

```json canonical
{ "formatVersion": 4, "path": "my-org/domain", "types": ["user", "user-ID"], "values": ["get-user"] }
```

```json accepted
{ "formatVersion": 4, "module": "my-org/domain", "types": ["user", "user-ID"], "values": ["get-user"] }
```

## document-tree-0003: Node filename is the escaped stem {node=Distribution}

`user-ID` is stored as `user-_id.type.yaml`. Decision 0001.

```yaml file path=manifest set=escape
formatVersion: 4
distribution: Library
package: my-org/my-project
pathBudget: 4000
```

```yaml file path=pkg/my-org/my-project/domain/module set=escape
formatVersion: 4
path: domain
types: [user-ID]
values: []
```

```yaml file path=pkg/my-org/my-project/domain/user-_id.type set=escape
formatVersion: 4
name: user-ID
def:
  Public:
    doc: The user's identifier
    TypeAliasDefinition:
      typeParams: []
      typeExp: morphir/SDK:string#string
```

```yaml canonical
formatVersion: 4
distribution:
  Library:
    packageName: my-org/my-project
    dependencies: {}
    def:
      modules:
        domain:
          Public:
            types:
              user-ID:
                Public:
                  doc: The user's identifier
                  TypeAliasDefinition:
                    typeParams: []
                    typeExp: morphir/SDK:string#string
            values: {}
```

## document-tree-0004: A stem truncated for the path budget is recorded in fileNames {node=Distribution}

Decision 0012. The budget is 64 characters from the distribution root. `pkg/my-org/my-project/domain/` is 29 characters and `.type.yaml` is 10, leaving 25 for the stem; a truncated stem keeps `25 - 10 = 15` characters of the escaped stem, drops any trailing `-` or `_`, and appends `__` plus the first 8 hex digits of the SHA-256 of the untruncated escaped stem. The module manifest maps the canonical name to the stem, and the name still appears under `types`.

```yaml file path=manifest set=truncate
formatVersion: 4
distribution: Library
package: my-org/my-project
pathBudget: 64
```

```yaml file path=pkg/my-org/my-project/domain/module set=truncate
formatVersion: 4
path: domain
types: [customer-relationship-management-record]
values: []
fileNames:
  customer-relationship-management-record: customer-relati__44a101f8
```

```yaml file path=pkg/my-org/my-project/domain/customer-relati__44a101f8.type set=truncate
formatVersion: 4
name: customer-relationship-management-record
def:
  Public:
    TypeAliasDefinition:
      typeParams: []
      typeExp: morphir/SDK:string#string
```

```yaml canonical
formatVersion: 4
distribution:
  Library:
    packageName: my-org/my-project
    dependencies: {}
    def:
      modules:
        domain:
          Public:
            types:
              customer-relationship-management-record:
                Public:
                  TypeAliasDefinition:
                    typeParams: []
                    typeExp: morphir/SDK:string#string
            values: {}
```

## document-tree-0005: A top-level $meta member is reserved and ignored {node=Distribution}

Decision 0014. A reader never reports `unknown_member` for `$meta` at the top level of a document-tree file, and never writes one. `session.jsonl` is daemon workspace state, not part of a distribution.

```yaml file path=manifest set=meta mode=read
formatVersion: 4
distribution: Library
package: my-org/my-project
pathBudget: 4000
$meta:
  generator: example
```

```yaml file path=pkg/my-org/my-project/domain/module set=meta mode=read
formatVersion: 4
path: domain
types: []
values: []
$meta:
  generator: example
```

```yaml canonical
formatVersion: 4
distribution:
  Library:
    packageName: my-org/my-project
    dependencies: {}
    def:
      modules:
        domain:
          Public:
            types: {}
            values: {}
```

## document-tree-0006: The same tree in the JSON profile {node=Distribution}

A `file` set is written in one profile, and a tree says the same thing in either. This is `document-tree-0003`'s set spelled in the JSON profile: the logical paths are identical — they carry no extension — and only the bytes of each document change, so a reader and a writer that agree on the tree must agree on both profiles.

```json file path=manifest set=escape-json
{ "formatVersion": 4, "distribution": "Library", "package": "my-org/my-project", "pathBudget": 4000 }
```

```json file path=pkg/my-org/my-project/domain/module set=escape-json
{ "formatVersion": 4, "path": "domain", "types": ["user-ID"], "values": [] }
```

```json file path=pkg/my-org/my-project/domain/user-_id.type set=escape-json
{ "formatVersion": 4, "name": "user-ID", "def": { "Public": { "doc": "The user's identifier", "TypeAliasDefinition": { "typeParams": [], "typeExp": "morphir/SDK:string#string" } } } }
```

```yaml canonical
formatVersion: 4
distribution:
  Library:
    packageName: my-org/my-project
    dependencies: {}
    def:
      modules:
        domain:
          Public:
            types:
              user-ID:
                Public:
                  doc: The user's identifier
                  TypeAliasDefinition:
                    typeParams: []
                    typeExp: morphir/SDK:string#string
            values: {}
```

```json canonical
{ "formatVersion": 4, "distribution": { "Library": { "packageName": "my-org/my-project", "dependencies": {}, "def": { "modules": { "domain": { "Public": { "types": { "user-ID": { "Public": { "doc": "The user's identifier", "TypeAliasDefinition": { "typeParams": [], "typeExp": "morphir/SDK:string#string" } } } }, "values": {} } } } } } } }
```

## document-tree-0007: A Private module {node=Distribution}

A package definition's modules are access-controlled, so the module manifest carries an optional `access` member (document-tree page, "access (module manifest)"). It defaults to `Public` and a writer emits it only for a `Private` module, which keeps every existing manifest byte-identical while letting a private module round-trip through a tree.

```yaml file path=manifest set=private
formatVersion: 4
distribution: Library
package: my-org/my-project
pathBudget: 4000
```

```yaml file path=pkg/my-org/my-project/domain/module set=private
formatVersion: 4
path: domain
access: Private
types: []
values: []
```

```yaml canonical
formatVersion: 4
distribution:
  Library:
    packageName: my-org/my-project
    dependencies: {}
    def:
      modules:
        domain:
          Private:
            types: {}
            values: {}
```

```json canonical
{ "formatVersion": 4, "distribution": { "Library": { "packageName": "my-org/my-project", "dependencies": {}, "def": { "modules": { "domain": { "Private": { "types": {}, "values": {} } } } } } } }
```

## document-tree-0008: A dependency lives under deps {node=Distribution}

A tree holds its dependencies under `deps/<package path>/@<version>/`, laid out exactly as `pkg/` is below that segment. The segment beginning with `@` ends the package path, so a package named `a` and one named `a/b` can never claim the same directory; it is a bare `@` while the v4 model carries no package version (decision 0015). The distribution manifest lists each dependency package under `dependencies`, so discovery reads one file instead of walking `deps/`. A `Library` tree's dependencies are package specifications, so their node files carry `spec`.

```yaml file path=manifest set=deps
formatVersion: 4
distribution: Library
package: my-org/my-project
pathBudget: 4000
dependencies: [morphir/SDK]
```

```yaml file path=pkg/my-org/my-project/domain/module set=deps
formatVersion: 4
path: domain
types: []
values: []
```

```yaml file path=deps/morphir/_sdk/@/basics/module set=deps
formatVersion: 4
path: basics
types: [int]
values: []
```

```yaml file path=deps/morphir/_sdk/@/basics/int.type set=deps
formatVersion: 4
name: int
spec:
  OpaqueTypeSpecification: {}
```

```yaml canonical
formatVersion: 4
distribution:
  Library:
    packageName: my-org/my-project
    dependencies:
      morphir/SDK:
        modules:
          basics:
            types:
              int:
                OpaqueTypeSpecification: {}
            values: {}
    def:
      modules:
        domain:
          Public:
            types: {}
            values: {}
```

```json canonical
{ "formatVersion": 4, "distribution": { "Library": { "packageName": "my-org/my-project", "dependencies": { "morphir/SDK": { "modules": { "basics": { "types": { "int": { "OpaqueTypeSpecification": {} } }, "values": {} } } } }, "def": { "modules": { "domain": { "Public": { "types": {}, "values": {} } } } } } } }
```

## document-tree-0009: An application's dependencies are definitions under deps {node=Distribution}

An `Application` links its dependencies statically (distributions-0010), so the node files under its `deps/` carry `def`, access-controlled like the package's own, where a `Library` or `Specs` tree's carry `spec` (document-tree-0008). The entry points live in the distribution manifest.

```yaml file path=manifest set=app-deps
formatVersion: 4
distribution: Application
package: example
pathBudget: 4000
dependencies: [my-org/shared]
entryPoints:
  start:
    target: example:main#run
    kind: main
```

```yaml file path=pkg/example/main/module set=app-deps
formatVersion: 4
path: main
types: []
values: [run]
```

```yaml file path=pkg/example/main/run.value set=app-deps
formatVersion: 4
name: run
def:
  Public:
    ExpressionBody:
      inputTypes: {}
      outputType: morphir/SDK:basics#unit
      body:
        Unit: {}
```

```yaml file path=deps/my-org/shared/@/util/module set=app-deps
formatVersion: 4
path: util
types: []
values: [identity]
```

```yaml file path=deps/my-org/shared/@/util/identity.value set=app-deps
formatVersion: 4
name: identity
def:
  Public:
    ExpressionBody:
      inputTypes:
        x: morphir/SDK:basics#int
      outputType: morphir/SDK:basics#int
      body:
        Variable: x
```

```yaml canonical
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
```

```json canonical
{ "formatVersion": 4, "distribution": { "Application": { "packageName": "example", "dependencies": { "my-org/shared": { "modules": { "util": { "Public": { "types": {}, "values": { "identity": { "Public": { "ExpressionBody": { "inputTypes": { "x": "morphir/SDK:basics#int" }, "outputType": "morphir/SDK:basics#int", "body": { "Variable": "x" } } } } } } } } } }, "def": { "modules": { "main": { "Public": { "types": {}, "values": { "run": { "Public": { "ExpressionBody": { "inputTypes": {}, "outputType": "morphir/SDK:basics#unit", "body": { "Unit": {} } } } } } } } } }, "entryPoints": { "start": { "target": "example:main#run", "kind": "main" } } } } }
```

## document-tree-0010: v3 manifest {node=DistributionManifestFile version=3}

A v3 tree's own manifest file is the same shape decision-for-decision as the v4 one (document-tree-0001), except every file says its own `formatVersion`, `"3.1.0"` (decision 0016). A v3 document tree has a YAML profile too, `manifest.yaml` alongside `manifest.json` (`docs/spec/ir/schemas/v3/document-tree-files.md`), the way every other v3 tree case in this file carries `yaml file` fences; this case pins both spellings like its v4 analogue, document-tree-0001.

```yaml canonical
formatVersion: 3.1.0
distribution: Library
package: my-org/my-project
pathBudget: 4000
```

```json canonical
{ "formatVersion": "3.1.0", "distribution": "Library", "package": "my-org/my-project", "pathBudget": 4000 }
```

## document-tree-0011: v3 Library module with definition files {node=Distribution version=3}

A v3 `Library` tree holds its own package's definitions under `pkg/`, laid out exactly as document-tree-0003 lays out a v4 one; only the envelope's `formatVersion` and what a node file's `def` carries differ. `def` is the classic payload exactly as a single v3 document writes it: `TypeAliasDefinition`'s tagged array, `Reference`'s empty attributes, and the fully qualified name as nested arrays.

```yaml file path=manifest set=v3-lib
formatVersion: 3.1.0
distribution: Library
package: my-org/my-project
pathBudget: 4000
```

```yaml file path=pkg/my-org/my-project/domain/module set=v3-lib
formatVersion: 3.1.0
path: domain
types: [user]
values: []
```

```yaml file path=pkg/my-org/my-project/domain/user.type set=v3-lib
formatVersion: 3.1.0
name: user
def:
  access: Public
  value:
    doc: ""
    value:
      - TypeAliasDefinition
      - []
      - - Reference
        - {}
        - [[[morphir], [s, d, k]], [[string]], [string]]
        - []
```

```yaml canonical
formatVersion: 3
distribution:
  - Library
  - [[my, org], [my, project]]
  - []
  - modules:
      - - [[domain]]
        - access: Public
          value:
            types:
              - - [user]
                - access: Public
                  value:
                    doc: ""
                    value:
                      - TypeAliasDefinition
                      - []
                      - - Reference
                        - {}
                        - [[[morphir], [s, d, k]], [[string]], [string]]
                        - []
            values: []
            doc: null
```

```json canonical
{ "formatVersion": 3, "distribution": ["Library", [["my", "org"], ["my", "project"]], [], { "modules": [[[["domain"]], { "access": "Public", "value": { "types": [[["user"], { "access": "Public", "value": { "doc": "", "value": ["TypeAliasDefinition", [], ["Reference", {}, [[["morphir"], ["s", "d", "k"]], [["string"]], ["string"]], []]] } }]], "values": [], "doc": null } }]] }] }
```

## document-tree-0012: v3 dependency specifications under deps {node=Distribution version=3}

The v3 shape of document-tree-0008: a `Library` tree's dependencies live under `deps/<package path>/@/`, laid out like `pkg/`, and their node files carry `spec` rather than `def`.

```yaml file path=manifest set=v3-deps
formatVersion: 3.1.0
distribution: Library
package: my-org/my-project
pathBudget: 4000
dependencies: [morphir/SDK]
```

```yaml file path=pkg/my-org/my-project/domain/module set=v3-deps
formatVersion: 3.1.0
path: domain
types: []
values: []
```

```yaml file path=deps/morphir/_sdk/@/basics/module set=v3-deps
formatVersion: 3.1.0
path: basics
types: [int]
values: []
```

```yaml file path=deps/morphir/_sdk/@/basics/int.type set=v3-deps
formatVersion: 3.1.0
name: int
spec:
  doc: ""
  value: [OpaqueTypeSpecification, []]
```

```yaml canonical
formatVersion: 3
distribution:
  - Library
  - [[my, org], [my, project]]
  - - - [[morphir], [s, d, k]]
      - modules:
          - - [[basics]]
            - types:
                - - [int]
                  - doc: ""
                    value: [OpaqueTypeSpecification, []]
              values: []
              doc: null
  - modules:
      - - [[domain]]
        - access: Public
          value:
            types: []
            values: []
            doc: null
```

```json canonical
{ "formatVersion": 3, "distribution": ["Library", [["my", "org"], ["my", "project"]], [[[["morphir"], ["s", "d", "k"]], { "modules": [[[["basics"]], { "types": [[["int"], { "doc": "", "value": ["OpaqueTypeSpecification", []] }]], "values": [], "doc": null }]] }]], { "modules": [[[["domain"]], { "access": "Public", "value": { "types": [], "values": [], "doc": null } }]] }] }
```

## document-tree-0013: v3 Specs tree {node=Distribution version=3}

A v3 `Specs` tree carries `spec` everywhere, even under its own `pkg/`: it has no definitions to hold. No dependencies here; document-tree-0012 already pins a dependency's node files, which carry `spec` regardless of the tree's own kind.

```yaml file path=manifest set=v3-specs
formatVersion: 3.1.0
distribution: Specs
package: my/pkg
pathBudget: 4000
```

```yaml file path=pkg/my/pkg/basics/module set=v3-specs
formatVersion: 3.1.0
path: basics
doc: Basics.
types: [int]
values: []
```

```yaml file path=pkg/my/pkg/basics/int.type set=v3-specs
formatVersion: 3.1.0
name: int
spec:
  doc: ""
  value: [OpaqueTypeSpecification, []]
```

```yaml canonical
formatVersion: 3.1.0
distribution:
  - Specs
  - [[my], [pkg]]
  - []
  - modules:
      - - [[basics]]
        - types:
            - - [int]
              - doc: ""
                value: [OpaqueTypeSpecification, []]
          values: []
          doc: Basics.
```

```json canonical
{ "formatVersion": "3.1.0", "distribution": ["Specs", [["my"], ["pkg"]], [], { "modules": [[[["basics"]], { "types": [[["int"], { "doc": "", "value": ["OpaqueTypeSpecification", []] }]], "values": [], "doc": "Basics." }]] }] }
```

## document-tree-0014: v3 cut stem in fileNames {node=Distribution version=3}

The v3 shape of document-tree-0004: the same budget, the same name, the same truncated stem and hash suffix; only the envelope differs.

```yaml file path=manifest set=v3-truncate
formatVersion: 3.1.0
distribution: Library
package: my-org/my-project
pathBudget: 64
```

```yaml file path=pkg/my-org/my-project/domain/module set=v3-truncate
formatVersion: 3.1.0
path: domain
types: [customer-relationship-management-record]
values: []
fileNames:
  customer-relationship-management-record: customer-relati__44a101f8
```

```yaml file path=pkg/my-org/my-project/domain/customer-relati__44a101f8.type set=v3-truncate
formatVersion: 3.1.0
name: customer-relationship-management-record
def:
  access: Public
  value:
    doc: ""
    value:
      - TypeAliasDefinition
      - []
      - - Reference
        - {}
        - [[[morphir], [s, d, k]], [[string]], [string]]
        - []
```

```yaml canonical
formatVersion: 3
distribution:
  - Library
  - [[my, org], [my, project]]
  - []
  - modules:
      - - [[domain]]
        - access: Public
          value:
            types:
              - - [customer, relationship, management, record]
                - access: Public
                  value:
                    doc: ""
                    value:
                      - TypeAliasDefinition
                      - []
                      - - Reference
                        - {}
                        - [[[morphir], [s, d, k]], [[string]], [string]]
                        - []
            values: []
            doc: null
```

```json canonical
{ "formatVersion": 3, "distribution": ["Library", [["my", "org"], ["my", "project"]], [], { "modules": [[[["domain"]], { "access": "Public", "value": { "types": [[["customer", "relationship", "management", "record"], { "access": "Public", "value": { "doc": "", "value": ["TypeAliasDefinition", [], ["Reference", {}, [[["morphir"], ["s", "d", "k"]], [["string"]], ["string"]], []]] } }]], "values": [], "doc": null } }]] }] }
```

## document-tree-0015: v3 JSON profile {node=Distribution version=3}

document-tree-0011's set spelled in the JSON profile: the logical paths are identical, and only the bytes of each document change (document-tree-0006 does the same for a v4 tree).

```json file path=manifest set=v3-lib-json
{ "formatVersion": "3.1.0", "distribution": "Library", "package": "my-org/my-project", "pathBudget": 4000 }
```

```json file path=pkg/my-org/my-project/domain/module set=v3-lib-json
{ "formatVersion": "3.1.0", "path": "domain", "types": ["user"], "values": [] }
```

```json file path=pkg/my-org/my-project/domain/user.type set=v3-lib-json
{ "formatVersion": "3.1.0", "name": "user", "def": { "access": "Public", "value": { "doc": "", "value": ["TypeAliasDefinition", [], ["Reference", {}, [[["morphir"], ["s", "d", "k"]], [["string"]], ["string"]], []]] } } }
```

```yaml canonical
formatVersion: 3
distribution:
  - Library
  - [[my, org], [my, project]]
  - []
  - modules:
      - - [[domain]]
        - access: Public
          value:
            types:
              - - [user]
                - access: Public
                  value:
                    doc: ""
                    value:
                      - TypeAliasDefinition
                      - []
                      - - Reference
                        - {}
                        - [[[morphir], [s, d, k]], [[string]], [string]]
                        - []
            values: []
            doc: null
```

```json canonical
{ "formatVersion": 3, "distribution": ["Library", [["my", "org"], ["my", "project"]], [], { "modules": [[[["domain"]], { "access": "Public", "value": { "types": [[["user"], { "access": "Public", "value": { "doc": "", "value": ["TypeAliasDefinition", [], ["Reference", {}, [[["morphir"], ["s", "d", "k"]], [["string"]], ["string"]], []]] } }]], "values": [], "doc": null } }]] }] }
```

## document-tree-0016: A v4 file in a v3 tree is rejected {node=Distribution version=3}

A file's `formatVersion` must say `"3.1.0"`, the way `layout::read_tree_v3` checks every file of a v3 tree (document-tree-0010); document-tree-0011's node file with `formatVersion: "4.0.0"` instead is refused at that file's own member. `version_mismatch` is that reader's own code for this, confirmed against `ecosystem/morphir-rust/crates/morphir-mck-adapter/tests/protocol.rs`'s `a_v3_tree_diagnostic_comes_back_with_its_code_and_cursor`.

```json rejected diagnostic=version_mismatch
{ "formatVersion": "4.0.0", "name": "user", "def": { "access": "Public", "value": { "doc": "", "value": ["TypeAliasDefinition", [], ["Reference", {}, [[["morphir"], ["s", "d", "k"]], [["string"]], ["string"]], []]] } } }
```

## document-tree-0017: v3 tree files ignore $meta {node=Distribution version=3}

Decision 0014 holds for a v3 tree too: a reader never reports `unknown_member` for `$meta` at the top level of a document-tree file, and never writes one. The v3 shape of document-tree-0005's `mode=read` set; unlike 0005 it pins the assembled document in both profiles, yaml and json, the way the other new v3 tree cases do.

```yaml file path=manifest set=v3-meta mode=read
formatVersion: 3.1.0
distribution: Library
package: my-org/my-project
pathBudget: 4000
$meta:
  generator: example
```

```yaml file path=pkg/my-org/my-project/domain/module set=v3-meta mode=read
formatVersion: 3.1.0
path: domain
types: []
values: []
$meta:
  generator: example
```

```yaml canonical
formatVersion: 3
distribution:
  - Library
  - [[my, org], [my, project]]
  - []
  - modules:
      - - [[domain]]
        - access: Public
          value:
            types: []
            values: []
            doc: null
```

```json canonical
{ "formatVersion": 3, "distribution": ["Library", [["my", "org"], ["my", "project"]], [], { "modules": [[[["domain"]], { "access": "Public", "value": { "types": [], "values": [], "doc": null } }]] }] }
```
