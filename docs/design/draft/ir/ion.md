---
title: Ion IR format
sidebar_label: Ion
sidebar_position: 12
status: draft
tracking:
  github_issues: [946]
  github_discussions: [938, 942]
---

# Ion IR format

This draft specifies an Amazon Ion encoding of Morphir IR v3 and v4. JSON and YAML remain encodings of the same IR. Ion is another physical format. A reader of either Ion layout builds the same IR value that the JSON codec builds from the corresponding document.

The implementation plan is [issue 946](https://github.com/finos/morphir/issues/946). The design record is [discussion 938](https://github.com/finos/morphir/discussions/938) for v3 and [discussion 942](https://github.com/finos/morphir/discussions/942) for v4.

The contract version of this spelling is `ionVersion` `0.1.0-draft.1`. A draft matches only that exact string. The IR inside the document is selected by `formatVersion`, `3.0.0` or `4.0.0`.

Two words stay separate. An **Ion annotation** is a symbol before `::`. An **attribute** is the per-node payload, a classic list in v3 and a struct in v4. A **Morphir annotation** is the `annotations` list on a v4 specification.

## Document

A datagram is the reading layout. It is a sequence of top-level values. The first is the header. The last is `morphir_footer::{}`. A record is one `morphir::` value and has no footer. A reader accepts either. Collapse regroups a datagram into a record. Expand is the inverse. A writer that starts from the IR emits one struct per package and one per module, with members inline, because the IR has already merged authoring splits.

```ion
morphir::{
  ionVersion: "0.1.0-draft.1",
  formatVersion: "3.0.0",
  kind: library,
  packageName: "example/finance",
}
morphir_footer::{}
```

A missing `ionVersion` means the latest version that reader implements. Today that is `0.1.0-draft.1`. Writers still emit the field. `formatVersion` is required. A reader ignores a header member it does not understand unless `critical` names it. `ionVersion` follows SemVer. On `0.y.z` the minor acts as the major.

`kind` is `library` for v3. v4 adds `specs` and `application`. A v3 reader rejects a v4-only node.

## Annotations

A definition is access, role, then kind.

| Position | Symbols |
| --- | --- |
| Access | `public`, `private` |
| Role | `def` |
| Kind | `module`, `value`, `custom::type`, `alias::type` |

A member specification uses the same slots with role `spec`. Its access is `public`. `opaque::type` and `derived::type` occur as specifications. `incomplete::type` is a v4 definition.

A package or module specification is a grouping header. The noun comes first: `package::spec`, `module::spec`. An application dependency uses `package::def` the same way.

`opaque`, `derived`, `alias`, and `custom` are modifiers in front of `type`. `native`, `external`, and `incomplete` are modifiers in front of `value`. An expression definition stays `public::def::value`.

## Names and groups

Package names, module names, and fully qualified names are canonical strings. A v3 path array is rebuilt from that string. A missing `package` field on a definition means the distribution package. A `package::spec` whose name equals the header package is rejected in v3, because that package is carried by `def` nodes.

Several `package::spec` values with the same name are one package specification. Several `module::spec` values with the same package and name are one module specification. A `package::spec` may include `modules`. Those entries combine with top-level `module::spec` values for that package. A `module::spec` may include `types` and `values`. Those combine with top-level type and value specs that name the same module. Document order is the order of the merged lists. A repeated type or value name in the merged module is rejected.

Empty arrays are omitted: `dependencies`, `modules`, `types`, `values`, `typeParams`, `constructors`, `args`, `arguments`, and `inputTypes` or `inputs` when empty. A reader treats a missing array as empty.

## Types

A string that is a canonical fully qualified name is a reference with no arguments. A string that is a canonical local name is a variable. Any other string is rejected.

| Node | Spelling |
| --- | --- |
| Variable | `"a"` or `variable::{ name: "a" }` |
| Reference | `"morphir/SDK:basics#int"` or `reference::{ name, arguments }` |
| Tuple | `tuple::[ ... ]` |
| Record | `record::{ fields: [ { name, type } ] }` |
| Extensible record | `extensibleRecord::{ variable, fields }` |
| Function | `function::{ parameterType, returnType }` |
| Unit | `unit::{}` |

A function type is binary. A list type is a reference to `morphir/SDK:list#list`. A bare list at type position is a tuple. Attributes, when present, force the expanded struct.

```ion
public::def::custom::type::{
  module: "Eligibility",
  name: "Result",
  typeParams: ["a", "b"],
  access: public,
  constructors: [
    { name: "Ok", args: [ { name: "value", type: "a" } ] },
    { name: "Err", args: [ { name: "reason", type: "b" } ] },
  ],
}
```

`access` inside `custom::type` is the constructor group. The leading `public` is the type's own access. v3 type definitions are `alias::type` and `custom::type`. v3 type specifications add `opaque::type` and `derived::type`.

## Values

A v3 definition carries `inputTypes` as a list of `{ name, type }`, `outputType`, and `body`. A specification carries `inputs` and `output` and has no body. v4 uses a struct keyed by parameter name for both `inputTypes` and `inputs`. Field order is parameter order. `outputType` is optional only on an incomplete body.

The body is an S-expression. The first symbol is the node. Apply is binary. A bare int is a whole number in v3 and an integer in v4. A bare float is a float. `true` and `false` are bools. A bare symbol is a variable. `()` is unit. `[]` in pattern position is an empty list.

| Node | Spelling |
| --- | --- |
| Reference | `(ref 'morphir/SDK:basics#equal')` |
| Constructor | `(constructor 'example/finance:Eligibility#Ok')` |
| Apply | `(apply fn arg)` |
| Lambda | `(lambda [score] body)` |
| If | `(if cond then else)` |
| Let | `(let score { outputType: "...", body: 70 } score)` |
| Letrec | `(letrec ((f { outputType: "...", body: ... })) f)` |
| Match | `(match scrutinee [pattern body] [pattern body])` |
| Destructure | `(destructure pattern value body)` |
| Field | `(field record fieldName)` |
| Field function | `(fieldFunction fieldName)` |
| Record | `(record (fieldName value))` |
| Update | `(update record (fieldName value))` |
| Tuple | `(tuple a b)` |
| List | `(list 1 2 3)` |
| String | `(string "hello")` |
| Char | `(char "a")` |
| Decimal | `(decimal "10.50")` |

`(lambda [score] body)` means an `as` pattern over a wildcard. The explicit form is `(lambda [(as (wildcard) score)] body)`. A bare symbol in pattern position is that same binding. `_` is a wildcard. The other pattern heads are `as`, `tuple`, `constructor`, `headTail`, a literal, and `()`.

When a node has a non-empty attribute payload, a struct follows the head. v3 omits that struct when the payload is `[]`. v4 attributes are `source`, `constraints`, and `extensions` on a type, and `source`, `inferredType`, and `extensions` on a value or a pattern. Empty members are omitted. `constraints` and `extensions` hold JSON-compatible Ion only.

## v4 nodes

A `specs` distribution writes its own modules as `module::spec`. An `application` writes dependencies as `package::def` and puts `entryPoints` on the header. An entry point has `target` and `kind` (`main`, `command`, `handler`, `job`, or `policy`) and an optional `doc`.

```ion
public::def::native::value::{
  name: "add",
  inputTypes: { a: "morphir/SDK:basics#int", b: "morphir/SDK:basics#int" },
  outputType: "morphir/SDK:basics#int",
  hint: arithmetic,
}
```

`hint` is `arithmetic`, `comparison`, `stringOp`, `collectionOp`, or `platformSpecific::{ platform }`. An external body lists `{ targetPlatform, externalName }` and may carry a fallback `body`. An incomplete body uses `incompleteness: draft` or `incompleteness: hole::{ reason }`. The reason is `unresolvedReference::{ target }`, `deletedDuringRefactor::{ txId }`, or `typeMismatch::{ expected, found }`.

A hole expression is `(hole reason)` or `(hole reason expectedType)`. An incomplete type is `public::def::incomplete::type` with an optional `partialTypeExp`.

Morphir annotations are an `annotations` list on `module::spec`, a `public::spec::` type, and `public::spec::value`. A definition rejects the field. A compact entry is `pkg:mod#local` or `pkg:mod#local:free text`. A structured entry is `{ name, arguments }`.

A document literal is `(document <payload>)`. The payload is the document. An integer lexeme is an Ion int. Any other number is an Ion decimal written with the stored lexeme. Ion float, timestamp, blob, clob, symbol, and s-expression are rejected inside the payload. A document cannot appear in a pattern. A v4 float literal that keeps its source text is `(float "<lexeme>")`. A bare Ion float means the shortest spelling of that finite value.

## Document tree

An Ion document tree uses the same paths as the JSON and YAML trees, with the `.ion` extension: `manifest.ion`, `pkg/<package>/<module>/module.ion`, `<stem>.type.ion`, and `<stem>.value.ion`, plus the same three file kinds under `deps/<package>/@/<module>/`. Directory segments and stems are escaped file stems, so `morphir/SDK` is `deps/morphir/_sdk/@/`. Discovery reads `manifest.ion`. A second manifest (`manifest.json`, `manifest.yaml`, or `manifest.yml`) makes the root ambiguous. The tree applies to v3 and v4.

Each file holds the annotated elements of the single-file spelling. The path is the scope:

| File | Elements |
| --- | --- |
| `manifest.ion` | The `morphir::` header, then one `package::spec` for each dependency |
| `module.ion` | The module element, then any of its types and values |
| `<stem>.type.ion` | That one type |
| `<stem>.value.ion` | That one value |

The path supplies the package, the module, and a node's name, so a file may omit `package`, `module`, and `name`. A name that is present must match the path. A type or value inside `module.ion` states its `name`, because the path does not name it.

The header carries `ionVersion`, `formatVersion`, `kind`, `packageName`, and `pathBudget`. Each `package::spec::{ name }` in the manifest names one dependency. The list keeps the dependency order and keeps a dependency that has no modules. A `package::spec` there may also carry inline `modules`, which merge with the `deps/` files. No tree file has a `morphir_footer`. The end of a file ends it.

Under `pkg/`, `module.ion` holds one `public::def::module` or `private::def::module`. A second one is rejected. Under `deps/`, `module.ion` holds `module::spec` fragments, which may repeat and merge. A member stated by two fragments is rejected. A v3 tree has no `deps/`, because the v3 codec does not encode dependencies yet.

A tree reads as the datagram that holds the same elements. The manifest's header comes first, then each dependency, then each module with its children inline, then a footer. In a module directory the module file comes first, then the type files, then the value files, each in path order. Children merge by the single-file rules. A type or value defined twice after the merge is rejected. A tree orders modules and their members by path. That order is the one thing a tree does not keep.

A writer that starts from the IR puts only the module header in `module.ion` and writes one file per type and one file per value. It omits every name the path supplies. When the path budget cuts a stem, the stem ends in `__` and eight hex digits and no longer spells the name, so that file keeps its `name`. A reader checks a stated name against a cut stem by its prefix and hash.

```ion
// pkg/example/finance/eligibility/module.ion
public::def::module::{
  doc: "Credit eligibility.",
}

public::def::alias::type::{
  name: "decision",
  typeExp: "morphir/SDK:basics#int",
}
```

```ion
// pkg/example/finance/eligibility/score.type.ion
public::def::alias::type::{
  typeExp: "morphir/SDK:basics#int",
}
```

The compatibility kit's profile list stays `json` and `yaml`. The Ion tree is storage.

## Out of scope

A package specification has no `annotations` member. Whether v4 should add one is [issue 944](https://github.com/finos/morphir/issues/944).
