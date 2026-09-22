// Copyright 2026 FINOS
// SPDX-License-Identifier: Apache-2.0
use std::collections::BTreeMap;
pub type Files = BTreeMap<String, Vec<u8>>;
pub type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;
pub const CLOCK: &str = "2027-01-01T00:00:00Z";
pub const SIGNED_PATH: &str = "spec/package/mck/fixtures/local-registry/assets/signed";
mod generate;
mod io;
pub mod ordered;
pub mod signing;
mod verify;
pub use generate::generate;
pub use io::{check_files, read_files, read_inputs, write_files};
pub use verify::verify_tuf;
mod cli;
pub use cli::{Destination, parse_arguments};
mod dsse;
pub use dsse::{decode_hex, verify_dsse};
mod relationships;
pub use relationships::verify_relationships;
