## REMOVED Requirements

### Requirement: No trust step
**Reason**: `extensions/trust` now decides when a repository needs a trust decision, and its requirements prompt for
the same operations that this requirement exempted.

**Migration**: Run `morphir trust add <name>`, answer the prompt, or pass the unattended acceptance options that
`extensions/trust` defines. Repositories that were already enabled follow the trust requirements on their next install
or update.
