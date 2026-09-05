---
type: Decision Record
title: Parameters are declared and arguments are applied
description: "IR v4 names a declared slot a parameter and an applied value an argument: a Function type has a parameterType, constructors have parameters, while Apply, Reference and Annotation keep their arguments; the input naming on definitions stays."
state: Accepted
decided: 2026-09-04
tags: [ir, ir-v4, encoding, vocabulary, parameters, arguments]
status: draft
---

# Parameters are declared and arguments are applied

v4 uses "parameter" for a slot a definition declares and "argument" for a value applied to a slot. Two names that
broke that rule are corrected:

- The `Function` type expression has `parameterType` and `returnType`.
- Custom type constructors declare `parameters` (morphir-elm's `ConstructorArgs`), and the reference model and every
  mirror name them so. The JSON stays a bare list of `[name, type]` pairs, so no bytes change.

```yaml
Function:
  parameterType: morphir/SDK:basics#int
  returnType: morphir/SDK:string#string
```

| Member | Side | Verdict |
| ------ | ---- | ------- |
| `Apply.argument` | value applied | kept |
| `Reference.args` (type arguments applied to a type constructor) | applied | kept |
| `Annotation.arguments` | applied | kept |
| `typeParams` | declared | kept |
| `Function.argumentType` | declared | renamed to `parameterType` |
| constructor `args` | declared | named `parameters` in models |
| `inputTypes`, `outputType`, `inputs`, `output` | declared | kept; "input" is a third vocabulary, not the confusion, and it is the name morphir-elm and the Scala runtime use |

| Option | Outcome | Why |
| ------ | ------- | --- |
| Correct the two misuses, keep the input naming | Chosen | Fixes the confusion where it exists; avoids reshaping every value definition in every file |
| Rename `inputTypes`/`inputs` to `parameters` as well | Rejected | One vocabulary everywhere, at the cost of the largest rename discussed and a drift from morphir-elm |
| Leave everything as inherited | Rejected | v4 is the one release where a rename costs nothing downstream |

## Why

A function type describes what a function accepts, which is its declaration side; calling that an argument type
mislabels it. morphir-elm's `Function a argType returnType` and its `ConstructorArgs` alias inherited the common
confusion, and the v4 schema copied `argumentType` from them. The other `arg` members in v4 are on the application
side and are correct.

## Consequences

1. `argumentType` is accepted on input for the one-release window of [decision 0006](/decisions/0006-node-member-names-follow-the-schema-with-a-one-release-window.md), then refused.
2. The kit's `types-0007` canonical fence changes to `parameterType`; `argumentType` joins its accepted fences for the
   window.
3. The reference model renames `Type.Function.argumentType` and `Constructor.args`; mirrors follow through the kit.
4. The v4 schema and the specification pages are updated to the new names.

## Revisit when

- A later version renames the definition-side `inputTypes`/`outputType` family, at which point the parameter
  vocabulary should be applied there too.
