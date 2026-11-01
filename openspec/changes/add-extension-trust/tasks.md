# Tasks

## 1. Trust decisions and prompts (morphir-ukvn.5.64.34.3)

- [ ] 1.1 Store trust records in `extensions/v1/trust.json` with what was shown, compile in the `finos` default trust
  and owner identity, and take other owner identities from `index.json` (TRUST-1); verify the "Trust belongs to the
  user" and "Trust is recorded with what was shown" scenarios
- [ ] 1.2 Add `morphir trust add|list|remove` (TRUST-3); verify the "Trust command" scenarios
- [ ] 1.3 Add the single trust prompt to `extension install` and `extension update`, the `setup` review screen, and
  on-demand installation in compile and generate; verify the "One trust prompt per operation" scenarios with
  interactive-input tests
- [ ] 1.4 Add `--trust` and `--trust-all` to every prompting command, with non-interactive failure before any
  download; verify the "Unattended trust" scenario and the "Untrusted repository" scenario
- [ ] 1.5 Document trust for users in `apps/morphir/docs/extension.md`; verify the documented `morphir trust` commands
  run as written

## 2. Sigstore verification of releases, indexes and admission (morphir-ukvn.5.64.35.1)

- [ ] 2.1 Pin the published Moon-Lander Sigstore package in the acquisition package and embed the Sigstore
  public-good trusted root (SIG-1); verify on native and js with the package's GitHub attestation fixtures
- [ ] 2.2 Verify artifact attestations at install from the `.sigstore.json` asset, falling back to the attestations
  API, and store the bundle in the lock (TRUST-2, SIG-1); verify the "Verified artifacts" scenarios with a bundle from
  another workflow
- [ ] 2.3 Verify the owner attestation of `index.json` against the trusted owner identity; verify the "Verified
  indexes" scenarios with a forged index, a valid index from a fixture repository, and a modified history under an
  unchanged valid root
- [ ] 2.4 Verify attestations in `morphir repository admit` and re-verify releases the MVP admitted (SIG-2); verify
  the "Verified admission" scenario in a test repository
- [ ] 2.5 Document verification and its failure messages; verify the docs build and each documented failure is
  produced by a test
