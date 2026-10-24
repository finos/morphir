---
order: 6
---
# Generator JSON commands

Use the site, SDK and Scheme documentation generators with `--json` when another
program needs their results. The flag changes presentation; generation and checks
still run, and a failure still has a nonzero process status. This page documents
these seven operations and their versioned result contract.

For example, generate the SDK source and inspect the paths actually written:

```shell
moon run pkgs/morphir-typing-tools/sdkgen --target native -- --json generate > result.json
```

Check the process status before consuming a successful result. Help is also JSON
and performs no generation or checks:

```shell
moon run pkgs/morphir-typing-tools/sdkgen --target native -- --json --help
```

## Result and error format

Each JSON invocation writes exactly one compact JSON document followed by LF to
stdout. The following examples are expanded for readability. A successful result
contains `result` and no `error`:

```json
{
  "profile": "morphir/command-result",
  "contractVersion": "0.1.0",
  "command": "morphir.sdkgen.generate",
  "state": "succeeded",
  "exitCode": 0,
  "result": {
    "sourcePath": "pkgs/morphir-sdk-spec/sdk.scm",
    "writtenPaths": ["pkgs/morphir-sdk-spec/sdk_data.mbt"]
  },
  "diagnostics": []
}
```

A failed result contains `error` and no `result`. `error.code` identifies the
failure category; `error.message` describes it. Diagnostics contain `severity`
and `message`, with severity `warning` or `error`.

```json
{
  "profile": "morphir/command-result",
  "contractVersion": "0.1.0",
  "command": "morphir.sdkgen.check",
  "state": "failed",
  "exitCode": 1,
  "error": {
    "code": "sdkgen.differences",
    "message": "sdkgen: 1 differences"
  },
  "diagnostics": [
    {"severity": "error", "message": "pkgs/morphir-sdk-spec/sdk_data.mbt: is stale; run `mise run sdk-spec:generate`"}
  ]
}
```

The process status agrees with `exitCode`. Help succeeds with status 0 and a
`result.help` string containing rendered usage. SDK and Scheme-doc syntax errors
use status 2 and code `syntax`; site syntax errors use status 1 and code `syntax`.
Domain validation, stale generated files and ordinary operation errors use status
1. Newly introduced JSON refusal paths exit normally instead of aborting; default
invocations keep their existing behavior. Fatal runtime failures or externally
terminated processes may end without producing a document, so also handle missing
or invalid output and the process status.

Stdout is reserved for that document. Site-generation warnings appear both in
`diagnostics` and as warning lines on stderr. Other runtime or host diagnostics
may also appear on stderr; consumers should parse stdout independently. Success
is emitted after required writes finish. The flag adds no transaction or rollback:
a failed operation may already have written files before the failure.

## Operations and result fields

| Invocation | `command` | Successful `result` |
| --- | --- | --- |
| Site generate | `morphir.site.generate` | `root`, `outputDirectory`, `mainBuild`, `writtenPaths` |
| Site check | `morphir.site.check` | `directory`, `configPath`, `basePath`, `pageCount`, `fileCount`, `passed` |
| SDK `bootstrap BINDINGS OUTPUT` | `morphir.sdkgen.bootstrap` | `bindingsPath`, `writtenPaths`, `valueCount`, `moduleCount` |
| SDK `generate` | `morphir.sdkgen.generate` | `sourcePath`, `writtenPaths` |
| SDK `check` | `morphir.sdkgen.check` | `bindingCount`, `checkedPaths`, `passed` |
| Scheme docs `generate` | `morphir.schemedocs.generate` | `writtenPaths`, `removedPaths` |
| Scheme docs `check` | `morphir.schemedocs.check` | `checkedPaths`, `passed` |

SDK errors use `sdkgen.failed` for operation failures and `sdkgen.differences` for
freshness mismatches. Scheme docs use `schemedocs.failed` and
`schemedocs.differences`. Site validation uses `site.invalid`; other generator or
checker errors use `site.generate_failed` or `site.check_failed`. Syntax errors
use the command's root identifier; root help uses `morphir.sdkgen`,
`morphir.schemedocs`, or the corresponding site identifier. These commands expose
no separate self-test CLI operation; their tests remain ordinary repository tests.

## Argument boundaries

SDK and Scheme docs take the JSON flag at the root, before the operation.
Everything after SDK `bootstrap` remains a fixed literal operand, including a
filename `--json`, `--help`, `--`, an empty string or a Unicode path. For example,
`--json bootstrap --json --help` reads the file named `--json` and writes the file
named `--help`. Do not filter such tokens out of a command's data arguments.

Site tools reserve an owned presentation prefix. Use `--json -- LEGACY_ARGS` for
JSON execution, and `--json --help` for effect-free JSON help. The legacy segment
keeps exact option lookup: first duplicates win, missing values and ignored
tokens keep their previous meaning, and equals forms are not rewritten. Use
`--forward-argv -- RAW` for an entirely literal default invocation. The escape
unwraps once; any similar-looking prefix inside RAW stays literal.

These generators introduce the profile above. The main Morphir CLI and commands
that already returned JSON keep their own successful schemas; passing `--json`
does not wrap or convert those existing contracts into this generator profile.
