---
status: accepted
---

# ADR-0008: Distinguish repositories, registries, catalogs, and installed inventory

Morphir calls a logical collection of published releases, metadata, and artifacts a **repository**. A configured access location is a **repository endpoint**, a network service that hosts repositories is a **registry**, and the searchable view over enabled repositories is a **catalog**. Morphir Home's durable record of installed releases and active selections is an **installed inventory**. An index is one possible repository-metadata format, alongside TUF metadata and OCI manifests, rather than the public name for a repository or installed state.

This language follows the boundaries used by TUF and OCI while retaining the narrower Cargo and Helm meaning of an index as metadata within a repository. It also lets a local directory and a hosted service implement the same repository contract without calling the directory a registry. The unreleased CLI does not retain an `--index` compatibility flag. Existing `LocalIndex`, `InstalledCatalog`, and `catalog/` names remain internal migration details until their owning implementation adopts the domain terms. New user-facing commands use `repository`, discovery uses `catalog` or `search`, and installed-state output uses `inventory`.
