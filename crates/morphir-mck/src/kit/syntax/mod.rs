//! The kit's case grammar: pure functions from text to cases and errors.
//!
//! This module depends on nothing but `std`, and the build script includes it
//! by path to find the fixtures the embedded kit must carry. Keep it that way.

pub mod case;
pub mod info_string;
pub mod markdown;
pub mod text;
