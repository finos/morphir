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
/// Only `startup` constructs one. `config` keeps the `Option` the current
/// loader has, because a run legitimately has no configuration file; the
/// change here is that exactly one place decides that, rather than each
/// command deciding for itself. The `Option` goes away when `EffectiveConfig`
/// replaces `ConfigContext`, which is a later increment.
///
/// `start_dir` is also an `Option`, and for the same reason `config` is:
/// `startup` only calls `std::env::current_dir()` when it is actually
/// resolving configuration (a whole-project compile). Every other command
/// must reach `Ready` without touching the filesystem, so it gets `None`
/// here rather than a syscall it doesn't need, or a placeholder that would
/// misrepresent "no working directory was read" as a real path.
///
/// `startup` is the only producer; `run_provider_compile` is the only
/// consumer, via [`Ready::start_dir`] and [`Ready::config`].
#[derive(Debug)]
pub struct Ready {
    pub(crate) start_dir: Option<std::path::PathBuf>,
    pub(crate) config: Option<morphir_devkit::ConfigContext>,
}

impl Ready {
    /// Where the run started, used to resolve relative paths. `None` unless
    /// `startup` resolved configuration for a whole-project compile, which
    /// matches [`Ready::config`]: both are `Some` together, or `None`
    /// together.
    pub(crate) fn start_dir(&self) -> Option<&std::path::Path> {
        self.start_dir.as_deref()
    }

    /// The loaded configuration, if this run is a whole-project compile.
    pub(crate) fn config(&self) -> Option<&morphir_devkit::ConfigContext> {
        self.config.as_ref()
    }

    /// Builds a `Ready` without running the startup phase. Tests only.
    ///
    /// Sets `start_dir` while leaving `config` `None`, which breaks the pair
    /// invariant the two fields otherwise hold. That is deliberate here: it
    /// lets a test exercise the "no configuration" branch of a consumer
    /// while still handing it a real directory to assert against.
    #[cfg(test)]
    pub(crate) fn for_test(start_dir: std::path::PathBuf) -> Self {
        Self {
            start_dir: Some(start_dir),
            config: None,
        }
    }
}

pub(crate) use Ready as SessionReady;
