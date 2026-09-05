---
type: Decision Record
title: Hole is an expression; native and external operations are definition bodies
description: "IR v4 keeps Hole as a value expression with an optional expectedType, removes the Native and External expressions, and makes ExternalBody a list of per-target bindings with an optional fallback body so Gleam-style externals encode faithfully."
state: Accepted
decided: 2026-09-04
tags: [ir, ir-v4, encoding, hole, native, external, gleam, mck]
status: draft
---

# Hole is an expression; native and external operations are definition bodies

`Hole` stays a value expression. `Native` and `External` are removed from the value expression union. A native or
foreign operation is always a definition with a `NativeBody` or an `ExternalBody`, and every use site is a
`Reference` to it. `ExternalBody` carries a list of per-target bindings and an optional fallback body.

```yaml
Hole:
  reason:
    UnresolvedReference:
      target: my-org/project:module#deleted-function
  expectedType: morphir/SDK:basics#int      # optional

add:
  Public:
    NativeBody:
      inputTypes: { a: morphir/SDK:basics#int, b: morphir/SDK:basics#int }
      outputType: morphir/SDK:basics#int
      nativeInfo:
        hint: { Arithmetic: {} }

reverse:
  Public:
    ExternalBody:
      inputTypes: { items: { Reference: ["morphir/SDK:list#list", a] } }
      outputType: { Reference: ["morphir/SDK:list#list", a] }
      externals:
        - targetPlatform: erlang
          externalName: "lists:reverse"
        - targetPlatform: javascript
          externalName: "./mylib.mjs#reverse"
      body:                                  # optional fallback, an ordinary expression over inputTypes
        Apply:
          function: { Apply: { function: { Reference: my-org/lists:internal#do-reverse }, argument: { Variable: items } } }
          argument: { List: [] }
```

| Option | Outcome | Why |
| ------ | ------- | --- |
| `Hole` as an expression; `Native`/`External` only as bodies; `ExternalBody` with bindings and a fallback | Chosen | One home for each vocabulary; every operation has a typed definition; Gleam's `@external` with a body encodes without loss |
| Keep the `Native` and `External` expressions | Rejected | `Native` repeats the definition's `nativeInfo` beside an FQName that already names it; `External` inline has no types |
| Keep the expressions, drop the bodies | Rejected | Only a definition is typed, referenceable across modules, and storable as one document-tree file |
| Single-binding `ExternalBody`, as the v4 schema has it | Rejected | Cannot express a function bound to two targets, or a binding with a fallback body |

## Why

The `Native` expression's payload is `{ fqname, nativeInfo }`. It names a definition and copies information that
definition's `NativeBody` already holds, so it can only agree with the definition or be wrong. v3 has no such node:
the SDK's builtins are definitions and their uses are references, which is the model every backend already handles.

The `External` expression's payload is `{ externalName, targetPlatform }`, with no name and no types. Nothing can
say what an inline foreign call takes or returns; lifting it into an `ExternalBody` definition is what gives it a
signature. Every inline use can be lifted.

A `Hole` is different in kind. It stands where an expression should be, and its `expectedType` is what the
surrounding expression expects, which is why the member keeps that name rather than `outputType`.

Gleam, the design's reference language, lets one function carry several `@external` bindings and a body that is the
fallback for targets without one. The single-binding `ExternalBody` in the v4 schema could not encode that, so the
Gleam frontend in morphir-rust would have had to drop either a binding or the fallback.

## Rules

1. `externals` has at least one entry, and `targetPlatform` values are unique within it.
2. `externalName` is one string whose grammar the target defines; the IR does not parse it.
3. `body` is optional. A backend for target T uses the binding for T when present, else `body` when present, else
   reports the definition unavailable for T.
4. A definition with a body and no bindings is an `ExpressionBody`; the two bodies never overlap.
5. `NativeBody` is unchanged and never carries a fallback body.

## Consequences

1. The value expression union shrinks from 21 members to 19 in the reference model; the Rust and Gleam models
   drop the same two variants (morphir-elm never had them).
2. `IncompleteBody.partialBody` is unchanged; a hole inside a body and an incomplete body remain different things.
3. The single-binding `ExternalBody` spelling is accepted on input as a one-entry `externals` list for the window
   of [decision 0006](/decisions/0006-node-member-names-follow-the-schema-with-a-one-release-window.md), then refused.
4. Kit: `values-0009` becomes active with `Hole` as its one canonical fence and loses its `rejected unknown_node`
   fence; `definitions-0007` pins a one-binding `ExternalBody`, a two-binding one with a fallback, and a
   `NativeBody`.
5. The what's-new page drops its `Native` and `External` expression sections and points at the bodies.

## Revisit when

- A target needs per-binding metadata beyond one name string, at which point `externals` entries grow a
  structured member rather than a grammar inside `externalName`.
