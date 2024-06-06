use morphir::app::MorphirApp;
#[tokio::main]
async fn main() -> Result<(), anyhow::Error> {
    let app = MorphirApp::new();
    let args = std::env::args().collect();
    app.run(args).await?;
    Ok(())
}
