---
status: proposed
---

# ADR-0007: Use TUF for tool release trust

Morphir tool repositories use The Update Framework 1.0 for publisher authentication, root rotation, metadata expiry, rollback protection, and artifact integrity. Morphir defines a small application profile inside signed TUF target metadata for tool identity, exact versions, channels, compatibility, status, and platform availability. Release descriptors and artifacts remain ordinary TUF targets.

A custom signed index would make Morphir responsible for security rules that TUF already specifies and tests. Artifact signatures alone would authenticate bytes but would not provide safe channel movement, freshness, or root rotation. TUF keeps those concerns in a standard trust workflow while allowing Morphir to define its own release model.

The first profile requires consistent snapshots and SHA-256 target hashes. Production roots use Ed25519 keys with a threshold greater than one. Mirrors are transport locations for the same logical repository and never establish separate trust. The choice of Rust TUF client remains an implementation decision as long as it follows the profile and passes the shared conformance fixtures.
