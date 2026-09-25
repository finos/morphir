//! Cross-workspace link spike (Task B0).
//!
//! Answers the kit/itest Gherkin spec's open question: does cucumber-rs's `inventory` step
//! collection work across the finos/morphir and morphir-rust workspace boundary? It defines one
//! step in this crate's own test binary (`Given the kit crate's steps are linked`) and calls one
//! step from `morphir-bdd`'s own base library (`Given a temporary directory`, from
//! `morphir_bdd::steps::files`). Both must run through [`morphir_bdd::Suite`], which is the real
//! cross-workspace library case: `morphir-bdd` is reached from `morphir-mck` only as a path
//! dependency into the `ecosystem/morphir-rust` submodule.

use cucumber::{given, then};
use morphir_bdd::Suite;
use morphir_bdd::world::MorphirWorld;

/// A test-only component: proves that [`kit_steps_are_linked`], defined in this crate's own test
/// binary, ran and inserted into the scenario's context.
#[derive(Debug, Clone, PartialEq)]
struct KitLinked;

/// `Given the kit crate's steps are linked` inserts a [`KitLinked`] component into the running
/// scenario's context.
#[given("the kit crate's steps are linked")]
fn kit_steps_are_linked(world: &mut MorphirWorld) {
    world.context.insert(KitLinked);
}

/// `Then the kit flag is set` asserts that [`kit_steps_are_linked`] ran earlier in the same
/// scenario.
#[then("the kit flag is set")]
fn kit_flag_is_set(world: &mut MorphirWorld) {
    assert_eq!(world.context.get::<KitLinked>(), Some(&KitLinked));
}

#[tokio::main]
async fn main() {
    let out_dir = tempfile::tempdir().expect("create a temporary output directory");
    let result = Suite::new("mck-link")
        .features(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/tests/features/link.feature"
        ))
        .clear_tags()
        .out_dir(out_dir.path())
        .run()
        .await;
    assert!(result.succeeded(), "{result:?}");
    assert!(result.passed >= 2, "{result:?}");
}
