# Publish and consume a local Library

This source-built early-access example starts with `src/main.gleam`, compiles a
classic V4 Library, and publishes a signed release to a new local registry. A
separate consumer can then resolve, restore and generate source from that release.
The publisher path is currently qualified on macOS. It is not part of the
v0.4.0-beta.4 binary.

Run the [executable scenario](scenarios.md) from the repository root with
`mise run test:examples -- --filter 'package/local-library-publish#publish-and-consume'`.
It starts from an absent registry and uses public, test-only signing seeds in
`fixture/keys`. The signed bootstrap root and pinned policy under `fixture/`
are frozen inputs; never reuse these keys for a real registry.

Follow [Create a Library](../../../docs/user-guides/packaging/creating-a-library.md#source-built-cli-preview)
and [Publish locally](../../../docs/user-guides/packaging/publishing-locally.md#source-built-cli-preview)
from a source checkout. Keep the same shell and its `$work` variable for both
steps. `bootstrap.mjs` builds only the tutorial's **public** unsigned root and
trust policy from CLI key information and the signed root bytes. It never opens
private seed files. The CLI signs the root and publication proposal with keys
the caller supplies explicitly.

To prove independent consumption after publication, create a second project
directory and give it only the registry path, `root.json`, and `policy.json`:

```sh
mkdir "$work/consumer"
cp "$work/root.json" "$work/policy.json" "$work/consumer/"
cp consumer/morphir.toml "$work/consumer/morphir.toml"
cd "$work/consumer"
morphir package trust init --root root.json --policy policy.json --state trust-state
morphir package resolve --root example.com/finance/hello@1.0.0 --policy policy.json --registry "$work/registry" --state trust-state --output morphir.lock --assurance portable
morphir package restore --policy policy.json --lock morphir.lock --registry "$work/registry" --state trust-state --output libraries --assurance portable
morphir gleam generate --config morphir.toml --input libraries/example.com/finance/hello/1.0.0/ir.json --output generated
morphir gleam compile --config morphir.toml --input generated --output compiled
```

The restored IR is at `libraries/example.com/finance/hello/1.0.0/ir.json`.
The [installing guide](../../../docs/user-guides/packaging/installing-and-using.md)
explains trust state, the lock file, and restoration in more detail.

This is a local demonstration, not key management advice. Choose real expiry
dates, protect your signing keys, and preserve `publisher-state` for restart and
recovery. The helper hardcodes `example.com`, the `hello` release's namespace.
