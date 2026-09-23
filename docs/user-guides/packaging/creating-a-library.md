---
title: Create a Library package
sidebar_label: Create a Library
sidebar_position: 4
---

# Create a Library package

A Library bundle brings together a model and the information needed to release it.
This guide uses the `eligibility` Library to explain those files and how to prepare
your own. Preparing a bundle is one part of publication; it does not make the bundle
available to `morphir package resolve` yet.

:::caution Early access
This guide targets **Morphir CLI v0.4.0-beta.5**. Package formats and authoring
workflows may change. There is no public package creation or packing command in
this release. The steps below work with bundle files directly and do not constitute
a complete publication workflow.
:::

## 1. Choose the release identity

Our example has these names:

| Name | Example | Meaning |
| --- | --- | --- |
| Package path | `example.com/finance/eligibility` | The identity used to publish and select releases. |
| Release version | `1.2.0` | The exact version of this bundle. |
| IR Package name | `example/eligibility` | The name referenced by definitions and dependencies in IR. |

Use your own namespace for your packages. `example.com` is illustrative; Morphir
does not download these examples from that domain. This early profile accepts
stable three-part versions such as `1.2.0`. Package release versions with prerelease
suffixes or build metadata are not supported by this profile, even though the CLI
itself is distributed as a prerelease.

## 2. Prepare the model

The bundle contains one classic JSON IR v4 Library document. The worked
`eligibility` model exposes a public `decision` module with a `Decision` type and
a `default-decision` value. A consumer can generate source from that model.

To inspect a complete, known-good bundle, download the examples once:

```sh
git clone --depth 1 --branch v0.4.0-beta.5 https://github.com/finos/morphir.git morphir-package-examples
cd morphir-package-examples
mkdir my-library
cp spec/package/mck/fixtures/two-libraries/eligibility/ir.json my-library/ir.json
cp spec/package/mck/fixtures/two-libraries/eligibility/manifest.json my-library/manifest.json
```

This copies the existing example release; it does not create a new release identity.
For your own Library, obtain a classic JSON v4 Library from a supported Morphir
frontend and use its actual IR Package name and public module paths in the manifest.
Changing the manifest alone does not rename the package or modules inside the IR.

## 3. Describe the bundle

The copied `manifest.json` is small enough to read in full:

```json
{
  "formatVersion": "0.1.0-draft.1",
  "kind": "Library",
  "packagePath": "example.com/finance/eligibility",
  "version": "1.2.0",
  "ir": {
    "formatVersion": "4",
    "packageName": "example/eligibility",
    "payload": {
      "path": "ir.json",
      "mediaType": "application/json",
      "profile": "classic"
    }
  },
  "dependencies": {},
  "exports": {
    "decision": "decision"
  },
  "content": {
    "ir.json": "sha256:243e640848e5ee728224c0bc9090c67cf434d9814cec77745daad918119ceb43"
  }
}
```

`exports` maps the names you expose to public IR module paths. `content` lists the
payload files and their exact-byte SHA-256 digests. The manifest does not list
itself as content. Keep source files, editor files, and other undeclared material
outside the bundle directory.

The digest above belongs only to the copied `ir.json`. If you have Node.js installed,
you can check it from the repository root:

```sh
node -e "const fs = require('node:fs'); const crypto = require('node:crypto'); console.log('sha256:' + crypto.createHash('sha256').update(fs.readFileSync('my-library/ir.json')).digest('hex'))"
```

Hash the saved bytes. Reformatting the JSON or changing its line endings changes
the digest, even when the model means the same thing. After changing your own
payload, update its `content` entry. A matching hash checks the bytes; it does not
establish that the IR, exports, and dependencies form a valid Library.

## 4. Declare dependencies when needed

`eligibility` has no dependencies. The second Library, `loan-rules`, requests it
through this manifest entry:

```json
"dependencies": {
  "example/eligibility": {
    "packagePath": "example.com/finance/eligibility",
    "versionRange": {
      "minimumInclusive": "1.0.0",
      "maximumExclusive": "2.0.0"
    }
  }
}
```

This is a manifest fragment, not a complete JSON document. Its key is the IR
Package name. The package path and interval select a release providing that name.
The IR must also contain the matching dependency specification; adding only the
manifest entry does not link models. Resolution chooses an exact release and
records it in `morphir.lock`.

## What comes next?

You now know the bundle's inputs and can inspect the worked files. A custom bundle
still needs semantic verification, a signed publisher statement, and authenticated
registry metadata before consumers can resolve it. The
[Library format contract](https://github.com/finos/morphir/blob/v0.4.0-beta.5/spec/package/library-contract.md)
contains the detailed restrictions for tool authors.

Continue with [publishing locally](publishing-locally.md) to understand that boundary,
or [try the prepared signed registry](installing-and-using.md).
