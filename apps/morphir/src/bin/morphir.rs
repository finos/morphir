use starbase::{App, MainResult};
use starbase::tracing::TracingOptions;
use starbase_utils::glob;
use tracing::info;
use morphir::session::Session;

#[tokio::main]
async fn main() -> MainResult {
    glob::add_global_negations(["**/target/**", "**/elm-stuff/**"]);
    let app = App::default();
    app.setup_diagnostics();
    let _guard = app.setup_tracing(TracingOptions {
        // log_file: Some(PathBuf::from("temp/test.log")),
        // dump_trace: false,
        ..Default::default()
    });

    let mut session = Session::default();

    app.run(&mut session, |session| async move {
        // Run CLI
        info!("Session is running: {:?}", session);
        Ok(())
    }).await?;

    Ok(())
}
