//! Private workflow operand compiler, not registered capability or authority.
mod decode;
use decode::*;
#[macro_use]
mod macros;
mod compile;
mod domain;
mod expansion;
mod input;
mod meaning;
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
