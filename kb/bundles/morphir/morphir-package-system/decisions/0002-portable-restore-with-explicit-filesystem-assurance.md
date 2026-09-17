---
type: Decision Record
title: Portable restore with explicit filesystem assurance
description: Portable restore targets Linux, macOS and Windows while preserving authentication and durable trust state.
state: Accepted
decided: 2026-09-17
tags: [packages, restore, filesystem, security, mck]
status: stable
---

# Portable restore with explicit filesystem assurance

We chose [portable restore](/glossary.md#portable-restore) on Linux, macOS and Windows
as the first delivery target. We retained package authentication and durable trust-state
requirements in both portable and hardened modes. We required explicit mode selection
and rejected automatic downgrade from a hardened request.

This decision belongs to the [package system design](/package-system-design.md#restore-filesystem-assurance).
It records a delivery boundary, not implemented platform support.

## Summary

The original restore contract required protection against hostile concurrent filesystem
replacement. Making that protection a prerequisite on every platform delayed ordinary
local consumption. We separated that protection from verification of untrusted package bytes.

| Option | Outcome | Why |
| --- | --- | --- |
| Portable restore first, with separately qualified hardened providers | Chosen | Supports ordinary local use without weakening package trust |
| Require hardened providers on every platform before first delivery | Rejected | Makes host hardening a prerequisite for all local consumption |
| Require Seatbelt or a specially configured macOS volume for ordinary restore | Rejected | Adds deployment constraints to the baseline experience |
| Silently fall back after a hardened failure | Rejected | Changes the caller's security requirement without consent |
| Relax signatures, rollback protection or durable state along with filesystem hardening | Rejected | Changes package authority rather than filesystem assumptions |

## Why

Portable mode assumes caller-controlled local directories without hostile concurrent
modification. Package contents remain untrusted. The client still verifies repository
and publisher authority, exact locked bytes, IR identity and dependencies before use.

The distinction matters when a local process replaces a regular file with a device
between inspection and open. Portable mode excludes that attacker from its environment
assumption. Hardened mode must prevent the unsafe access despite the replacement.
Both modes reject a device they detect; neither executes package hooks.

The [original staging contract](../../../../../spec/package/local-library-contract.md#safe-staging-and-materialization)
remained the hardened baseline. Its required security-state recovery was not a
filesystem convenience that could be dropped. A lost rollback floor can authorize an
older signed view even when every operation requests fresh verification.

## Consequences

The [assurance addendum](../../../../../spec/package/restore-filesystem-assurance.md)
defines the scope of the relaxation. The host selects and reports the mode outside
package metadata. A hardened request fails if its provider is unavailable.
Portable mode still needs qualified write exclusion, promotion and durable state.

MCK must identify separate versioned execution profiles and required cases. Existing
draft.3 expectations remain unchanged. Passing portable tests cannot establish hardened
compatibility, and neither a definition check nor a missing-case skip establishes either.

We kept `morphir.lock`, release identity and IR naming unchanged. Model packages,
executable extensions and installable tools retained distinct artifact contracts.

## Unresolved

The portable execution/report schema and platform providers still require implementation
and review. No OS is qualified by this decision. Windows persistence and recovery need
their own evidence; Linux or macOS tests cannot substitute for it.

## Revisit when

Revisit the baseline if a deployment cannot enforce the trusted-local-filesystem
assumption, or if qualified hardened providers become practical on all supported hosts.
Do not broaden the portable threat model through an implementation workaround.
