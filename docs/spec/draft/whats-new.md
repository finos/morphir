---
title: "What's New in Version 4"
description: "Summary of changes in Morphir IR v4"
sidebar_position: 0
---

# What's New in Version 4 (Draft)

Morphir IR v4 introduces significant architectural changes to support a polyglot, tool-friendly ecosystem.

## Key Changes

### 1. Document Tree Layout
v4 introduces a **Document Tree** distribution mode (`.morphir-dist/`), alongside the Classic single-blob mode.
- **Granular Files**: One file per type/value definition.
- **Incremental Builds**: Compilers can touch specific files.
- **Shell Friendly**: Standard tools (`grep`, `find`) can inspect the IR.

### 2. Removal of Generic Parameters
The generic type attribute parameter `a` (present in v1-v3) has been removed.
- **Structured Attributes**: Replaced by explicit `TypeAttributes` and `ValueAttributes` structures.
- **Standardization**: Attributes now have a standard schema including source location and constraints.

### 3. Canonical String Naming
Names, Paths, and Fully-Qualified Names now serialize to **canonical strings** instead of arrays.
- **Readability**: `"Morphir/SDK:List#map"` instead of nested arrays.
- **Keys**: Names can now be used directly as JSON object keys.
- **Legacy Support**: Array decoding is still supported for backward compatibility.

### 4. Canonical Module Definitions (`module.json`)
First-class support for `module.json` manifests, allowing modules to be defined flexibly within the Document Tree.

## Migration Guide

(Coming Soon: Guide for migrating v3 IR to v4)
