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
| `platforms.<id>.providers` | One provider per required operation |

Each provider has `operation` (`compile` with `language`, or `generate` with `target`), `delivery`, `extensionId` and `version`, plus the identities its delivery needs:

| `delivery` | Additional members |
| --- | --- |
| `built-in` | `modelInput` |
| `process` | `repositoryId`, `descriptorTarget`, `descriptorSha256`, `artifactTarget`, `artifactSha256`, protocol members |
| `wasm` | `abi` and the `process` members |
| `dotnet-tool` | `repositoryId`, `packageId`, `command`, `packageTarget`, `packageSha256`, protocol members |

The protocol members are `protocolVersion` and exactly one compatibility member. MEP `0.1` never enables model transport, so it carries `modelInput`. MEP `0.2.0-draft.1` carries one `modelTuple` whose five members are compared exactly, and whose `operation` is `morphir.frontend.compileModel` for `compile` and `morphir.backend.generateModel` for `generate`. Another MEP version is `unsupported_case`.

For a `dotnet-tool` host offering, `hostTarget` names the authenticated package bytes.

Understood critical paths: `schemaVersion`, `critical`, `requestSha256`, `recipe`, `recipe.repositoryId`, `recipe.target`, `recipe.sha256`, `host`, `host.implementation`, `host.version`, `host.deployment`, `platforms`. Platform keys are data, so paths below `platforms` are not addressable.

## Frozen restore

`morphirup restore --locked` reads the request bytes and refuses with `request_changed` when their SHA-256 differs from `requestSha256`. It then takes the closure for the current platform and refuses with `platform_not_locked` when the lock does not record it. A musl machine never takes a glibc closure. Restore never resolves a channel again and never rewrites the lock; explicit setup or update creates or extends a closure.

A lock records each platform's complete dependency closure. Two closures never come from independent channel resolutions: setup resolves one recipe and writes every requested platform from it.

## Fixtures

`fixtures/0.1.0-draft.1/lock/approved-fragment.json` is the example above. `two-platforms-bound.json` adds an `osx-arm64` closure and binds `request/approved.toml` by its real digest; the binding cases use it. `lock/negative/` covers a later draft, an unknown critical member, a drive path, a rooted path, a traversing path, an uppercase digest, a short digest, an unknown platform key, no platforms, a process provider without its artifact digest, an unknown delivery, two providers for one operation, a non-SemVer version and a WASM provider without an ABI.
