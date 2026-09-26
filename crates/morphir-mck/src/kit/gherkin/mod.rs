//! The kit's `.feature` case files: the Gherkin step vocabulary, the lowering
//! of a `.feature` case file into kit cases.
//!
//! [`vocabulary`] parses one step's text, with its optional doc string, into a
//! [`vocabulary::KitStep`], and prints a `KitStep` back as step text.
//! [`lower`] reads a `morphir-gherkin` document into the engine's `KitCase`
//! model.

pub mod lower;
pub mod vocabulary;
