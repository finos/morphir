---
title: Portable toolchain lock 0.1.0-draft.1
sidebar_label: Portable lock
status: draft
---

# Portable toolchain lock 0.1.0-draft.1

`.morphir/toolchain.lock.json` is the exact resolution of a [request](./toolchain-request.md). It is checked in beside the request and contains no absolute path and no credential. Version authority: this page. Schema: [toolchain-lock-0.1.0-draft.1.schema.json](/schemas/toolchain-lock-0.1.0-draft.1.schema.json).

The approved example records one platform. Digests and versions are synthetic:

```json
{
  "schemaVersion": "0.1.0-draft.1",
  "critical": ["host", "platforms"],
  "requestSha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "recipe": {
    "repositoryId": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "target": "toolchains/recipes/fsharp/1.0.0.json",
    "sha256": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
  },
  "host": { "implementation": "dotnet", "version": "1.2.3", "deployment": "native-aot" },
  "platforms": {
    "win-x64": {
      "hostTarget": "artifacts/morphir-dotnet-native-aot/1.2.3/win-x64.zip",
      "hostSha256": "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
      "providers": [
        {
          "operation": "compile",
          "language": "fsharp",
          "delivery": "process",
          "extensionId": "org.finos.morphir.fsharp-frontend",
          "version": "0.6.0",
          "repositoryId": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          "descriptorTarget": "extensions/fsharp-frontend/0.6.0/release.json",
          "descriptorSha256": "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
          "artifactTarget": "extensions/fsharp-frontend/0.6.0/win-x64.zip",
          "artifactSha256": "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
          "protocolVersion": "0.2.0-draft.1",
          "modelTuple": {
            "operation": "morphir.frontend.compileModel",
            "profile": "morphir-ir",
            "codec": "morphir-json",
            "envelopeVersion": "0.1.0-draft.1",
            "irVersion": "4.0.0"
          }
        },
        {
          "operation": "generate",
          "target": "fsharp",
          "delivery": "built-in",
          "extensionId": "morphir.fsharp",
          "version": "1.2.3",
          "modelInput": { "profile": "morphir-ir", "codec": "morphir-json", "irVersion": "4.0.0" }
        }
      ]
    }
  }
}
```

## Members

| Member | Meaning |
| --- | --- |
| `requestSha256` | SHA-256 of the exact request bytes the lock was resolved from |
| `recipe` | The authenticated recipe: `repositoryId` (SHA-256 of the canonical initial root `signed` object, as in tool release metadata v1), `target` and `sha256` |
| `host` | The exact `implementation`, `version` and `deployment`, the same on every platform |
| `platforms` | At least one closure, keyed by platform id |
| `platforms.<id>.hostTarget`, `hostSha256` | The authenticated host artifact for that platform |
| `platforms.<id>.providers` | One provider per required operation. Never empty, and every platform has a provider for the same set of operations |

Each provider has `operation` (`compile` with `language`, or `generate` with `target`), `delivery`, `extensionId` and `version`, plus the identities its delivery needs:

| `delivery` | Additional members |
| --- | --- |
| `built-in` | `modelOutput` for `compile` and `modelInput` for `generate`: the model the built-in writes or reads. The other member is `inconsistent_document` |
| `process` | `repositoryId`, `descriptorTarget`, `descriptorSha256`, `artifactTarget`, `artifactSha256`, protocol members |
| `wasm` | `abi` and the `process` members |
| `dotnet-tool` | `repositoryId`, `descriptorTarget`, `descriptorSha256` (the release's extension descriptor, whose claims describe the guest), `packageId`, `command`, `packageTarget`, `packageSha256`, protocol members |

The protocol members are `protocolVersion` and exactly one compatibility member. MEP `0.1` never enables model transport, so it carries `modelInput`. MEP `0.2.0-draft.1` carries one `modelTuple` whose five members are compared exactly, and whose `operation` is `morphir.frontend.compileModel` for `compile` and `morphir.backend.generateModel` for `generate`. Another MEP version is `unsupported_case`.

For a `dotnet-tool` host offering, `hostTarget` names the authenticated package bytes.

Understood critical paths: `schemaVersion`, `critical`, `requestSha256`, `recipe`, `recipe.repositoryId`, `recipe.target`, `recipe.sha256`, `host`, `host.implementation`, `host.version`, `host.deployment`, `platforms`, `platforms.*`, `platforms.*.hostTarget`, `platforms.*.hostSha256`, `platforms.*.providers`, and `platforms.*.providers.<member>` for each provider member above, including `modelTuple.<member>`, `modelInput.<member>` and `modelOutput.<member>` for each tuple and model member. A lock that needs every reader to understand a provider member lists it, for example `platforms.*.providers.modelTuple`. A platform is named only by `*`: `platforms.win-x64.hostTarget` is not an understood path and is refused with `unsupported_critical_member` (`lock/negative/critical-concrete-platform-key.json`).

## Frozen restore

`morphirup restore --locked` never resolves a channel again and never rewrites the lock; explicit setup or update creates or extends a closure. It checks, in this order:

| Check | Code | Path | Cases |
| --- | --- | --- | --- |
| The SHA-256 of the request bytes equals `requestSha256` | `request_changed` | `requestSha256` | `lock-request` |
| The lock records a closure for the current platform. A musl machine never takes a glibc closure | `platform_not_locked` | `platforms` | `lock-platform` |

A lock records each platform's complete dependency closure. A closure with no provider is `inconsistent_document` at its `providers`. Closures that cover different operations from each other are `inconsistent_document` at `platforms`: the rule relates the closures to each other, so no single platform is named (`lock/negative/closure-operations-differ.json`). Two closures never come from independent channel resolutions: setup resolves one recipe and writes every requested platform from it.

### Checking a lock against its recipe

Given the recipe's exact bytes, a lock is refused with `lock_recipe_mismatch` at the first failure of these checks, in this order. The closures are visited in [platform table order](./index.md#order-of-checks), and for each closure the host artifact, then the operations, then each provider in index order (its repository, then its identity):

| Check | Code | Path | Cases |
| --- | --- | --- | --- |
| The SHA-256 of the recipe bytes equals `recipe.sha256` | `lock_recipe_mismatch` | `recipe.sha256` | `lock-recipe-bytes` |
| `recipe.repositoryId` is the identity of the authenticated repository the recipe bytes were read from | `repository_mismatch` | `recipe.repositoryId` | `lock-recipe-repository` |
| The recipe offers a host with the lock's implementation, deployment and version | `lock_recipe_mismatch` | `host` | `lock-recipe-host` |
| A closure's host artifact is the offering's artifact for that platform | `lock_recipe_mismatch` | `platforms.<id>.hostTarget` | `lock-recipe-host-artifact` |
| A closure's operations are exactly the recipe's operations | `lock_recipe_mismatch` | `platforms.<id>.providers` | `lock-recipe-operations` |
| Each provider's `repositoryId`, when its delivery has one, is that same repository identity | `repository_mismatch` | `platforms.<id>.providers[i].repositoryId` | `lock-provider-repository` |
| Each provider is the offering's built-in for its operation or a recipe provider that fits the host on that platform, in its locked form | `lock_recipe_mismatch` | `platforms.<id>.providers[i]` | `lock-recipe-provider` |

The two repository rows apply the [one repository per binding check](./toolset-recipe.md#one-repository-per-binding-check) rule: a lock resolved from a recipe names that recipe's repository, and so does every provider in it.

## Fixtures

`fixtures/0.1.0-draft.1/lock/approved-fragment.json` is the example above. `two-platforms-bound.json` adds an `osx-arm64` closure and binds `request/approved.toml` by its real digest. `dotnet-tool-host.json` locks a `dotnet-tool` host with the .NET tool frontend and binds `request/critical-understood-member.toml`. `critical-nested-provider-member.json` names a provider member as critical. `target-path-512-utf8-bytes.json` and `target-path-240-utf16-units.json` hold host targets exactly at the [target path](./index.md#target-paths) byte and code-unit limits, written with non-ASCII characters. `lock/negative/` covers:

- a later draft, an unknown critical member, an unknown nested critical member, a concrete platform key named as critical and a repeated critical path;
- a drive path, a rooted path, a traversing path, a device-name component, a component ending in `.`, a path over 240 code units, a line separator, and non-ASCII paths one past each limit: 513 UTF-8 bytes, 241 UTF-16 code units, and a 256-byte component;
- an uppercase digest, a short digest, an unknown platform key, no platforms, an empty closure, a closure missing an operation (two variants), a process provider without its artifact digest, a `dotnet-tool` provider without its descriptor, an unknown delivery, two providers for one operation, a non-SemVer version and a WASM provider without an ABI;
- credential members (`authorization`, and a mixed-case `Authorization`);
- documents that break two rules at once (`precedence-*.json`), described under [order of checks](./index.md#order-of-checks).

The signed fixtures add the frozen locks and the `lockRecipe` cases, with one negative lock for each check above.