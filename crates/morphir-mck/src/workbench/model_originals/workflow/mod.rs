//! Private workflow operand compiler, not registered capability or authority.
mod decode;
use decode::*;
#[macro_use]
mod macros;
mod compile;
mod domain;
mod expansion;
mod identity_input;
mod input;
mod installed_client;
mod installed_measurements;
mod meaning;
pub mod native;
pub use pipeline::installed::adapter as installed;
mod native_original;
mod pairing;
mod scope;
mod walk;
mod work;

#[cfg(test)]
mod tests;

#[cfg(test)]
mod translated_tests;

#[cfg(test)]
mod input_shapes_tests;

#[cfg(test)]
mod input_boundaries_tests;

#[cfg(test)]
mod input_corpus_tests;

#[cfg(test)]
mod paired_corpus_tests;

mod ingress;

mod reviewed_sources;
mod source_proof;

mod source_compile;

#[cfg(test)]
mod bound_input_tests;

#[cfg(test)]
mod observed_tests;

mod observation_check;
mod observed;
mod record_check;

#[cfg(test)]
mod identity_tests;

#[cfg(test)]
mod report_context_tests;

#[cfg(test)]
mod context_checker_tests;

#[cfg(test)]
mod report_record_tests;

#[cfg(test)]
mod identity_source_baseline_tests;

#[cfg(test)]
mod record_boundary_tests;

#[cfg(test)]
mod record_boundary_support;

#[cfg(test)]
mod identity_additive_source_tests;

#[cfg(test)]
mod record_attempt_tests;

#[cfg(test)]
mod fixture_tests;

#[cfg(test)]
mod pipeline_tests;

#[cfg(test)]
mod workspace_predicate_tests;

pub(in crate::workbench) mod pipeline;

#[cfg(test)]
mod factory_tests;

#[cfg(test)]
mod pipeline_negotiation_tests;

#[cfg(test)]
mod pipeline_negotiation_evidence_tests;

#[cfg(test)]
mod native_original_unit_controls;
