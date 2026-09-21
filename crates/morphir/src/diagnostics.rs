//! Error reporting setup for the CLI.
//!
//! miette renders every error the CLI reports. Until now nothing configured
//! it, so it used the default handler miette's `fancy` feature installs.
//!
//! What this changes, measured rather than assumed:
//!
//! - **Panics render as diagnostics.** `miette::set_panic_hook` replaces the
//!   standard library's panic output. This is the substantive change.
//! - **The theme matches the rest of the CLI**, because the handler is built
//!   with `starbase_styles`, which the CLI already depends on for its other
//!   output. Invisible under `NO_COLOR`.
//!
//! What it does **not** change: the cause chain. `with_cause_chain` is set
//! here for explicitness, but miette's `fancy` default already prints the
//! chain. A configuration error rendered identically with and without this
//! module, which was checked against a real failing `morphir.toml` rather than
//! reasoned about.
//!
//! It configures miette the way `starbase::diagnostics::setup_miette` does,
//! but does not call that function, for one reason: `setup_miette` unwraps
//! `miette::set_hook`. miette keeps its hook in a global cell that is
//! initialized the first time any report is rendered, so "a hook already
//! exists" is an ordinary state rather than a bug. In the CLI binary this
//! module runs first and wins. In a test binary, or inside an embedder, some
//! other code has usually rendered a report already. Losing the theme there is
//! not worth aborting the process over, so the failure is ignored.

use std::sync::Once;

static INSTALLED: Once = Once::new();

/// Installs miette's report handler and panic hook, once per process.
///
/// Safe to call from any entry point, any number of times. A hook installed by
/// someone else is left alone.
pub fn install() {
    INSTALLED.call_once(configure);
}

fn configure() {
    miette::set_panic_hook();

    // Ignored deliberately: see the module docs. A hook is already present
    // whenever anything has rendered a report, which is normal outside the
    // CLI binary.
    let _ = miette::set_hook(Box::new(|_| {
        Box::new(
            miette::MietteHandlerOpts::new()
                .with_cause_chain()
                .graphical_theme(starbase::style::theme::create_graphical_theme())
                .build(),
        )
    }));
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Installation is global, so any number of callers may reasonably ask for
    /// it. The second ask must not take the process down.
    ///
    /// This also covers the harder case, by virtue of where it runs. In the
    /// full test binary other tests render miette reports first, which
    /// initializes miette's hook cell, so by the time this runs a hook already
    /// exists. That is exactly the state `setup_miette`'s unwrap treats as
    /// fatal, and the reason this module configures miette itself.
    #[test]
    fn installing_more_than_once_is_a_no_op() {
        install();
        install();
        install();
    }
}
