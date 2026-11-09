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
| `selection` | For `show`: the selected `generationId`, `platform`, `host` and optional `lockSha256`, with its `source` |
| `diagnostics` | Every diagnostic, possibly empty |

`outcome` is `failed` exactly when a diagnostic has `severity` `error`. `planned` carries a plan and no error. A mismatch is `inconsistent_document`.

`selection.source.kind` is `cli`, `environment` (`MORPHIRUP_TOOLCHAIN`), `project` with the absolute `path` of the request, or `user-default`, in that precedence order.

Understood critical paths: `schemaVersion`, `critical`, `command`, `outcome`, `plan`, `planSha256`, `selection`, `diagnostics`.

## Plans

A plan names `implementation`, `deployment`, `platform`, the `recipe`, whether `metadataRefresh` is `required` or `not-required`, and its `components`. Each component has:

- `component`: `{ "role": "host", "implementation", "deployment" }` or `{ "role": "provider", "operation", "language" | "target" }`;
- `version`, and for a provider `extensionId` and `delivery`;
- `source`: `repository-target` or `recipe-digest` with `repositoryId`, `target` and `sha256`, or `built-in`, or `external-owner`;
- `downloadBytes`, `installedBytes`, `updateOwner` (an ownership case) and `prerequisites`;
- `probe`: `none`, `in-host`, or `process-with-user-rights`. A `process` or `dotnet-tool` provider's readiness probe runs acquired code with the user's rights, and the plan says so.

`planSha256` is the SHA-256 of the plan's TUF canonical JSON: object keys sorted, no insignificant whitespace, no floating-point numbers. This is the encoding tool release metadata v1 already uses for repository identity. `--expect-plan <digest>` compares against it and refuses a different plan. A result whose `planSha256` does not match its plan is `inconsistent_document`.

## Diagnostics

Every diagnostic has `kind`, `severity` (`error` or `warning`) and a human `message`. The kinds keep the failure categories apart:

| `kind` | Required members | Optional members |
| --- | --- | --- |
| `unsupported-artifact` | `component`, `platform` | `alternatives` (`implementation`, `deployment`, `platform`) |
| `missing-prerequisite` | `component`, `prerequisite` | `alternatives` |
| `trust-failure` | `code` (a tool release metadata v1 stable code), `repositoryId` | `role` (`root`, `timestamp`, `snapshot`, `targets`), `target`, `mirror` |
| `offline-content-unavailable` | `component`, `target`, `sha256` | |
| `ownership-conflict` | `component`, `ownership` | `instruction` |
| `readiness-failed` | `component`, `check`, `readiness` | |
| `unsupported-contract` | `document`, `code` (a reader code), `path` | |
| `selection-unavailable` | `source` | `instruction` |

`instruction` is a non-empty argument vector, such as `["dotnet", "tool", "update", "--global", "Morphir.Tool"]`. A `readiness-failed` diagnostic reports the readiness reached, which is below the state its failed check would reach. A `mirror` carries no user information, query or fragment; a document carrying credentials is `credential_in_document`. No result carries a secret value.

## Fixtures

`fixtures/0.1.0-draft.1/result/` holds an AOT F# setup plan with its digest, a `show` result explaining a project selection, an offline restore missing a locked archive, and a `doctor` result with one diagnostic of every kind. `result/negative/` covers a later draft, an unknown critical member, an unknown diagnostic kind, mirrors carrying user information or a query, a succeeded outcome with an error, an unknown trust code, an offline diagnostic without a digest, an unknown command, a failed check that reports the state it failed to reach, and a plan digest that does not match.
