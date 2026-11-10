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

The canonical form is the OLPC canonical JSON that TUF uses, which tool release metadata v1 already uses for repository identity:

- No whitespace outside strings.
- Object members are sorted by the bytes of their encoded keys.
- Strings are converted to Unicode Normalization Form C. Only `"` and `\` are escaped, as `\"` and `\\`. Every other character is written as its UTF-8 bytes, including `<`, `>`, `&`, `+`, `'` and non-ASCII characters. There is no `\uXXXX` escape.
- Numbers are integers in plain decimal; a floating-point number makes the plan invalid.
- `true`, `false` and `null` are written as such.

Many JSON libraries escape by default (.NET writes `>` as `>`), so an implementation must configure or write its own encoder. `fixtures/0.1.0-draft.1/result/setup-plan-escaping.json` has a plan whose strings contain `>`, `<`, `&`, `+`, `é`, `"` and `\`, and `setup-plan-escaping.plan.canonical.json` holds its exact canonical bytes.

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

A frozen restore whose request bytes changed reports a `lock-binding` diagnostic with code `request_changed`, `document` `lock` and `path` `requestSha256`. A `readiness-failed` diagnostic reports the readiness reached, which is below the state its failed check would reach. A `mirror` carries no user information, query or fragment. No result carries a secret value.

## Fixtures

`fixtures/0.1.0-draft.1/result/` holds an AOT F# setup plan with its digest, the escaping plan and its canonical bytes, a `show` result explaining a project selection, an offline restore missing a locked archive, a frozen restore whose request changed, and a `doctor` result with a diagnostic of every kind. `result/negative/` covers:

- a later draft, an unknown critical member, an unknown command and an unknown diagnostic kind;
- mirrors carrying user information or a query;
- a succeeded outcome with an error, a failed outcome without one, and a planned outcome without a plan;
- an unknown code, a code of another kind, and `abi_unavailable` without `abi`;
- an offline diagnostic without a digest, an empty instruction, and a failed check that reports the state it failed to reach;
- relative and traversing project paths, and a `lockSha256` that is not a digest;
- a plan digest that does not match, a provider component without a delivery, and a process provider whose probe is `none`.
