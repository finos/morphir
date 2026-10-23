---
order: 7
---
# Automation JSON results

CI, acquisition and host helpers offer opt-in JSON for automation. Choose the
flag at the command's owned boundary. Literal paths and external-tool arguments
may themselves be named `--json`, so the spelling is deliberately command-specific.
For example, request effect-free help from the CI measurement helper:

```shell
moonx scripts/ci-measure.mbtx --json -- --help
```

The new finite result format has these fields:

```json
{"profile":"morphir/command-result","contractVersion":"0.1.0","command":"ci.measure","state":"succeeded","exitCode":0,"result":{"help":"rendered command usage"},"diagnostics":[]}
```

`command` is a stable operation identifier. Successful operations have `result`
and no `error`; failures have `error: {"code": "category", "message": "description"}`
and no `result`. The state is `succeeded` or `failed`, and `exitCode` agrees with
the actual mapped process status. Result fields describe completed work, such as
written paths, a receipt, measured values, a validated source identity or passed
self-tests. Failure codes are local to each command; do not infer success from the
presence of JSON alone.

Stdout contains one compact JSON value followed by LF. Progress and live child
output use stderr in JSON mode. A child whose stdout is data keeps its existing
decoder; that data is not mixed into the outer stdout stream. Stderr may contain
ordinary human or runtime diagnostics. Success is emitted after required writes
complete; failures do not imply rollback of earlier effects. A killed process or
fatal runtime failure can end without a JSON value, so check both status and output.

Help returns rendered usage in `result.help` or `result.render_help`, without
acquisition or operation effects. Existing self-tests run their real checks before
reporting a passed result. New expected JSON validation/refusal branches exit
normally with status1. Existing explicit child/status mappings remain meaningful,
including23 and130 where propagated. Default invocations retain their old error,
abort, status and output behavior; a host's signal-derived status is not a
portable JSON contract.

## Existing JSON remains compatible

Commands with an existing successful JSON contract keep that object bare rather
than wrapping it. CI selection, mise-impact verdicts, trust verdicts, CI artifact
views, CI/qualification/provider receipts and Wasmoon component evidence preserve
their existing schemas. Those objects do not acquire `contractVersion` merely
because `--json` is supplied. Help/self-test responses and newly structured errors
can use the new finite format above. In particular, a distrust verdict with
`trusted:false` can still be a successful completed decision with process status0.

## Invocation boundaries

The following examples name script argv after the script filename. Consult its
JSON help for the available operations. Fixed-arity JSON flags go outside the
legacy data slots; data is never reconstructed from a variadic parser result.

| Helpers | JSON selection and literal data |
| --- | --- |
| `ci-changes`, `ci-gate`, `ci-reuse` | Declared `--json` flag, including owned subcommand positions; `--receipt=--json` and `--repo=--json` remain literal option values. JSON help validates complete syntax before succeeding. |
| Other CI helpers | Exact `--json -- RAW` selects presentation once. Supported leading/trailing forms outside complete legacy arity also work. A lone target/run value named `--json` remains data where it previously was data. |
| `artifact-client-source` | `check --json`; success reports the checked source identity. |
| `moonbit-core` | `check --json`; the result includes `corePath`. Default stdout remains the bare path for existing consumers. |
| `llvm-setup`, `native-otel-setup` | Root `--json` selects the new result; setup still performs its existing checks and required writes. |
| `headless-host` | `CHECKOUT --json`; a lone checkout named `--json` stays a checkout. |
| `mck-release` | Exact `--json -- RAW`; e.g. `--json -- --self-test` is the JSON self-test. Legacy `--self-test --json` remains two literal acquisition operands. |
| `decimal` core-pin fixture | `--json` returns actual checked digit counts and `passed`; its default successful output stays unchanged. |
| `moonbit-extension` | `build --json`, `bundle --json`, `test --json`, `--help --json`, `--self-test --json`. Results describe the actual guest path, bundle/platform, or completed checks. |
| `wasm-host-check` | `--json` qualifies, `setup --json` installs existing dependencies, and `--help --json` or `--self-test --json` are local controls. Qualification returns the completed report in `result`; setup reports completed step statuses. |
| `workbench-cef-extract` | Exactly `-xjf ARCHIVE -C DESTINATION --json`; the four original tar slots stay literal. Results name the validated archive, destination, sha256 and completed extraction. `--roundtrip --json` reports the small archive check, not actual CEF qualification. |
| `workbench-packaged-targets` | `build TARGET --json`, `accept TARGET --json`, `aggregate DIRECTORY --json`, or `--probe-archive --json`. Results contain the receipt actually published. `aggregate --json` still reads the directory named `--json`; add a third `--json` to select JSON for that directory. |
| Wasmoon probe | `COMPONENT RESOURCES CALLBACKS --json` or `--json -- COMPONENT RESOURCES CALLBACKS`. The successful evidence object remains bare; help/self-test use the finite format. |

A `--json` control does not grant host capability or authorize new acquisitions.
For example, a small archive roundtrip and synthetic matrix receipt do not qualify
an actual Linux AppImage or Windows CEF package. The existing actual-host checks
and release requirements still apply. Forwarded Rust MCK and protocol stdout keep
their existing contracts; the MoonBit wrapper does not take ownership of them.
