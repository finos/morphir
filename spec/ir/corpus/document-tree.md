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
                  TypeAliasDefinition:
                    typeParams: []
                    typeExp: morphir/SDK:string#string
            values: {}
```
