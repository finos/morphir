# Signed preview-recipe inputs

These candidate inputs extend the [preview family](../../index.md) without
changing the historical signed repository. They are test data for the one .NET
runner, not a repository configuration, publisher authority or downloadable
release. No production composition may trust these keys.

`repository.json` contains a separate TEST-ONLY root, timestamp/snapshot/targets
envelopes, target bytes, a later recipe revocation and refusal inputs.
`cases.json` supplies six independent expected outcomes. No signature, trust
refresh or recipe authentication has yet been executed against these inputs in
the shared runner. Parent tests check metadata integrity and payload schemas
only. Those tests do not authenticate signatures or resolve a closure.

## Fixed authority and bytes

The root requires two signatures from distinct root keys. Targets, snapshot and
timestamp each have a separate key. Every public fixture seed is the SHA-256 of
the UTF-8 label `Morphir preview toolchain TEST-ONLY fixture key: <role>`, where
`<role>` is `root-1`, `root-2`, `targets`, `snapshot` or `timestamp`. These labels
are deliberately public. They are not production secrets or bootstrap roots.

Authoring used Ed25519 and the [RFC 8410 PKCS#8 seed encoding](https://www.rfc-editor.org/rfc/rfc8410.html#section-10.3).
The signed JSON subset contains only ordinary integers, strings, arrays,
booleans and objects. Authoring serialized objects with keys in increasing
ordinal order, arrays in their declared order and no insignificant whitespace.
Signatures cover those canonical `signed` bytes. Lengths and SHA-256 links cover
the canonical complete envelope bytes, including signatures. The initial root's
canonical signed text is retained as `initialRootSignedBytes`; its UTF-8
SHA-256 is `repositoryId`. The maintained reader must apply its existing TUF
canonicalization and checks, rather than trust this retained text as a shortcut.

All roles expire in 2999 except the deliberately expired timestamp. Every case
uses the explicit `referenceTime`, 2030-01-01T00:00:00Z, rather than the machine
clock. The invalid targets signature is still a correctly sized hex string;
snapshot and timestamp links are recomputed and signed around it. That control
must fail signature verification, not a stale envelope link.

The recipe's target record uses the [candidate recipe metadata rules](../../index.md#authenticated-recipe-targets).
The outer TUF profile and tool-release descriptors retain their v1 authorities.
Extension descriptors use their separately published extension preview schema.
No historical `schemaVersion` record is rewritten or converted by a reader.

## Cases and closure

| Case | Intended observation |
| --- | --- |
| `authenticated-preview-recipe` | Accept the recipe after trusted refresh, exact target verification and current-family reading |
| `recipe-length-refused` | Refuse target bytes shortened by one byte |
| `recipe-digest-refused` | Refuse changed bytes with the same byte length |
| `metadata-signature-refused` | Refuse the relinked metadata containing an invalid targets signature |
| `timestamp-expiry-refused` | Refuse a signed but expired timestamp |
| `learned-recipe-revocation-refused` | Refuse the same recipe digest after accepting later metadata that revokes it |

The last case requires a fresh session to accept the base metadata, then the
version-2 timestamp, snapshot and targets. A previous accepted target must not
override the newly learned revocation. Other cases start from the supplied root
without inheriting another case's cache. Each case reads `metadata` and optional
`timestamp` as paths within the supplied repository object, not filesystem or
network locations. `targetBytes`, when present, replaces only the selected
target's returned bytes. Unknown operations or selectors must be refused as
unsupported test inputs, never counted as passed or silently skipped.

The positive recipe binds all four host offerings and both process providers
for six native platform pairs. The three archive offerings have v1 release
descriptors; the tool offering binds one portable NuGet target and declares both
its .NET 10 runtime and install-phase SDK prerequisites. This does not claim
that the package bundles a runtime. Frontend and
backend each have an extension descriptor and six target identities. Every
target record's length and digest match its supplied bytes. The artifact bodies
are deliberately inert TEST-ONLY text, despite archive, executable and package
filenames. They must never be extracted, installed, launched or used to claim
packaging, readiness, prerequisites or F# qualification.

These six cases cover authentication basics. The following binding cases add
some descriptor/recipe disagreement controls. Incomplete platform closures,
critical-member rules, generation/offline restore and acquired-artifact
workflows still need their own cases and execution. Task 1.6 and the family
cutover remain open.

## Authenticated binding cases

`binding-cases.json` adds eight fixed expectations for
`check-recipe-bindings`. It binds the exact bytes of
`binding-repositories.json` by SHA-256. The latter retains the original root,
repository identity and reference time, records the original repository file's
SHA-256, and supplies a complete metadata/target-file set for each named variant.
The original repository and its six authentication cases are unchanged.

Every case starts independently from that root. Refresh its selected metadata,
authenticate and read the recipe, then apply the host and provider binding
checks before resolution or acquisition. The immutable identity, repository,
target digest, platform, protocol and model comparisons retain the rules in the
[recipe binding tables](../../../toolset-recipe.md#authenticated-recipe-targets).
Read preview recipes and extension descriptors at their own exact schema URLs;
do not invoke the historical recipe or extension codecs as a fallback.

| Case | Expected outcome and first path |
| --- | --- |
| `complete-bindings-accepted` | Accept all four host offerings and both process providers |
| `host-descriptor-identity-refused` | `release_descriptor_mismatch` at `hosts[0].source` |
| `host-platform-substitution-refused` | `artifact_platform_mismatch` at `hosts[0].platforms.win-x64.target` |
| `provider-repository-substitution-refused` | `repository_mismatch` at `providers[0].repositoryId` |
| `provider-descriptor-digest-refused` | `target_digest_mismatch` at `providers[0].descriptorSha256` |
| `provider-protocol-disagreement-refused` | `release_descriptor_mismatch` at `providers[0].protocolVersion` |
| `provider-model-disagreement-refused` | `release_descriptor_mismatch` at `providers[0].modelTuple` |
| `provider-artifact-digest-refused` | `target_digest_mismatch` at `providers[0].platforms.win-x64.artifactSha256` |

Each variant's changed target bytes have new authenticated lengths/digests and
newly signed targets, snapshot and timestamp envelopes. This deliberately avoids
an earlier stale-link or target-corruption failure masking the intended binding
comparison. For example, the host-platform case binds the authenticated Linux
artifact to the Windows slot; it does not corrupt the artifact's bytes. The
host-identity case changes the authenticated descriptor's own tool id while
retaining its original authenticated release state. Expected paths use the
existing binding order, not a new diagnostic vocabulary.

All 48 JSON payloads across these variants pass their own schemas. Parent tests
also check byte links, manifest inventory and fixed expectations. They execute
no signature verifier or binding checker. No case has yet established its
intended outcome through the shared .NET runner. Unknown operations or variant
names must be refused, and no row may be silently skipped. Artifact bodies
remain inert text and must never be installed or launched.

These cases do not cover every binding or cutover rule. Missing platform
closures, critical paths, generation state, frozen/offline restore, developer
consent and acquired-artifact workflows still require their own cases and
behavioral evidence. Tasks 1.6 through 1.8 remain open.
