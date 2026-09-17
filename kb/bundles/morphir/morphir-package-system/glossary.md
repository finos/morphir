---
type: Glossary
title: Package restore terminology
description: Filesystem assurance terms distinguish portable restore from hardened restore.
tags: [packages, restore, filesystem]
status: stable
---

# Package restore terminology

These terms describe the approved [package restore design](/package-system-design.md#restore-filesystem-assurance), not shipped capabilities.

## Filesystem assurance

The local-filesystem threat assumptions and protections under which a package restore
runs. It does not determine repository or publisher authority.

## Portable restore

Restore that verifies untrusted package bytes while relying on caller-controlled local
directories without hostile concurrent filesystem modification. It retains durable
trust-state requirements. This mode is distinct from the portability of `morphir.lock`.

## Hardened restore

Restore that also meets the original contract's filesystem confinement and special-file
protections under hostile concurrent source-entry replacement. It retains the same
package authentication requirements as portable restore.
