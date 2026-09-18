---
status: accepted
---

# ADR-0009: Use an explicit source root for compilation identity

A MEP compilation contains one package and a complete set of source documents.
Hosts provide a source root when several documents use absolute URIs. The SDK
validates their relative identities through one shared contract, while each
frontend owns the mapping from those paths to language-specific module names.
The root remains `options.sourceRootUri` to preserve the existing request shape.

Inferring the common ancestor would change module identities when a caller adds
or removes documents. Per-document module IDs or multiple roots would require
new import and collision rules. One explicit root avoids both problems and
works for CLI files, editor buffers, and generated-source round trips. The
single-absolute-document basename fallback remains for existing callers; hosts
that require stable nested identity should always supply a root.

Exposure is separate from source inclusion. An omitted list exposes all modules,
an empty list exposes none, and a nonempty list names the public modules. This
preserves ad hoc requests while representing private modules without discarding
their definitions. Generated Python retains the code, but requires the original
exposure metadata when recompiled because Python has no equivalent module access
modifier. See the [contract](../design/project-compilation-context.md).
