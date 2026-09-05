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

## document-tree-0003: Node filename is the escaped stem {node=TypeDefinitionFile}

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

```yaml file path=manifest set=meta
formatVersion: 4
distribution: Library
package: my-org/my-project
pathBudget: 4000
$meta:
  generator: example
```

```yaml file path=pkg/my-org/my-project/domain/module set=meta
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
