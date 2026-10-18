//! Explicit qualification host, not registered by ordinary `morphir ui`.
#[path = "support/artifact_fixture.rs"]
mod artifact_fixture;

use morphir::commands::ui::{provider::SessionCapabilities, server::BoundUiHost};
use std::sync::Arc;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let (provider, _) = artifact_fixture::provider();
    let host = BoundUiHost::bind(
        "artifact-qualification-session".into(),
        SessionCapabilities {
            playground: Some(Arc::new(provider)),
            ..Default::default()
        },
    )
    .await?;
    println!("{}", host.launch_url());
    host.serve().await?;
    Ok(())
}
