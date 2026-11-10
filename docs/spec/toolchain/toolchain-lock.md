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
| `built-in` | `modelInput` |
| `process` | `repositoryId`, `descriptorTarget`, `descriptorSha256`, `artifactTarget`, `artifactSha256`, protocol members |
| `wasm` | `abi` and the `process` members |
| `dotnet-tool` | `repositoryId`, `descriptorTarget`, `descriptorSha256` (the release's extension descriptor, whose claims describe the guest), `packageId`, `command`, `packageTarget`, `packageSha256`, protocol members |

The protocol members are `protocolVersion` and exactly one compatibility member. MEP `0.1` never enables model transport, so it carries `modelInput`. MEP `0.2.0-draft.1` carries one `modelTuple` whose five members are compared exactly, and whose `operation` is `morphir.frontend.compileModel` for `compile` and `morphir.backend.generateModel` for `generate`. Another MEP version is `unsupported_case`.

For a `dotnet-tool` host offering, `hostTarget` names the authenticated package bytes.

Understood critical paths: `schemaVersion`, `critical`, `requestSha256`, `recipe`, `recipe.repositoryId`, `recipe.target`, `recipe.sha256`, `host`, `host.implementation`, `host.version`, `host.deployment`, `platforms`, `platforms.*`, `platforms.*.hostTarget`, `platforms.*.hostSha256`, `platforms.*.providers`, and `platforms.*.providers.<member>` for each provider member above, including `modelTuple.<member>` and `modelInput.<member>` for each tuple and input member. A lock that needs every reader to understand a provider member lists it, for example `platforms.*.providers.modelTuple`.

## Frozen restore

`morphirup restore --locked` reads the request bytes and refuses with `request_changed` when their SHA-256 differs from `requestSha256`. It then takes the closure for the current platform and refuses with `platform_not_locked` when the lock does not record it. A musl machine never takes a glibc closure. Restore never resolves a channel again and never rewrites the lock; explicit setup or update creates or extends a closure.

A lock records each platform's complete dependency closure. A closure with no provider, or a platform whose closure covers different operations from another platform's, is `inconsistent_document`. Two closures never come from independent channel resolutions: setup resolves one recipe and writes every requested platform from it.

### Checking a lock against its recipe

Given the recipe's exact bytes, a lock is refused with `lock_recipe_mismatch` when:

1. the SHA-256 of the recipe bytes differs from `recipe.sha256` (path `recipe.sha256`);
2. the recipe offers no host with the lock's implementation, deployment and version (path `host`);
3. a closure's host artifact is not the offering's artifact for that platform (path `platforms.<id>.hostTarget`);
4. a closure's operations are not exactly the recipe's operations (path `platforms.<id>.providers`);
5. a provider is neither the offering's built-in for its operation nor a recipe provider that fits the host on that platform, in its locked form (path `platforms.<id>.providers[i]`).

## Fixtures

`fixtures/0.1.0-draft.1/lock/approved-fragment.json` is the example above. `two-platforms-bound.json` adds an `osx-arm64` closure and binds `request/approved.toml` by its real digest. `dotnet-tool-host.json` locks a `dotnet-tool` host with the .NET tool frontend and binds `request/critical-understood-member.toml`. `critical-nested-provider-member.json` names a provider member as critical. `lock/negative/` covers a later draft, an unknown critical member and an unknown nested critical member, a drive path, a rooted path, a traversing path, a device-name component, a component ending in `.`, a path over 240 code units, a line separator, an uppercase digest, a short digest, an unknown platform key, no platforms, an empty closure, a closure missing an operation, a process provider without its artifact digest, an unknown delivery, two providers for one operation, a non-SemVer version, a WASM provider without an ABI and a credential member. The signed fixtures add the frozen locks and the `lockRecipe` cases.