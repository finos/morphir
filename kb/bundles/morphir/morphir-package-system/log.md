# Log

## 2026-09-16

* **Update**: Refreshed the landing baseline to Morphir PR #813, commit `2cd0dcd0`, and its TypeScript pin `46197e2`. The naming-corpus drift check now passes with Rust pin `933fcf5`; verification of Rust test coverage remains separate.
* **Update**: Recorded the agreed staged binding and resolution compromise in the [package design](/package-system-design.md). Core IR definitions and references remain release-version-free. Common cases use one implicit dependency binding per IR Package name in each consumer; packaging selects exact releases.
* **Update**: Added canonical IR examples, the resolution search approach, and MCK scenarios. Stage 0 fixes deterministic policy and baseline capability boundaries; Stage 1 delivers ordinary packaging without a new reference encoding. Graph-aware coexistence and explicit direct multi-binding remain Stage 3 work.
* **Update**: Preserved decision 0015's current bare `@` layout rule. A future distribution/layout change does not require release versions in core definitions or FQNames. No resolver, codec, or schema change is claimed by this design update.

## 2026-09-15

* **Update**: Incorporated merged Morphir PRs #810 and #812 and TypeScript PRs #9 and #10. Dependency directories now require the decision 0015 `@` boundary; the current model accepts only the bare slot. Captured package-relative Module names, `package:module` qualification, duplicate-name rejection, and the naming corpus's separate fixture requirements.
* **Update**: Verified 113 focused TypeScript naming and tree tests and the 620 passing MCK records on both transports, with two v3 skips each. Filed `morphir-klsu` for the older naming corpus in the pinned Rust checkout.
* **Update**: Adopted Morphir Compatibility Kit (MCK) branding for the planned package suite at `spec/package/mck/`. Stage 0 now includes versioned MCK integration and required-capability checks across two independent implementations.
* **Update**: Reconciled the [package design](/package-system-design.md) with Morphir PR #809 and morphir-typescript PR #8. Recorded the pending Morphir PR #810 integration, the embedded kit revision, current IR graph limits, and the separate roles of codec normalization, package content digests, and kit provenance.

## 2026-09-05

* **Creation**: Added the [Morphir model package system](/package-system-design.md) design after the review captured in [finos/morphir#800](https://github.com/finos/morphir/issues/800).
