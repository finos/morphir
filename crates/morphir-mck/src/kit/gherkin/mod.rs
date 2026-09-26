//! The kit's `.feature` case files: the Gherkin step vocabulary, the lowering
//! of a `.feature` case file into kit cases, and the converter that writes
//! `.feature` text from Markdown cases.
//!
//! [`vocabulary`] parses one step's text, with its optional doc string, into a
//! [`vocabulary::KitStep`], and prints a `KitStep` back as step text.
//! [`lower`] reads a `morphir-gherkin` document into the engine's `KitCase`
//! model. [`convert`] writes `.feature` text for a Markdown file's cases.

pub mod convert;
pub mod lower;
pub mod vocabulary;
