//! The fixed part of a kit's input closure (`spec/mck/kit-manifest.md`):
//! parent-owned files every snapshot carries whatever its cases name. The
//! rest of the closure is every file under the kit directory and every
//! external fixture a case step names.
//!
//! Std-only: the build script includes this file by path.

/// Repository-relative paths of the fixed inputs of the IR suite. A schema
/// that gains an external `$ref` adds the referenced file here in the same
/// change.
pub const FIXED_INPUTS: &[&str] = &[
    // The coverage vocabulary `morphir mck coverage` reads.
    "spec/mck/vocabulary.json",
    // The schemas `morphir mck schema check` validates fences against.
    "website/static/schemas/morphir-ir-v4.json",
    "website/static/schemas/morphir-ir-v4-document-tree-files.json",
    // Metaschema and example gates run from installed/vendored kits too.
    "spec/mck/vocabulary.schema.json",
    "spec/mck/mck-kit.lock.schema.json",
    "spec/mck/mck-kit.lock.example.json",
    "spec/mck/provenance.schema.json",
];
