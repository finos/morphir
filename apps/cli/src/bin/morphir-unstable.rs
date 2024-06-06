use morphir::app::CliApp;
#[tokio::main]
async fn main() -> Result<(), anyhow::Error> {
    let app: CliApp = Default::default();
    let args = std::env::args().collect();
    app.run(args).await?;
    Ok(())
}
