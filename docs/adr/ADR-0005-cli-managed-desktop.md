---
status: accepted
---

# ADR-0005: Manage Morphir Desktop as a tool from Morphir Home

Morphir Desktop is the well-known user-launched tool `desktop`, not an extension. The CLI acquires, verifies, activates, updates, repairs, and launches it through the same distribution kernel used by extensions while retaining separate tool and extension catalogs and commands. `morphir desktop` installs the configured Desktop selection when no active release exists unless `--offline` forbids network access. Every participating component resolves one Morphir Home for configuration, durable state, managed artifacts, caches, and logs, with namespaced ownership inside that root.

We rejected a Desktop-specific installer because it would duplicate release selection, integrity checks, locking, and rollback. We also rejected treating Desktop as an extension because people launch tools while Morphir hosts invoke extensions for capabilities. `morphir setup` remains an optional, idempotent onboarding workflow that delegates to the normal tool and extension operations rather than owning another installation path.
