# Proposal

## Why

`acquire-extensions-from-repositories` delivers the MVP extension pipeline without trust, so that repository, install,
publishing and setup work is not blocked on signature verification. In that MVP the CLI installs from any enabled
repository and cannot show who published an artifact. Publishers and repository owners already attest releases and
indexes with GitHub artifact attestations; nothing checks them yet. This change is the fast follower: the user decides,
once and simply, which repositories to trust, and the CLI verifies that each artifact and index came from the
identities that trust names.

## What Changes

- **Trust belongs to the user.** Installing from a GitHub-hosted repository needs the user's trust in it. `finos` is
  trusted by default. Trusting a repository covers the publishers its owner admits.
- **One prompt, or none in CI.** One trust prompt per operation lists every new repository and publisher identity;
  `--trust <repository>` and `--trust-all` answer it ahead of time. `morphir setup`'s review screen and on-demand
  installation in compile and generate show the same prompt.
- **`morphir trust add|list|remove`.**
- **Verified releases.** Installation verifies each artifact's GitHub artifact attestation (Sigstore) against the
  publisher identity in the trusted index, and stores the bundle in the lock. Activation stays offline.
- **Verified indexes.** The CLI verifies the owner's attestation of each GitHub-hosted index against the trusted owner
  identity; an unverified index is searchable but not installable.
- **Verified admission.** The owner's admission workflow verifies each release's attestation against the registered
  publisher workflow, not only its repository.
- Local-directory repositories stay digest-only.

## Capabilities

### New Capabilities

- `extensions/trust`: trust decisions for repositories and publishers, the default trust, prompts, unattended
  acceptance, the stored trust record, and the attestation checks that trust relies on.

### Modified Capabilities

- `extensions/repositories`: removes the `No trust step` requirement of the MVP, because `extensions/trust` replaces
  it. This change therefore archives after `acquire-extensions-from-repositories`, which adds that requirement.

## Beads

- **Tracked by**: `morphir-ukvn.5.64.35`
- **Related**:
  - `morphir-ukvn.5.64.34` (the MVP pipeline this follows; its groups 1 and 2 must land first)
  - `morphir-ukvn.5.64` (parent: the MoonBit CLI becomes the primary Morphir CLI; its 2026-10-17 note made
    authentication optional, and this change makes it required for GitHub-hosted repositories)
  - the MoonBit Sigstore verifier being proposed in moonrockz/moon-lander (worktree `sigstore-verification`)

## Impact

- **Code:** the acquisition package (trust record, attestation and index checks), `apps/morphir` (`morphir trust`,
  prompts and options in install, update, setup, compile and generate), and `morphir repository admit`.
- **Dependencies:** the published Moon-Lander Sigstore package, and an embedded Sigstore public-good trusted root.
- **Users:** installs from repositories other than `finos` ask for trust once. CI adds `--trust` or `--trust-all`.
- **Publishers and owners:** no new steps; the MVP workflows already create the attestations.
