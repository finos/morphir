//! The state the session's `startup` phase resolves.
//!
//! Lives in its own module, rather than inline in `main.rs`, because
//! `commands::compile` needs to name the type too, and `commands` is
//! compiled under both the `morphir` library and binary crate roots
//! (`lib.rs` and `main.rs` each declare `mod session;`, alongside the same
//! split every other module `commands` depends on already has, such as
//! `error` and `output`). `MorphirSession` and the rest of the lifecycle
//! machinery stay in `main.rs`: they exist only for the binary.

/// What `startup` produced, available to every later phase.
///
/// A command that compiles gets the compile `startup` prepared through the
/// same preparation every compile entry point uses, rather than `startup`
/// predicting which route a later handler will take; every other command
/// reaches this state without touching the filesystem at all.
#[derive(Debug, Default)]
pub struct Ready {
    compile: std::sync::Mutex<Option<crate::commands::compile::PreparedCompile>>,
}

impl Ready {
    /// A state carrying one prepared compile.
    pub fn with_compile(prepared: crate::commands::compile::PreparedCompile) -> Self {
        Self {
            compile: std::sync::Mutex::new(Some(prepared)),
        }
    }

    /// Take the prepared compile. A compile runs once, so a second call, or a
    /// call from a command that prepared none, answers `None`.
    pub(crate) fn take_compile(&self) -> Option<crate::commands::compile::PreparedCompile> {
        self.compile
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .take()
    }
}

pub(crate) use Ready as SessionReady;
