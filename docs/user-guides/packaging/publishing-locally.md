---
title: Publish Libraries to a local registry
sidebar_label: Publish locally
sidebar_position: 5
---

# Publish Libraries to a local registry

Local publication makes a Library release discoverable and verifiable in a
directory registry. That registry holds package files plus signed information
about which releases it offers and who published them. Consumers use the directory
through `morphir package resolve` and `restore`.

New to signing and trust? Read [Why package trust matters](why-package-trust.md)
or [Trust explained simply](trust-explained.md) first.

:::caution Early access: publisher tooling is not yet available
This guide describes **Morphir CLI v0.4.0-beta.5**. It has no public command to
initialize a model-package registry, sign a release, or publish a Library. This
article also shows the newer source-built preview separately. The beta.5 steps
below explain the publication inputs and how to try a prepared local registry;
they do not publish a custom release. Formats and workflows may change.
:::

## Source-built CLI preview

The source-built CLI can publish a dependency-free classic V4 Library to an
explicitly initialized local registry on **macOS**. This path is not in
v0.4.0-beta.5; publication on other platforms awaits qualification. Continue
from [Create a Library](creating-a-library.md#source-built-cli-preview) in the
same shell, where `$work` points to a temporary directory. The checked-in
[`hello` example](https://github.com/finos/morphir/tree/main/examples/package/local-library-publish)
includes `bootstrap.mjs`, a small helper that builds the public root and policy
documents for this tutorial. The CLI does not create or implicitly trust an
authority.

First make a publisher key and four distinct registry-role keys. Each file is
an explicit Ed25519 seed, kept in a private directory outside the checkout:

```sh
mkdir -m 700 "$work/keys"
for role in publisher root targets snapshot timestamp; do
  openssl rand -hex 32 > "$work/keys/$role.key"
  chmod 600 "$work/keys/$role.key"
  morphir --no-banner package registry key-info --key-file "$work/keys/$role.key" --json > "$work/$role-info.json"
done
node bootstrap.mjs root 2027-01-01T00:00:00Z "$work/root-info.json" "$work/targets-info.json" "$work/snapshot-info.json" "$work/timestamp-info.json" > "$work/unsigned-root.json"
morphir package registry sign-metadata --input "$work/unsigned-root.json" --key-file "$work/keys/root.key" --output "$work/root.json"
node bootstrap.mjs policy "$work/root.json" "$work/publisher-info.json" > "$work/policy.json"
```

The policy pins the **exact signed root bytes** and authorizes only the tutorial
publisher key for `example.com`. Keep the five seed files private; the consumer
receives only `root.json` and `policy.json`. Choose a root and metadata expiry
appropriate to your use rather than copying the tutorial dates.

Now sign and publish the release:

```sh
morphir package sign --bundle "$work/hello-bundle" --key-file "$work/keys/publisher.key" --output "$work/hello-release"
morphir package registry init --root "$work/root.json" --policy "$work/policy.json" --registry "$work/registry" --publisher-state "$work/publisher-state"
morphir package registry prepare --bundle "$work/hello-bundle" --release "$work/hello-release" --policy "$work/policy.json" --registry "$work/registry" --publisher-state "$work/publisher-state" --expires 2027-01-01T00:00:00Z --output "$work/proposal-draft"
morphir package registry sign-proposal --draft "$work/proposal-draft/draft.json" --targets-key-file "$work/keys/targets.key" --snapshot-key-file "$work/keys/snapshot.key" --timestamp-key-file "$work/keys/timestamp.key" --output "$work/proposal.json"
morphir package publish --bundle "$work/hello-bundle" --release "$work/hello-release" --predecessor "$work/proposal-draft/predecessor.json" --proposal "$work/proposal.json" --policy "$work/policy.json" --registry "$work/registry" --publisher-state "$work/publisher-state"
```

`prepare` binds the draft to the current registry view. If another writer publishes
first, prepare and sign a new proposal; `publish` will not silently change the
old one. Keep `publisher-state` for restart and recovery. A second project can
use **only public** `root.json` and `policy.json` to initialize trust, then
`resolve` and `restore` the release as shown in
[Installing and using Libraries](installing-and-using.md). The
[CLI reference](../../cli/package/registry.md) describes the exact command inputs.

## What publication needs

For the `eligibility@1.2.0` example, a complete release involves:

1. **The Library bundle.** `manifest.json` and its declared `ir.json`, as described
   in [Create a Library](creating-a-library.md).
2. **A release record.** The package identity, dependency requirements, bundle
   location, and digests used by registry clients.
3. **A signed publisher statement.** The publisher signs information binding the
   release identity to its model, dependencies, and content.
4. **Signed registry metadata.** The registry advertises authenticated release
   records and publisher statements using TUF metadata.

The consumer supplies a trust policy and independently trusted bootstrap root.
Together they identify the repository and publisher keys the consumer accepts.
Signed registry metadata authenticates the registry's view; a publisher signature
establishes publisher evidence. The CLI also checks authorization and the actual
bundle contents before admitting a release.

## Explore a prepared registry

The [versioned example](https://github.com/finos/morphir/tree/v0.4.0-beta.5/examples/package/local-library-restore)
includes published `loan-rules@1.0.0` and `eligibility@1.2.0` releases. If you followed
the creation article, return to the root of `morphir-package-examples` and copy the
example to a new working directory:

```sh
cp -R examples/package/local-library-restore local-library-demo
cd local-library-demo
```

The relevant layout is:

```text
fixture/
  trust-policy.json
  registry/
    bundles/       Library directories containing manifest.json and ir.json
    metadata/      Signed root, targets, snapshot, and timestamp metadata
    targets/
      records/     Immutable release records
      statements/  Signed publisher statements
consumer/
  morphir.toml     Configuration for the consuming project
```

Copying these files preserves an already prepared registry. It is not publication
of a new release. Changing a bundle invalidates its declared hashes and the signed
information associated with it. Renaming the directory does not create a new
package identity or version.

All signing keys behind this fixture are public test data. Its long-lived metadata
is for repeatable examples, not an expiry policy to copy for real packages.

## For your own releases

Keep your model sources and proposed bundle together in your development workflow.
Choose the package identity, exports, and dependencies now, but account for the
missing authoring and publication tooling before depending on this feature for
distribution. The current CLI does not turn your bundle into the signed registry
objects above.

The [local Library contract](https://github.com/finos/morphir/blob/v0.4.0-beta.5/spec/package/local-library-contract.md)
and [trust profile](https://github.com/finos/morphir/blob/v0.4.0-beta.5/spec/package/package-trust-profile.md)
describe the draft protocol for implementers. They specify more than the released
CLI currently exposes. Example fixture generators and public test keys are not a
supported publisher for your own releases.

## Model packages and extensions use different repositories

You may see `morphir extension repository publish` in the CLI reference. That
command publishes executable extension bundles. It does not publish model
Libraries and cannot fill the gap described here. Use `morphir package` for the
model-package consumer workflow.

Continue with [installing and using Libraries](installing-and-using.md). You can
start at its trust-initialization step if you already copied the example above.
