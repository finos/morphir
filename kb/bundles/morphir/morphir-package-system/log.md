# Log

## 2026-09-16

* **Update**: Added the independent Rust package implementation and opt-in MCK package adapter. The same shared TypeScript driver reports all 80 draft cases passing against Rust with no failures, kit errors, or skips. Parent CI runs both implementations and retains their reports. Full locks, resolution, registry and trust behavior remain outside this slice; the user-facing lockfile remains `morphir.lock`.
* **Update**: Landed the shared TypeScript package core in [morphir-typescript #16](https://github.com/finos/morphir-typescript/pull/16) and its parent integration in [Morphir #815](https://github.com/finos/morphir/pull/815). The parent pins merged TypeScript commit `f308c9be27fa58af72c112fe4e16028568c3e6f4`.
* **Update**: Implemented the draft package suite in the TypeScript MCK core, with separate reference operations, versioned package contracts, fixed-result comparison and required-case gates. Parent invocation runs both transports. Added closed Library-set integrity cases for bytes, digests, names and binding targets. Upstream landing and the parent pin remain coordinated follow-up work; two transports are one implementation.
* **Update**: Accepted exact declared payload-byte hashing, with separate manifest normalization. Recompression preserves Package content identity; payload reformatting changes it. IR semantic equivalence is a separate check.
* **Update**: Recorded [decision 0001](/decisions/0001-package-compatibility-uses-the-shared-mck-core.md): package compatibility uses the shared TypeScript MCK core and implementation adapters. Retired the standalone prototype runners from deliverable tooling and made the language preference explicit in agent guidance.
* **Update**: Retained the first experimental Stage 0 specification slice: two v4 Libraries, manifest and partial lock-core schemas, and candidate schema/normalization/digest cases. Generic schema validation remains available. Shared package execution, full locks, resolution policy cases, trust contracts, and versioned package adapters remain unfinished.
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
