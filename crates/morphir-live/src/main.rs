//! Morphir Live - Interactive visualization and management tool for Morphir IR.

use morphir_live::{App, AppConfig};

fn main() {
    let config = get_app_config();

    dioxus::LaunchBuilder::new()
        .with_context(config)
        .launch(App);
}

#[cfg(not(target_arch = "wasm32"))]
fn get_app_config() -> AppConfig {
    use clap::Parser;
    use morphir_live::cli::{Cli, Commands};

    let args = Cli::parse();

    match args.command {
        Some(Commands::Version) => {
            println!("morphir-live {}", env!("CARGO_PKG_VERSION"));
            std::process::exit(0);
        }
        Some(Commands::Serve) => {
            println!("morphir-live serve");
            println!();
            println!("Coming soon: Start a headless Morphir Live server that exposes");
            println!("the IR visualization and management API without launching the UI.");
            std::process::exit(0);
        }
        None => AppConfig {
            config_path: args.path,
        },
    }
}

#[cfg(target_arch = "wasm32")]
fn get_app_config() -> AppConfig {
    AppConfig::default()
}
