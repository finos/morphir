//! Morphir Live - Interactive visualization and management tool for Morphir IR.

use morphir_live::{App, AppConfig};

fn main() {
    let config = get_app_config();

    #[cfg(feature = "desktop")]
    {
        use dioxus::desktop::{Config, WindowBuilder};

        // Load the window icon from the assets
        let icon = load_icon();

        let window_config = Config::new().with_window(
            WindowBuilder::new()
                .with_title("Morphir Live")
                .with_window_icon(icon),
        );

        dioxus::LaunchBuilder::new()
            .with_cfg(window_config)
            .with_context(config)
            .launch(App);
    }

    #[cfg(not(feature = "desktop"))]
    {
        dioxus::LaunchBuilder::new()
            .with_context(config)
            .launch(App);
    }
}

/// Load the Morphir icon for the window.
#[cfg(feature = "desktop")]
fn load_icon() -> Option<dioxus::desktop::tao::window::Icon> {
    use std::path::PathBuf;

    // Icon filenames to try (in order of preference)
    let icon_files = ["favicon.ico", "icon.png"];

    // Base paths to search
    let base_paths: Vec<PathBuf> = vec![
        // Current directory (when running from crate root)
        PathBuf::from("assets"),
        // Manifest directory at compile time
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("assets"),
        // Relative to executable
        std::env::current_exe()
            .ok()
            .and_then(|p| p.parent().map(|p| p.join("assets")))
            .unwrap_or_default(),
    ];

    for base in &base_paths {
        for filename in &icon_files {
            let icon_path = base.join(filename);
            if icon_path.exists() {
                if let Ok(image) = image::open(&icon_path) {
                    let rgba = image.to_rgba8();
                    let (width, height) = rgba.dimensions();
                    if let Ok(icon) = dioxus::desktop::tao::window::Icon::from_rgba(
                        rgba.into_raw(),
                        width,
                        height,
                    ) {
                        return Some(icon);
                    }
                }
            }
        }
    }
    None
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
