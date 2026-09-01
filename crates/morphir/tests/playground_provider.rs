//! The playground provider as a caller outside the crate sees it.
//!
//! The unit tests in `provider/playground.rs` inject a registry and an
//! invoker, which is how they reach an extension without one being installed
//! — including the no-write guard, which has to watch a real invocation to
//! mean anything. This file covers what those cannot: that `new(home)` alone
//! produces a usable provider reading a real Morphir home.

use morphir::commands::ui::protocol::PlaygroundGenerateParams;
use morphir::commands::ui::provider::PlaygroundCapability;
use morphir::commands::ui::provider::playground::NativePlaygroundProvider;
use morphir_common::home::MorphirHome;

fn empty_home() -> (tempfile::TempDir, MorphirHome) {
    let root = tempfile::tempdir().expect("a temporary Morphir home");
    let home = MorphirHome::resolve_from(Some(root.path().as_os_str()), None)
        .expect("an explicit Morphir home resolves");
    (root, home)
}

#[tokio::test]
async fn a_home_with_no_installed_backend_cannot_generate_an_uninstalled_target() {
    let (_root, home) = empty_home();
    let provider = NativePlaygroundProvider::new(home);

    let error = provider
        .generate(PlaygroundGenerateParams {
            ir: serde_json::json!({"formatVersion": 4}),
            ir_version: "4.0.0".into(),
            target: "avro".into(),
            options: serde_json::json!({}),
        })
        .await
        .expect_err("no extension installed here generates Avro");

    assert!(
        error.to_string().contains("avro"),
        "unexpected error: {error}"
    );
}

/// A home with nothing installed still offers the built-in providers: the
/// registry the playground projects is the same one `morphir compile` uses,
/// and it carries the built-ins.
#[tokio::test]
async fn the_catalog_reads_the_home_it_was_built_with() {
    let (_root, home) = empty_home();
    let provider = NativePlaygroundProvider::new(home);

    let catalog = provider
        .catalog()
        .await
        .expect("an empty home has a catalog");

    assert!(
        catalog.target("avro").is_none(),
        "an empty home offers no installed targets"
    );
    assert!(
        catalog.frontend("gleam").is_some(),
        "the built-in Gleam frontend is always offered: {catalog:?}"
    );
}
