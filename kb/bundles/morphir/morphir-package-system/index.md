---
okf_version: "0.2"
title: Morphir package system
description: The proposed Morphir model package system defines artifact boundaries, release identity, dependency resolution, registry behavior, trust, and staged delivery.
---

# Morphir package system

The proposed Morphir model package system defines artifact boundaries, release identity, dependency resolution,
registry behavior, trust, and staged delivery.

## Design notes

* [Morphir model package system](/package-system-design.md) - The design defines an IR-first package system for reusable Morphir models across language implementations and repositories.

## Decisions

* [Package compatibility uses the shared TypeScript MCK core](/decisions/0001-package-compatibility-uses-the-shared-mck-core.md) - Package compatibility cases use the shared TypeScript MCK tooling and implementation adapters rather than separate compatibility runners.
