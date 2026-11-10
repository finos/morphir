---
title: morphirup JSON result 0.1.0-draft.1
sidebar_label: Manager result
status: draft
---

# morphirup JSON result 0.1.0-draft.1

With `--json`, a `morphirup` command writes exactly one result document to standard output. Progress and logs go to standard error. Version authority: this page. Schema: [morphirup-result-0.1.0-draft.1.schema.json](/schemas/morphirup-result-0.1.0-draft.1.schema.json).

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

Understood critical paths: `schemaVersion`, `critical`, `command`, `outcome`, `plan`, `planSha256`, `selection`, `diagnostics`.

## Plans

A plan names `implementation`, `deployment`, `platform`, the `recipe`, whether `metadataRefresh` is `required` or `not-required`, and its `components`. Each component has:

- `component`: `{ "role": "host", "implementation", "deployment" }` or `{ "role": "provider", "operation", "language" | "target" }`;
- `version`, and for a provider `extensionId` and `delivery`. A provider component without `delivery`, or a host component with one, is `inconsistent_document`;
- `source`: `repository-target` or `recipe-digest` with `repositoryId`, `target` and `sha256`, or `built-in`, or `external-owner`;
- `downloadBytes`, `installedBytes`, `updateOwner` (an ownership case) and `prerequisites`;
- `probe`: `none`, `in-host`, or `process-with-user-rights`. A `process` or `dotnet-tool` provider's readiness probe runs acquired code with the user's rights, so its `probe` is `process-with-user-rights`, and no other component's is. Anything else is `inconsistent_document`.

### The plan digest

`planSha256` is the SHA-256 of the plan's canonical JSON bytes. `--expect-plan <digest>` compares against it and refuses a different plan. A result whose `planSha256` does not match its plan is `inconsistent_document` at `planSha256`.

The canonical form is the OLPC canonical JSON encoding of the `olpc-cjson` encoder that the TUF client uses, which tool release metadata v1 already uses for repository identity. "OLPC canonical JSON" is not one fixed format across implementations, so the rules below govern; where another canonical JSON library differs from them, these rules apply:

- There is no whitespace outside strings.
- A string is converted to Unicode Normalization Form C and written as `"`, its UTF-8 bytes, and `"`. Only `"` and `\` are escaped, as `\"` and `\\`. Every other character is written as its own UTF-8 bytes, with no `\uXXXX` or other escape: `<`, `>`, `&`, `+`, `'`, non-ASCII characters, and the control characters U+0000 to U+001F. A line feed is therefore the single byte `0x0A`, not `\n`, and the canonical bytes are not always valid JSON; they are only hashed.
- An object's members are sorted by the bytes of each key as written by the previous rule, including its enclosing quotation marks, compared byte by byte as unsigned values. Because the closing `"` is part of the comparison, `"a!"` sorts before `"a"` (`!` is `0x21`, `"` is `0x22`), and the order is UTF-8 byte order, not UTF-16 code-unit order: U+FF76 sorts before U+1D11E. Keys are normalized before they are sorted.
- A number is an integer written in plain decimal. A number with a fraction or an exponent cannot be encoded, and a plan with one is invalid; the reader refuses it before the digest is computed, because every integer member of a result is written that way (see [numbers](./index.md#numbers)).
- `true`, `false` and `null` are written as such.

Many JSON libraries escape by default: .NET's `System.Text.Json` writes `>` as `>` and a line feed as `\n`, and .NET's ordinal string comparison orders by UTF-16 code units. An implementation must configure or write its own encoder. `fixtures/0.1.0-draft.1/result/setup-plan-escaping.json` has a plan whose strings contain `>`, `<`, `&`, `+`, a precomposed `é`, a decomposed `e` followed by U+0301, a line feed, `"` and `\`, and an unknown `keyOrder` member whose keys (`a`, `a!`, a decomposed `é`, U+FF76, U+1D11E and `Z`) pin the key order. `setup-plan-escaping.plan.canonical.json` holds its exact canonical bytes, and `planSha256` is their SHA-256.

## Diagnostics

Every diagnostic has `kind`, `code`, `severity` (`error` or `warning`), a human `message` and an optional `instruction`, a non-empty argument vector such as `["dotnet", "tool", "update", "--global", "Morphir.Tool"]`. Its `code` is a [stable code](./index.md#stable-codes) of its kind; a code of another kind is `inconsistent_document` at `code`, and an unknown code is `unsupported_case`. The kinds keep the failure categories apart:

| `kind` | Codes | Required members | Optional members |
| --- | --- | --- | --- |
| `unsupported-artifact` | `unsupported_artifact`, `abi_unavailable`, `no_compatible_release` | `component`, `platform`; `abi` exactly for `abi_unavailable` | `alternatives` (`implementation`, `deployment`, `platform`) |
| `missing-prerequisite` | `missing_prerequisite` | `component`, `prerequisite` | `alternatives` |
| `trust-failure` | `target_not_authenticated`, `target_length_mismatch`, `target_digest_mismatch`, `release_descriptor_mismatch`, `artifact_platform_mismatch`, `release_revoked`, the `metadata_*` codes, `offline_metadata_unavailable`, `repository_unavailable` | `repositoryId` | `role` (`root`, `timestamp`, `snapshot`, `targets`), `target`, `mirror` |
| `offline-content-unavailable` | `offline_content_unavailable` | `component`, `target`, `sha256` | |
| `ownership-conflict` | `ownership_conflict` | `component`, `ownership` | |
| `readiness-failed` | `readiness_failed` | `component`, `check`, `readiness` | |
| `unsupported-contract` | the eight reader codes | `document` (`request`, `lock`, `recipe`, `receipt`, `result`), `path` | |
| `selection-unavailable` | `generation_not_installed` | `source` | |
| `lock-binding` | `request_changed`, `platform_not_locked`, `lock_changed`, `receipt_lock_mismatch`, `lock_recipe_mismatch` | `document`, `path`; `platform` exactly for `platform_not_locked` | |

A `lock-binding` diagnostic's `document` is the document whose member its `path` names, so each code reports a fixed `document`:

| `code` | `document` | `path` | Fixture |
| --- | --- | --- | --- |
| `request_changed` | `lock` | `requestSha256` | `restore-request-changed.json` |
| `platform_not_locked` | `lock` | `platforms`, with `platform` naming the missing platform | `restore-platform-not-locked.json` |
| `lock_changed` | `receipt` | `lockSha256` | `repair-lock-changed.json` |
| `receipt_lock_mismatch` | `receipt` | the receipt member, such as `providers[0].identity` | `repair-receipt-lock-mismatch.json` |
| `lock_recipe_mismatch` | `lock` | the lock member, such as `platforms.win-x64.providers[0]` | `restore-lock-recipe-mismatch.json` |

Only `platform_not_locked` has `platform`. A `lock-binding` diagnostic with `platform` and another code is `inconsistent_document` at its `platform`, and the schema refuses it too. A diagnostic without `code` is `invalid_document` at its `code`. A `readiness-failed` diagnostic reports the readiness reached, which is below the state its failed check would reach. A `mirror` carries no user information, query or fragment. No result carries a secret value.

## Fixtures

`fixtures/0.1.0-draft.1/result/` holds an AOT F# setup plan with its digest, the escaping plan and its canonical bytes, a `show` result explaining a project selection, an offline restore missing a locked archive, a `doctor` result with a diagnostic of every kind, and one failed result for each `lock-binding` code in the table above. `result/negative/` covers:

- a later draft, an unknown critical member, an unknown command and an unknown diagnostic kind;
- a diagnostic without a code, and a `lock-binding` diagnostic with `platform` on another code;
- `downloadBytes` written as `41943040.0` and as `1e3`;
- mirrors carrying user information or a query;
- a succeeded outcome with an error, a failed outcome without one, and a planned outcome without a plan;
- an unknown code, a code of another kind, and `abi_unavailable` without `abi`;
- an offline diagnostic without a digest, an empty instruction, and a failed check that reports the state it failed to reach;
- relative and traversing project paths, and a `lockSha256` that is not a digest;
- a plan digest that does not match, a provider component without a delivery, and a process provider whose probe is `none`.
