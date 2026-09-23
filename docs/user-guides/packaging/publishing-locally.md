---
title: Publish Libraries to a local registry
sidebar_label: Publish locally
sidebar_position: 3
---

# Publish Libraries to a local registry

Local publication makes a Library release discoverable and verifiable in a
directory registry. That registry holds package files plus signed information
about which releases it offers and who published them. Consumers use the directory
through `morphir package resolve` and `restore`.

:::caution Early access: publisher tooling is not yet available
This guide describes **Morphir CLI v0.4.0-beta.4**. It has no public command to
initialize a model-package registry, sign a release, or publish a Library. This
article explains the publication inputs and how to try a prepared local registry.
It is not a runnable recipe for publishing a new custom release. The format and
future publishing workflow may change.
:::

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

The [versioned example](https://github.com/finos/morphir/tree/v0.4.0-beta.4/examples/package/local-library-restore)
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

The [local Library contract](https://github.com/finos/morphir/blob/v0.4.0-beta.4/spec/package/local-library-contract.md)
and [trust profile](https://github.com/finos/morphir/blob/v0.4.0-beta.4/spec/package/package-trust-profile.md)
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
