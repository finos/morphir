---
title: Project toolchain request 0.1.0-draft.1
sidebar_label: Toolchain request
status: draft
---

# Project toolchain request 0.1.0-draft.1

A project checks in `.morphir/toolchain.toml`, a [TOML 1.0.0](https://toml.io/en/v1.0.0) document, to say which host and toolset it wants. The request names a channel or an exact host release; the [lock](./toolchain-lock.md) records what that resolved to. Version authority: this page. Schema: [toolchain-request-0.1.0-draft.1.schema.json](/schemas/toolchain-request-0.1.0-draft.1.schema.json), applied to the JSON value the TOML parses to.

```toml
schemaVersion = "0.1.0-draft.1"
[host]
implementation = "dotnet"
deployment = "native-aot"
channel = "stable"
[toolset]
preset = "fsharp"
```

The file is separate from `morphir.toml`. Existing `[toolchain.<name>]` sections there define task adapters and keep their meaning; a manager never reads them as a host selection.

## Members

| Member | Required | Meaning |
| --- | --- | --- |
| `schemaVersion` | yes | Exactly `0.1.0-draft.1` |
| `critical` | no | Member paths a reader must understand |
| `platforms` | no | Unique platform ids to prepare closures for. Without it, setup resolves the current platform |
| `host.implementation` | yes | Implementation token, such as `dotnet` |
| `host.deployment` | yes | Deployment token, such as `native-aot`, `self-contained`, `framework-dependent` or `dotnet-tool` |
| `host.channel` | one of | `stable`, `preview`, `insiders` or `preview/<segment>`, as in tool release metadata v1 |
| `host.version` | one of | An exact host release |
| `toolset.preset` | yes | Preset token, such as `fsharp` |
| `toolset.providers` | no | Explicit provider choices, at most one per operation |

`host` has exactly one of `channel` and `version`; both or neither is `inconsistent_document`. Each `toolset.providers` entry has `operation` (`compile` with `language`, or `generate` with `target`), at least one of `delivery` and `extensionId`, and optionally `abi` with the `wasm` delivery. A second entry for the same operation, an entry with neither `delivery` nor `extensionId`, or an `abi` without the `wasm` delivery is `inconsistent_document`. An explicit choice always wins over a built-in, and it is the only way to select a provider other than the recipe's first for its operation (see [selecting a closure](./toolset-recipe.md#selecting-a-closure)):

```toml
[[toolset.providers]]
operation = "generate"
target = "fsharp"
delivery = "process"
```

Understood critical paths: `schemaVersion`, `critical`, `platforms`, `host`, `host.implementation`, `host.deployment`, `host.channel`, `host.version`, `toolset`, `toolset.preset`, `toolset.providers`, `toolset.providers.operation`, `toolset.providers.language`, `toolset.providers.target`, `toolset.providers.delivery`, `toolset.providers.extensionId`, `toolset.providers.abi`.

## Identity

The request's identity is the SHA-256 of the file's exact UTF-8 bytes. Nothing is canonicalized first. Reformatting the file, even adding a blank line, changes its identity, so a lock bound to the old bytes refuses it with `request_changed` until an explicit setup or update writes a new lock. This avoids defining canonical TOML across languages.

A reader refuses bytes that are not UTF-8 or not TOML with `invalid_document`. Writers emit TOML 1.0.0 only. Additions in later TOML versions, such as newlines inside inline tables or the `\e` and `\xHH` escapes, are not part of this contract, and a reader may refuse them; no fixture uses them.

## Fixtures

`fixtures/0.1.0-draft.1/request/` holds the approved example, a team request with two platforms and an explicit external backend, an exact host version, unknown optional members, an understood critical path, a reformatted copy of the approved example, and two WASM example requests: one without a choice and one that chooses the `morphir-bytes-v1` ABI. `request/negative/` holds one document per refusal: a later draft, the released `0.1.0`, a non-SemVer version, a missing version, an unknown critical path, both and neither of channel and version, an invalid deployment token, an unknown channel, an unknown delivery, a compile selection without a language, an unknown platform, a duplicate platform, bytes that are not TOML, two choices for one operation, a choice with neither delivery nor identity, an ABI without the `wasm` delivery, and a credential member.