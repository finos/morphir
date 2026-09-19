//! Talking to an implementation's adapter process: the IR protocol, version 1,
//! and the session that carries it.

pub mod protocol;
pub mod session;
mod tree;

pub use session::{Limits, Session, TransportError};
pub use tree::Terminator;
