# Morphir target-name metadata

`finos/morphir-metadata` interprets a bounded naming adapter in rich engine metadata.
It has no filesystem, network or process access. It preserves authored Ion values;
its result records consumed assertions separately from the original data.

The contract follows the [finos/morphir linked-metadata draft](https://github.com/finos/morphir/blob/23e7dfa4202d45fe74ef05e5214c0890125325d6/docs/design/draft/ir/linked-metadata.md)
and [fixed reference cases](https://github.com/finos/morphir/blob/23e7dfa4202d45fe74ef05e5214c0890125325d6/spec/ir/mck/metadata-contract-draft.md)
at `23e7dfa4202d45fe74ef05e5214c0890125325d6`. Local tests use independent expectations.
They do not qualify native IR 4.1, an Ion IR profile, JSON-LD or the upstream MCK.

## Selected declaration

The consumer selects this production binding, distinct from upstream `acme` fixtures:

```text
morphir://ir/pkg/morphir/naming?format=4.1.0#/module/naming/value/target-names
```

This binding requires a host-supplied authenticated provider. This repository does
not ship a signed provider release or a signature verifier. The `fixtures` package
simulates host restoration for tests; it is never an automatic provider source.

| Provider contract | Required declaration |
| --- | --- |
| Distribution | Freshly authenticated signed `morphir/naming` Library, native format `4.1.0` |
| Declaration | Public `naming` module with public `target-names` ValueDefinition |
| Output type | Closed record with exactly `frontend` and `backend`, both `Dict String String` |
| Native schema facts | `subject-role = ValueDefinition`, `object-form = data`, `interpreter = target-name-language-ids` |
| Schema vocabulary | `morphir://ir/pkg/morphir/metadata?format=4.1.0#/module/schema/value/` |
| Identity | Exact restored SHA-256 revision and matching revision-pinned distribution URI |

The schema facts must occur in the restored provider's own document `$meta.@graph`
and name its declaration as subject. A companion schema file cannot replace them.
A predicate URI may pin `rev=sha256:<digest>`; the restored revision must match.
Every interpretation run invokes the restoration capability anew. Restores are reused
only for equal expanded predicates within that run. A digest alone never admits a provider.

`RestoredLibrary.core` is the supported semantic projection of the restored Library.
The host must supply its native `$meta` and authenticated identity together. The core's
current 4.0 codec is not used to claim a native 4.1 restore. The host is responsible for
fresh signature authentication and for deriving the projection from those same bytes.

## Engine adapter and authored assertions

Store this payload in one owned `IRUnit.metadata` entry. Its annotation selects the
adapter; arbitrary other metadata stays opaque. The local `node_id` is the engine
storage holder. `document` identifies the containing assertion document, and each
`@id` identifies a semantic subject. Those identities can differ.

```ion
morphir_linked_metadata_v1::{
  document: "morphir://ir/pkg/example/annotations?format=4.1.0#/distribution",
  '$meta': {
    '@context': {
      targetNames: {
        '@id': "morphir://ir/pkg/morphir/naming?format=4.1.0#/module/naming/value/target-names",
        '@type': "@json"
      }
    },
    '@graph': [{
      '@id': "morphir://ir/pkg/example?format=4.0.0#/module/main/value/ready",
      targetNames: {
        frontend: {moonbit: "isReady"},
        backend: {moonbit: "chosen"}
      }
    }]
  }
}
```

Only current, unpinned ValueDefinition subjects in the input Library are consumed.
Body, attribute, type, specification, workspace and ordered-child subjects are outside
this consumer's supported role. Native ValueDefinition facts belong in `$meta.@graph`;
putting them on a body expression changes their subject. This envelope is an engine
adapter, not a native carrier or a new IR format. The current JSON loss guard stays intact.

Both maps are required; empty maps are valid. Language IDs follow
`^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$`. Spelling strings stay opaque, including URI-looking
text. The MoonBit generator separately checks `backend.moonbit` as a target identifier.
Equal authored assertions retain separate holder/document/carrier/property/ordinal
receipts. Contradictory records fail with their owner and contributing documents.
`assertionSources` selectors must match expanded assertions from the same document
and supply one complete, nonempty source set. Authored sources remain in the original
payload; source claims are not authentication evidence.

## Context acquisition and scope

Contexts follow artifact then document scope. This slice consumes document graphs;
node `attributes` and specification `annotations` are not projected by this adapter.
Inline contexts, compact prefixes, exact aliases and canonical `@vocab` are supported.
Narrow scopes can replace unprotected aliases; protected bindings cannot be replaced.
Unsupported JSON-LD keywords fail before any result leaves the interpreter.

A context reference is a relative `.jsonld` path or
`morphir://context/sha256/<64 lowercase hex digits>`. References never cause HTTP
fetches. `contextBase` can carry a file-base hint for relative imports. The explicit
host loader must confine paths to its accepted workspace or verified archive root,
resolve symlinks, inventory exact bytes and reject escape. A metadata-supplied base
cannot widen that root. The portable consumer checks SHA-256 bytes before parsing,
rejects cycles and repeated resources, and rejects conflicting imports before a
trailing override. Content-addressed contexts have no relative file base.

Bounds are 32 import levels, 256 resources per closure, 1 MiB per context document,
and 100,000 expanded assertions per graph. Context files must be UTF-8 JSON with
exactly one `@context` member and no duplicate object members.

## Host capabilities

Pass `Capabilities` to `interpret`, `generate(metadata_capabilities=...)`, or
`Engine::new(metadata_capabilities=...)`. Capabilities are supplied by application
code. Metadata and CLI configuration cannot install a restoration callback.

The defaults have no provider or context loader and no required naming interpreter.
Generation fails clearly on a known naming fact without admission or interpretation;
it never silently substitutes an automatic spelling. The installed CLI currently has
no signed-Library restore integration. It can preserve these payloads in checkpoints,
but cannot generate from known naming facts until a host integrates that service.
Unknown syntactically valid predicates remain preserved and are listed as unvalidated.

```sh
moon test -p finos/morphir-metadata --target all
```

The shared `v4.1-document-metadata-to-v4.0/1` projection is qualified against a
signed test naming Library in `finos/morphir-rust`. Its authority-qualified
release is `example.com/morphir/naming@1.0.0`; its native IR identity remains
`morphir/naming` at 4.1.0. The interoperability test reads the shared v4.0 core
view, original native document metadata and exact context bytes, then validates
the closed frontend/backend declaration through a simulated host capability.
The provider revision hashes the original native payload, not the core view.

This qualifies data interoperability. Fresh authentication and restoration are
verified separately by the Rust signed-fixture tests; installed host sessions
and process transport remain separate integration work. The first projection
profile refuses node-local linked metadata and nonlexical parameter maps.

The [shared signed fixture](https://github.com/finos/morphir-rust/blob/3b55adfa831c6dcfb749e4e74c301e924124490c/crates/morphir-package/tests/local_registry/naming-snapshot-fixture/README.md)
pins the source corpus used by the consumer test.
