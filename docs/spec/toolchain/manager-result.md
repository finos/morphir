---
title: morphirup JSON result 0.1.0-draft.1
sidebar_label: Manager result
status: draft
---

# morphirup JSON result 0.1.0-draft.1

With `--json`, a `morphirup` command writes exactly one result document to standard output. Progress and logs go to standard error.

The exit status is `0` when the outcome is `planned` or `succeeded`, and `1` when it is `failed`. A command line the manager cannot parse (an unknown option, a missing argument) exits `2` and writes no result, only a usage message on standard error. An internal error, a defect in the manager or an exhausted resource, exits `3` with nothing on standard output and the error on standard error, so a script never mistakes it for a usage error or for a failed result. `morphirup --version` prints only the manager's version, in canonical SemVer, and a line feed on standard output and exits `0`; it writes no result, even with `--json`. A command that runs but cannot read a document it needs, such as an absent project lock for `restore --locked`, fails with `document_unavailable` (`unsupported-contract`, with `document` and the empty `path`; `result/restore-document-unavailable.json`). Version authority: this page. Schema: [morphirup-result-0.1.0-draft.1.schema.json](/schemas/morphirup-result-0.1.0-draft.1.schema.json).

## Members

| Member | Meaning |
| --- | --- |
| `command` | `setup`, `restore`, `update`, `show`, `doctor`, `list`, `default`, `rollback`, `repair`, `remove`, `self-update` or `env`. `run` passes the selected host's own output through and writes no result |
| `outcome` | `planned`, `succeeded` or `failed` |
| `plan`, `planSha256` | A setup or update plan and its digest |
| `selection` | For `show`: the selected `generationId`, `platform`, `host` and optional `lockSha256` (a SHA-256), with its `source` |
| `diagnostics` | Every diagnostic, possibly empty |

`outcome` is `failed` exactly when a diagnostic has `severity` `error`. `planned` carries a plan and no error. A mismatch is `inconsistent_document` at `outcome`.

`selection.source.kind` is `cli`, `environment` (`MORPHIRUP_TOOLCHAIN`), `project` with the absolute [local path](./index.md#local-paths) of the request, or `user-default`, in that precedence order.

The command-line selector (`--toolchain <value>`) and `MORPHIRUP_TOOLCHAIN` both take a generation id, the receipt's `generationId`: they select an installed complete generation and never name a channel, a version or a request. `selection.generationId` is that value. A value that is not a valid generation id, or names no installed complete generation for the current platform, fails the command; it does not fall through to the next source. With `MORPHIRUP_TOOLCHAIN=gen-0002`, `show` reports:

```json title="docs/spec/toolchain/fixtures/0.1.0-draft.1/result/show-environment-selection.json"
{
  "schemaVersion": "0.1.0-draft.1",
  "command": "show",
  "outcome": "succeeded",
  "selection": {
    "source": {
      "kind": "environment"
    },
    "generationId": "gen-0002",
    "platform": "win-x64",
    "host": {
      "implementation": "dotnet",
      "version": "1.2.3",
      "deployment": "self-contained"
    }
  },
  "diagnostics": []
}
```

A `project` source is found by [discovery](./toolchain-request.md#discovery).

Understood critical paths: `schemaVersion`, `critical`, `command`, `outcome`, `plan`, `planSha256`, `selection`, `diagnostics`.

## Plans

A plan says everything the command will do and write, so that its digest pins all of it. A plan made without acting, such as the result of plan-only setup, states what the planned command would do when applied: its `metadataRefresh`, for example, is `required` when the applied command would refresh metadata, whatever the plan-only run itself read. It names:

- `implementation`, `deployment` and `platform`: the host offering and the platform it installs now;
- the `recipe`;
- `metadataRefresh`: `required` when the command refreshes the repository metadata before acting, which `setup` and `update` always do unless they run offline, and `not-required` when it runs offline from the verified metadata it holds;
- its `components`: what it installs for `platform`;
- `lock`: the complete [lock](./toolchain-lock.md) the command writes when it succeeds, with every platform's closure, not only `platform`'s. After success the written lock equals `lock` as a parsed value. A setup locks the request's `platforms` together with the platform it runs on, each once, in [platform table](./index.md#platforms) order: a request listing `win-x64` and `osx-arm64`, set up on `linux-x64`, locks all three (binding kind `setup-platforms`).

Because `lock` is inside the plan, `--expect-plan` pins every closure that setup records, for the other platforms too (binding case `plan-lock`). The reader checks the plan against its lock, refusing each mismatch with `inconsistent_document`. The checks run in this order, and the first failure is reported:

1. `lock.recipe` is the plan's `recipe`, at `plan.lock.recipe`.
2. `lock.host` has the plan's implementation and deployment, at `plan.lock.host`.
3. `lock.platforms` records `platform`, at `plan.lock.platforms`.
4. Then each component in index order, all of its checks before the next component's:
   1. A `repository-target` or `recipe-digest` source, the host's included, names the recipe's repository, at `source.repositoryId` (one repository per binding check).
   2. For the host component:
      - its `implementation`, `deployment` and `version` are the lock's host, at `plan.components[i]` (`result/negative/plan-host-component-other-deployment.json`, `-other-implementation.json`, `-other-version.json`);
      - its source kind is `repository-target`, for a release authenticated by its own TUF target, or `external-owner`, at `source` (`plan-host-built-in-source.json`, `plan-host-recipe-digest-source.json`);
      - its source `target` is that platform's host artifact path, at `source.target` (`plan-host-source-other-target.json`);
      - its source `sha256` is that artifact's locked digest, at `source.sha256` (`plan-host-source-other-digest.json`). A source with the right target and the wrong digest is refused at `source.sha256`, not at `source` or `source.target`.

      So a host source of the wrong kind that also names the wrong target is refused at `source`, and one with the wrong target and the wrong digest at `source.target`.
   3. For a provider component:
      - the closure has a provider for its operation, at `plan.components[i].component`;
      - its `extensionId`, `version` and `delivery` are that locked provider, at `plan.components[i]`. Provider components are matched to the lock by operation, so their order in `components` is free (`result/setup-plan-providers-swapped.json` is valid);
      - its source has the kind its delivery allows and names the locked artifact or package, at `source`: `recipe-digest`, because the recipe binds an external provider's bytes by digest, or `external-owner`; `built-in` for a built-in (`result/negative/plan-provider-repository-target-source.json`).
5. There is exactly one host component and one provider component per provider of that closure, at `plan.components`.

`lock` itself follows the lock schema and reader: a refusal inside it carries its path under `plan.lock`.

Each component has:

- `component`: `{ "role": "host", "implementation", "deployment" }` or `{ "role": "provider", "operation", "language" | "target" }`, where a `compile` provider requires `language` and a `generate` provider requires `target`. Diagnostics name components the same way;
- `version`, and for a provider `extensionId` and `delivery`. A provider component without `delivery` or `extensionId`, or a host component with either, is `inconsistent_document` at that member, checked `delivery` first (`result/negative/provider-component-without-extension-id.json`, `host-component-with-extension-id.json`);
- `source`: `repository-target` or `recipe-digest` with `repositoryId`, `target` and `sha256`, or `built-in`, or `external-owner`;
- `downloadBytes`: the authenticated length of the target the component downloads, from the TUF targets metadata, or `0` when it downloads nothing;
- `installedBytes`: the bytes the component occupies once installed. Its source is **deferred**: it will be a recipe member that release assembly writes for each artifact, and it is defined together with the multi-file package form (see [toolset recipe limits](./toolset-recipe.md#limits-of-this-contract-version)), because that form defines what an installed extension is. Until then a manager reports its own measurement, so `installedBytes`, and with it `planSha256`, can differ between two managers for the same inputs;
- `updateOwner`, an ownership case;
- `prerequisites`, possibly empty: the component's prerequisites that apply on the plan's `platform`. They are already filtered, so a plan prerequisite names no `platforms`; one that does is `inconsistent_document` at its `platforms`;
- `probe`: how setup runs the component's code. Setup's readiness runs the staged host to check it and its built-ins, so the host component's `probe` is `process-with-user-rights`. Installation runs `describe` on every `process` guest unless `--no-probe` is given, and readiness runs every `process` and `dotnet-tool` guest; both are `process-with-user-rights`. A `built-in` or `wasm` provider runs inside the host and is `in-host`. `none` names a component setup never runs, and no component of a `0.1.0-draft.1` setup or update plan is one. Any other value is `inconsistent_document`.

All of this is required because a plan's digest covers it: every member of a plan has one fixed value for the same inputs.

### The plan digest

`planSha256` is the SHA-256 of the plan's canonical JSON bytes. `--expect-plan <digest>` compares against it, and a different plan fails with `plan_changed` (`lock-binding`, `document` `result`, `path` `planSha256`; `result/setup-plan-changed.json`) before anything is changed. A result whose `planSha256` does not match its plan is `inconsistent_document` at `planSha256`.

The digest is compared last. The reader first reads the whole plan, including every check of the plan against its lock above and the NFC key check below, and only then computes the canonical bytes and compares `planSha256` with their SHA-256. So a plan that breaks a plan rule and also carries a stale digest is refused at the plan rule (`result/negative/precedence-plan-rule-before-digest.json`, refused at `plan.components[0].source.sha256`, not `planSha256`).

The canonical form is defined by the rules below, and this page is their authority. They are the canonical JSON that tool release metadata v1 uses for repository identity and signatures, and this repository's reference checker produces them with the `olpc-cjson` crate. "OLPC canonical JSON" is not one fixed format across implementations. These rules differ from the canonical JSON of the TUF reference implementations, securesystemslib and go-securesystemslib, in key order and in NFC ([the TUF profile](../tool-release-metadata/index.md#canonical-json-and-the-reference-tuf-implementations) says what that means for signing). Where any library, `olpc-cjson` included, differs from these rules, the rules apply:

- There is no whitespace outside strings.
- A string is converted to Unicode Normalization Form C and written as `"`, its UTF-8 bytes, and `"`. Only `"` and `\` are escaped, as `\"` and `\\`. Every other character is written as its own UTF-8 bytes, with no `\uXXXX` or other escape: `<`, `>`, `&`, `+`, `'`, non-ASCII characters, and the control characters U+0000 to U+001F. A line feed is therefore the single byte `0x0A`, not `\n`, and the canonical bytes are not always valid JSON; they are only hashed.
- An object's members are sorted by the bytes of each key as written by the previous rule, including its enclosing quotation marks, compared byte by byte as unsigned values. Because the closing `"` is part of the comparison, `"a!"` sorts before `"a"` (`!` is `0x21`, `"` is `0x22`), and the order is UTF-8 byte order, not UTF-16 code-unit order: U+FF76 sorts before U+1D11E. Keys are normalized before they are sorted. Two member names of one object that differ but have the same NFC form, such as a precomposed `é` and `e` followed by U+0301, would encode as one key. So the reader refuses such a plan before computing its digest, with `invalid_document` at that object (`result/negative/plan-key-collision.json`).
- A number is an integer written in plain decimal. A number with a fraction or an exponent cannot be encoded, and a plan with one is invalid; the reader refuses it before the digest is computed, because every integer member of a result is written that way (see [numbers](./index.md#numbers)).
- `true`, `false` and `null` are written as such.

**NFC and the plan digest.** Because strings are normalized, two plans whose text differs only in NFC-equivalent spelling have one digest. The TUF profile refuses that for signed metadata, because there a signature from one party must authenticate the exact text another party serves ([signed text](../tool-release-metadata/index.md#signed-text)). A plan is different, and nothing changes for it:

- the manager makes it from authenticated inputs;
- `--expect-plan` compares two digests the same manager computed;
- every member of a plan that selects bytes is a SHA-256, a target path that must already be NFC, or an ASCII token.

So two plans with one digest install the same artifacts, and can differ only in text no check reads, such as an unknown member. `result/setup-plan-escaping.json` keeps its decomposed `é` to pin the normalization.

The `canonical-json` binding cases pin the encoding on its own: for each key pair whose order differs from the reference TUF implementations' and for a decomposed string, they give the expected canonical text, and beside it, as `referenceTuf`, what securesystemslib 1.6.0 writes. `result/setup-plan-key-order.json` is a plan carrying both key pairs, with its canonical bytes in `setup-plan-key-order.plan.canonical.json`.

**Unicode normalization (decided 9 November 2026, [finos/morphir#1146](https://github.com/finos/morphir/issues/1146#issuecomment-6760173619)).** NFC here is Unicode Normalization Form C as defined by **Unicode 17.0.0**: its canonical decompositions, canonical combining classes and composition exclusions, and the Hangul algorithm. A manager ships its own normalization data of that version. It does not use the machine's ICU, which a Native AOT executable may not find, which may silently skip normalization, and whose version varies, so a digest is the same on every machine.

- A code point that Unicode 17.0.0 does not assign passes through unchanged with combining class 0. It is a starter, so no mark is reordered across it and nothing composes with it.
- U+FFFE, a noncharacter but a valid scalar value, is the same: it passes through unchanged and is never refused. .NET's `string.Normalize` throws on it, so an implementation built on that method must normalize around it.
- A later Unicode version is adopted only by a new draft of these contracts.

The `nfc` binding cases pin the version. They cover:

- compositions that exist only since Unicode 16.0 (Kirat Rai `U+16D67 U+16D67`, and Todhri `U+105D2 U+0307`);
- reorderings by marks first assigned in Unicode 16.0 (Garay `U+10D69`) and 17.0 (Tai Yo `U+1E6E3`);
- Hangul jamo, and a Hangul syllable with a trailing jamo;
- a string already in NFC, a decomposed `é`, and an unassigned code point;
- U+FFFE.

An implementation with older data treats the 16.0 and 17.0 characters as unassigned and fails those cases. The 17.0 case is a reordering, because a mark first assigned in 17.0 is observable under NFC through its combining class.

This repository's reference checker normalizes with the `unicode-normalization` crate 0.1.25 (in `Cargo.lock`), whose tables are Unicode 17.0.0 (`UNICODE_VERSION = (17, 0, 0)` in its `tables.rs`).

Many JSON libraries escape by default: .NET's `System.Text.Json` writes `>` as `>` and a line feed as `\n`, and .NET's ordinal string comparison orders by UTF-16 code units. An implementation must configure or write its own encoder. `fixtures/0.1.0-draft.1/result/setup-plan-escaping.json` has a plan whose strings contain `>`, `<`, `&`, `+`, a precomposed `é`, a decomposed `e` followed by U+0301, a line feed, `"` and `\`, and an unknown `keyOrder` member whose keys (`a`, `a!`, a decomposed `é`, U+FF76, U+1D11E and `Z`) pin the key order. `setup-plan-escaping.plan.canonical.json` holds its exact canonical bytes, and `planSha256` is their SHA-256.

## Diagnostics

Every diagnostic has `kind`, `code`, `severity` (`error` or `warning`), a human `message` and an optional `instruction`, a non-empty argument vector such as `["dotnet", "tool", "update", "--global", "Morphir.Tool"]`. Its `code` is a [stable code](./index.md#stable-codes) of its kind; a code of another kind is `inconsistent_document` at `code`, and an unknown code is `unsupported_case`. The kinds keep the failure categories apart:

| `kind` | Codes | Required members | Optional members |
| --- | --- | --- | --- |
| `unsupported-artifact` | `unsupported_artifact`, `abi_unavailable`, `no_compatible_release` | `component`, `platform`; `abi` exactly for `abi_unavailable` | `alternatives` (`implementation`, `deployment`, `platform`); `document` and `path` |
| `missing-prerequisite` | `missing_prerequisite` | `component`, `prerequisite` | `alternatives` |
| `trust-failure` | `target_not_authenticated`, `target_length_mismatch`, `target_digest_mismatch`, `release_descriptor_mismatch`, `artifact_platform_mismatch`, `repository_mismatch`, `release_revoked`, the `metadata_*` codes, `offline_metadata_unavailable`, `repository_unavailable` | `repositoryId` | `role` (`root`, `timestamp`, `snapshot`, `targets`), `target`, `mirror`; `document` and `path` |
| `offline-content-unavailable` | `offline_content_unavailable` | `component`, `target`, `sha256` | |
| `ownership-conflict` | `ownership_conflict` | `component`, `ownership` | |
| `readiness-failed` | `readiness_failed` | `component`, `check`, `readiness` | |
| `unsupported-contract` | the eight reader codes and `document_unavailable` | `document` (`request`, `lock`, `recipe`, `receipt`, `result`), `path` | |
| `selection-unavailable` | `generation_not_installed` | `source` | |
| `lock-binding` | `request_changed`, `platform_not_locked`, `lock_changed`, `receipt_lock_mismatch`, `lock_recipe_mismatch`, `plan_changed` | `document`, `path`; `platform` exactly for `platform_not_locked` | `cause`, only for `request_changed` |

An `unsupported-artifact` or `trust-failure` diagnostic that a check of one document reported names that member with `document` and `path`, as `unsupported-contract` diagnostics do. So a binding check's `repository_mismatch` says which provider named the wrong repository (`result/setup-provider-repository-mismatch.json`, `document` `recipe`, `path` `providers[2].repositoryId`), and a resolution refusal says which request member it concerns (`result/setup-choice-unsupported.json`, `path` `toolset.providers[1]`). A refusal of the request's preset names the host component, because no provider is involved (`result/setup-preset-unsupported.json`, `path` `toolset.preset`). `document` and `path` come together: one without the other is `inconsistent_document` at the one present (`result/negative/diagnostic-path-without-document.json`). A diagnostic about no single document, such as an expired timestamp, has neither.

A `lock-binding` diagnostic's `document` is the document whose member its `path` names, so each code reports a fixed `document`, and another `document` is `inconsistent_document` at `document` (`result/negative/lock-binding-other-document.json`):

| `code` | `document` | `path` | Fixture |
| --- | --- | --- | --- |
| `request_changed` | `lock` | `requestSha256` | `restore-request-changed.json` |
| `platform_not_locked` | `lock` | `platforms`, with `platform` naming the missing platform | `restore-platform-not-locked.json` |
| `lock_changed` | `receipt` | `lockSha256` | `repair-lock-changed.json` |
| `receipt_lock_mismatch` | `receipt` | the receipt member, such as `providers[0].identity` | `repair-receipt-lock-mismatch.json` |
| `lock_recipe_mismatch` | `lock` | the lock member, such as `platforms.win-x64.providers[0]` | `restore-lock-recipe-mismatch.json` |
| `plan_changed` | `result` | `planSha256` | `setup-plan-changed.json` |

A `request_changed` diagnostic may carry `cause`, when the request bytes differ from the locked ones only by encoding: `crlf-line-endings` (converting CRLF to LF gives the locked bytes), `byte-order-mark` (removing a leading UTF-8 byte order mark does), or `crlf-line-endings-and-byte-order-mark` (both). Its message then names the cause and the `.gitattributes` entry that prevents it (`result/restore-request-changed-crlf.json`). Only `request_changed` has `cause`; another code with it is `inconsistent_document` at `cause`.

Only `platform_not_locked` has `platform`. A `lock-binding` diagnostic with `platform` and another code, or `platform_not_locked` without it, is `inconsistent_document` at its `platform`, and the schema refuses both. `abi` on any code but `abi_unavailable` is `inconsistent_document` at `abi`. A `document_unavailable` diagnostic concerns a document that was never read, so its `path` is empty; another path is `inconsistent_document` at `path`. A result with `plan` and without `planSha256` is `invalid_document` at `planSha256`, a required member being absent; a `planSha256` without `plan` is `inconsistent_document` at `planSha256`. A diagnostic without `code` is `invalid_document` at its `code`. A `readiness-failed` diagnostic reports the readiness reached, which is below the state its failed check would reach. A `mirror` carries no user information, query or fragment. No result carries a secret value.

## Fixtures

`fixtures/0.1.0-draft.1/result/` holds an AOT F# setup plan with its digest, the escaping plan and its canonical bytes, two `show` results explaining a project selection and a `MORPHIRUP_TOOLCHAIN` selection, an offline restore missing a locked archive, a `doctor` result with a diagnostic of every kind, one failed result for each `lock-binding` code in the table above, a `request_changed` naming CRLF line endings as its cause, a restore whose lock is absent (`document_unavailable`), the setup plan with its provider components in the other order, a `repository_mismatch` and two `unsupported_artifact` refusals that name the document member they concern. The plans carry `lock/two-platforms-bound.json` as their `lock`. `result/negative/` covers:

- a plan without `lock`, a lock that does not record the plan's platform, a lock for another recipe, a provider component that is not the locked provider, a source from another repository, a host and a built-in whose `probe` is `none`, and a plan prerequisite that names platforms;
- a host component of another deployment, implementation or release than the lock's, a provider with a `repository-target` source, a host with a `built-in` source, a host source naming another target, and one naming the locked target with another digest;
- a plan that breaks a plan rule and carries a stale `planSha256`, refused at the plan rule (`precedence-plan-rule-before-digest.json`);
- a diagnostic `path` without `document`, a `lock-binding` diagnostic with another document, `platform_not_locked` without `platform`, `abi` on another code, a `document_unavailable` with a path, a `critical` that is not an array, a plan without `planSha256` and a `planSha256` without a plan;
- `cause` on a code other than `request_changed`;

- a later draft, an unknown critical member, an unknown command and an unknown diagnostic kind;
- a diagnostic without a code, and a `lock-binding` diagnostic with `platform` on another code;
- a provider component without `extensionId`, a host component with one, a component without `prerequisites`, a provider component without `language`, a `dotnet-tool` ownership without `scope`, and a `runtime` prerequisite without `versions`;
- `downloadBytes` written as `41943040.0` and as `1e3`;
- mirrors carrying user information or a query;
- a succeeded outcome with an error, a failed outcome without one, and a planned outcome without a plan;
- an unknown code, a code of another kind, and `abi_unavailable` without `abi`;
- an offline diagnostic without a digest, an empty instruction, and a failed check that reports the state it failed to reach;
- relative and traversing project paths, and a `lockSha256` that is not a digest;
- a plan digest that does not match, a provider component without a delivery, and a process provider whose probe is `none`.
