# Unsigned local Library review shapes

These are complete field-level shapes for reviewing candidate draft.3. They are not an
executable registry fixture, a schema-valid full lock, signed evidence, or a compatibility
result. Every `UNSIGNED:...` value marks unavailable future exact-byte evidence and
deliberately fails the digest grammar. Do not replace it with a plausible fake SHA-256.
No TUF metadata, DSSE signatures, trusted key material, or local authorization is supplied.

The two JSON payload files alongside this README are readable unsigned statement values.
Their JSON structures satisfy the candidate payload schema. Their pretty-printed file
bytes are not the canonical payload bytes to sign. Canonical encoding removes indentation,
sorts object keys, retains prescribed dependency order, and emits no final newline.
Neither the unsigned files nor their hashes may stand in for a signed envelope's digest.

These hashes identify only the actual readable files in this directory, including their
final LF. They do not authenticate a publisher or identify canonical signing payloads:

| Readable unsigned file | Exact file SHA-256 |
| --- | --- |
| `eligibility-statement-payload.json` | `sha256:98b42b54516d679247a649a95c554dd310f71be357046ad3ecd81f4e3b0d7d31` |
| `loan-rules-statement-payload.json` | `sha256:b6c9301e78a523f8037dd6bf1fbd2b7ca89aa836b293e13d72f776db26a6d683` |

## Unchanged fixture identities and bytes

The source is the existing [two-Library fixture](../../two-libraries/), including both
manifests, both `ir.json` files and `lock-core.json`. No source file is copied or rewritten.

| Value | Eligibility provider | Loan-rules consumer |
| --- | --- | --- |
| PackagePath | `example.com/finance/eligibility` | `example.com/finance/loan-rules` |
| Version | `1.2.0` | `1.0.0` |
| IR PackageName | `example/eligibility` | `example/loan-rules` |
| Exact IR file digest | `sha256:243e640848e5ee728224c0bc9090c67cf434d9814cec77745daad918119ceb43` | `sha256:b1884eeb8364f96c6405cc45f2fe07a006c22f066a4136656ad05dda9c9a94cc` |
| Canonical manifest digest | `sha256:7441f6bc460eeded5a5c5a286d07256fd0eaaca93bcb1fe8ea97c8dcd920532c` | `sha256:23bbfeda3a3539a0a27546f5e261c4b325c3484327157898f0c54cbe36a8c9c2` |
| Package content digest | `sha256:5922bc8860f6cd008b9cda341be7f3a776ea332e63261392e94c17e19a647886` | `sha256:345706de972523b65c8711a4367d61f143035770145519576aeaaf18733d874e` |

Loan-rules requires IR name `example/eligibility` from packaging path
`example.com/finance/eligibility` in `[1.0.0, 2.0.0)`. Its IR reference remains
`example/eligibility:decision#default-decision`. The root is the published loan-rules
release, not an unpublished authoring project. Old handles `n0` and `n1` project to
exact draft.2 ReleaseIds without introducing persistent instance IDs.

## Full lock shape, intentionally nonconforming

The graph uses draft.2 normalized presentation, root first. Acquisitions sort by
PackagePath, evidence by ID. `finance` is a lock-local alias resolved through caller
configuration; no physical root or trusted key comes from this document.

```json
{
  "formatVersion": "0.1.0-draft.3",
  "kind": "LibraryLock",
  "resolution": {
    "policy": "flat-library:0.1.0-draft.2",
    "profile": "local-library",
    "requiredCapabilities": ["dsse-ed25519", "local-directory", "tuf-1.0.36"]
  },
  "graph": {
    "root": {
      "packagePath": "example.com/finance/loan-rules",
      "version": "1.0.0"
    },
    "nodes": [
      {
        "release": {
          "packagePath": "example.com/finance/loan-rules",
          "version": "1.0.0"
        },
        "irPackageName": "example/loan-rules",
        "manifestDigest": "sha256:23bbfeda3a3539a0a27546f5e261c4b325c3484327157898f0c54cbe36a8c9c2",
        "contentDigest": "sha256:345706de972523b65c8711a4367d61f143035770145519576aeaaf18733d874e",
        "bindings": [
          {
            "irPackageName": "example/eligibility",
            "target": {
              "packagePath": "example.com/finance/eligibility",
              "version": "1.2.0"
            }
          }
        ]
      },
      {
        "release": {
          "packagePath": "example.com/finance/eligibility",
          "version": "1.2.0"
        },
        "irPackageName": "example/eligibility",
        "manifestDigest": "sha256:7441f6bc460eeded5a5c5a286d07256fd0eaaca93bcb1fe8ea97c8dcd920532c",
        "contentDigest": "sha256:5922bc8860f6cd008b9cda341be7f3a776ea332e63261392e94c17e19a647886",
        "bindings": []
      }
    ]
  },
  "registries": [
    { "id": "finance", "snapshot": "finance-snapshot" }
  ],
  "acquisitions": [
    {
      "release": {
        "packagePath": "example.com/finance/eligibility",
        "version": "1.2.0"
      },
      "registry": "finance",
      "record": {
        "path": "records/eligibility-1.2.0.json",
        "digest": "UNSIGNED:eligibility-record"
      },
      "source": {
        "kind": "registry-directory",
        "path": "bundles/5922bc8860f6cd008b9cda341be7f3a776ea332e63261392e94c17e19a647886"
      },
      "statement": "eligibility-statement"
    },
    {
      "release": {
        "packagePath": "example.com/finance/loan-rules",
        "version": "1.0.0"
      },
      "registry": "finance",
      "record": {
        "path": "records/loan-rules-1.0.0.json",
        "digest": "UNSIGNED:loan-rules-record"
      },
      "source": {
        "kind": "registry-directory",
        "path": "bundles/345706de972523b65c8711a4367d61f143035770145519576aeaaf18733d874e"
      },
      "statement": "loan-rules-statement"
    }
  ],
  "evidence": [
    {
      "id": "eligibility-statement",
      "registry": "finance",
      "kind": "release-statement",
      "path": "statements/eligibility-1.2.0.json",
      "digest": "UNSIGNED:eligibility-dsse-envelope"
    },
    {
      "id": "finance-root",
      "registry": "finance",
      "kind": "tuf-root",
      "path": "metadata/1.root.json",
      "digest": "UNSIGNED:tuf-root"
    },
    {
      "id": "finance-snapshot",
      "registry": "finance",
      "kind": "tuf-snapshot",
      "path": "metadata/1.snapshot.json",
      "digest": "UNSIGNED:tuf-snapshot"
    },
    {
      "id": "finance-targets",
      "registry": "finance",
      "kind": "tuf-targets",
      "path": "metadata/1.targets.json",
      "digest": "UNSIGNED:tuf-targets"
    },
    {
      "id": "finance-timestamp",
      "registry": "finance",
      "kind": "tuf-timestamp",
      "path": "metadata/1.timestamp.json",
      "digest": "UNSIGNED:tuf-timestamp"
    },
    {
      "id": "loan-rules-statement",
      "registry": "finance",
      "kind": "release-statement",
      "path": "statements/loan-rules-1.0.0.json",
      "digest": "UNSIGNED:loan-rules-dsse-envelope"
    }
  ]
}
```

## Both registry record shapes, intentionally nonconforming

Each is shown in readable form. After replacing the unavailable envelope reference with
real signed-envelope evidence, a published record must use canonical JSON plus exactly
one LF, and its acquisition must hash those exact stored bytes. These code blocks are
not stored record bytes, and the `UNSIGNED:` references are not valid digests.

```json
{
  "formatVersion": "0.1.0-draft.3",
  "kind": "LibraryRegistryRecord",
  "release": {
    "packagePath": "example.com/finance/eligibility",
    "version": "1.2.0"
  },
  "irPackageName": "example/eligibility",
  "dependencies": [],
  "manifestDigest": "sha256:7441f6bc460eeded5a5c5a286d07256fd0eaaca93bcb1fe8ea97c8dcd920532c",
  "contentDigest": "sha256:5922bc8860f6cd008b9cda341be7f3a776ea332e63261392e94c17e19a647886",
  "source": {
    "kind": "registry-directory",
    "path": "bundles/5922bc8860f6cd008b9cda341be7f3a776ea332e63261392e94c17e19a647886"
  },
  "statement": {
    "path": "statements/eligibility-1.2.0.json",
    "digest": "UNSIGNED:eligibility-dsse-envelope"
  }
}
```

```json
{
  "formatVersion": "0.1.0-draft.3",
  "kind": "LibraryRegistryRecord",
  "release": {
    "packagePath": "example.com/finance/loan-rules",
    "version": "1.0.0"
  },
  "irPackageName": "example/loan-rules",
  "dependencies": [
    {
      "irPackageName": "example/eligibility",
      "packagePath": "example.com/finance/eligibility",
      "versionRange": {
        "minimumInclusive": "1.0.0",
        "maximumExclusive": "2.0.0"
      }
    }
  ],
  "manifestDigest": "sha256:23bbfeda3a3539a0a27546f5e261c4b325c3484327157898f0c54cbe36a8c9c2",
  "contentDigest": "sha256:345706de972523b65c8711a4367d61f143035770145519576aeaaf18733d874e",
  "source": {
    "kind": "registry-directory",
    "path": "bundles/345706de972523b65c8711a4367d61f143035770145519576aeaaf18733d874e"
  },
  "statement": {
    "path": "statements/loan-rules-1.0.0.json",
    "digest": "UNSIGNED:loan-rules-dsse-envelope"
  }
}
```

The complete unsigned payload values are [eligibility](eligibility-statement-payload.json)
and [loan-rules](loan-rules-statement-payload.json). Neither contains source locations,
registry aliases, mutable status, signatures, or claims about local verification.

## Remaining signed-fixture gate

A later contract fixture must supply actual canonical payload bytes, DSSE envelopes,
immutable record bytes, TUF role metadata, authorized test-only keys, and every matching
digest. Its historical metadata references must resolve to real retained files. The
shared MCK core must distinguish successful structure checks from failed authentication
of unsigned data. None of that evidence is claimed by this review directory.
