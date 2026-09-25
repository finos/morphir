---
title: Install and use Libraries
sidebar_label: Install and use
sidebar_position: 6
---

# Install and use Libraries

This walkthrough installs the published `loan-rules@1.0.0` graph from a prepared
local registry. Morphir selects its `eligibility@1.2.0` dependency, restores both
Libraries, and uses the eligibility model to generate and compile Gleam source
in a consumer project.

:::caution Early access
These commands target **Morphir CLI v0.4.0-beta.9**. Packaging commands and formats
may change. The supported workflow uses one caller-controlled local registry and
fresh signed metadata. The example demonstrates generation and compilation from
a restored Library, not cross-package linking or execution of an application.
:::

## 1. Get the CLI and example

Install [v0.4.0-beta.9](https://github.com/finos/morphir/releases/tag/v0.4.0-beta.9)
using the [CLI installation guide](../../getting-started/morphir-cli.md) and put
`morphir` on your `PATH`. Check the version:

```sh
morphir --version
```

The example is self-contained. Clone its matching source tag and work in a copy:

```sh
git clone --depth 1 --branch v0.4.0-beta.9 https://github.com/finos/morphir.git morphir-package-examples
cd morphir-package-examples
cp -R examples/package/local-library-restore local-library-demo
cd local-library-demo
```

Skip these preparation commands if you already created `local-library-demo` in
the [publication guide](publishing-locally.md). Run the remaining commands from
that directory. No submodule checkout, source build, separate Gleam compiler, or
downloaded extension is needed for this example. Git and a POSIX shell are used
for the preparation commands.

The fixture's trust policy authorizes public test keys. Use it only for this
example. For a real registry, obtain the policy and trusted root independently
from an administrator you trust.

## 2. Establish trust once

For a short explanation of the policy, trusted root, and saved state used here,
see [Trust explained simply](trust-explained.md).

```sh
morphir package trust init --policy fixture/trust-policy.json --root fixture/registry/metadata/1.root.json --state trust-state --json
```

This creates `trust-state` and verifies that the bootstrap root matches the
policy's exact digest. Keep this directory for subsequent operations. It holds
persistent authentication state, including rollback protection. Initialization
refuses an existing directory; it does not reset it.

## 3. Resolve the published root

```sh
morphir package resolve --root example.com/finance/loan-rules@1.0.0 --policy fixture/trust-policy.json --registry fixture/registry --state trust-state --output consumer/morphir.lock --assurance portable --json
```

Resolve authenticates the registry, selects compatible dependencies, verifies the
complete graph, and writes a new `consumer/morphir.lock`. This example selects
`loan-rules@1.0.0` and `eligibility@1.2.0`. The output parent, `consumer`, already
exists; the lock file must not exist before this command.

`--assurance portable` explicitly accepts the requirement that you control the
local registry, state, and output directories. It does not enable a hardened
filesystem mode.

Keep `morphir.lock` with your consumer project. It pins the selected releases and
metadata, but it does not replace authentication on the next operation. This
command starts from a published root; it does not read your project's source
imports and automatically add dependencies.

## 4. Install the locked Libraries with restore

The installation operation is named `restore` in the current CLI:

```sh
morphir package restore --policy fixture/trust-policy.json --lock consumer/morphir.lock --registry fixture/registry --state trust-state --output consumer/libraries --assurance portable --json
```

Restore checks fresh signed metadata, publisher authorization, and package
contents before exposing the complete graph. It does not re-resolve dependencies
or rewrite the lock. The result includes:

```text
consumer/libraries/
  example.com/finance/
    loan-rules/1.0.0/
      manifest.json
      ir.json
    eligibility/1.2.0/
      manifest.json
      ir.json
```

The destination must be new. For another authenticated replay of the same lock,
run restore with another destination, such as `consumer/replayed`. Keep using the
same trust state.

For a source-built V4.1 [linked metadata bundle](creating-a-library.md#linked-metadata-context-files-in-the-source-built-draft),
the installed Library also has its signed `contexts/*.jsonld` files. You can
query facts directly from its installed `ir.json`:

```sh
morphir metadata query --ir consumer/libraries/example.com/greeting/1.0.0/ir.json
```

The CLI resolves those contexts from the installed Library directory, without
the author's source tree. The current draft labels those facts `unvalidated`
until a verified predicate declaration closure is connected. This metadata
command and V4.1 bundle path are not in the beta.8 binary.

## 5. Use the restored model

The supplied `consumer/morphir.toml` names the consuming project and selects the
built-in Gleam frontend. Generate source from the restored eligibility Library:

```sh
morphir gleam --json generate --config consumer/morphir.toml --input consumer/libraries/example.com/finance/eligibility/1.2.0/ir.json --output consumer/generated
```

Open `consumer/generated/decision.gleam`. It contains:

```gleam
pub type Decision {
  Approved
  Declined
}

pub fn default_decision() {
  Approved
}
```

Now compile that generated source to Morphir IR under the consumer project's
identity:

```sh
morphir gleam --json compile --config consumer/morphir.toml --input consumer/generated --output consumer/compiled
```

The JSON result reports success and a Library named `examples/library-consumer`.
You have used the restored provider as input to another project. The CLI has not
automatically linked the `loan-rules` and `eligibility` code or executed the model.

## Refresh and update later

To authenticate the latest registry metadata without changing your lock:

```sh
morphir package refresh --policy fixture/trust-policy.json --registry fixture/registry --state trust-state --assurance portable --json
```

Refresh records the accepted metadata view. It does not install packages or grant
permission to use one. If the registry advances beyond your lock's metadata pins,
restore refuses the old lock. Resolve a new lock, or update selected dependencies.

For example, select an eligible update for the `eligibility` dependency and write
a separate lock:

```sh
morphir package update --lock consumer/morphir.lock --target example.com/finance/eligibility --policy fixture/trust-policy.json --registry fixture/registry --state trust-state --output consumer/updated.lock --assurance portable --json
```

This registry contains only one eligible version of each package, so the command
does not demonstrate a version upgrade. The separate
[scoped-update example](https://github.com/finos/morphir/tree/v0.4.0-beta.9/examples/package/local-library-update)
provides multiple versions and a checked upgrade. For an exact target version,
append `@VERSION` to the package path; repeat `--target` to request several targets.
The root and packages outside the old target dependency closure stay pinned.
Restore the new lock into another new directory before consuming it.

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| Initialization refuses the state directory | Initialize only once. Reuse established state for later commands. |
| The lock or restore output already exists | Choose a new output path with an existing parent. These commands do not overwrite previous results. |
| Metadata pins no longer match | The authenticated registry has advanced. Resolve or update to a new lock. |
| Metadata expired, content is missing, or a signature/hash fails | Ask the registry operator to fix or renew the release metadata or content. Editing local signed files does not repair authentication. |
| Trust state is corrupt or an operation is unresolved | Preserve the state and diagnose the failure. Do not delete it or clear internal markers to bypass the refusal. Automatic recovery is not available in this release. |

See the [package command reference](../../cli/package.md) for every flag and the
[packaging overview](overview.md) for the current support boundary.
