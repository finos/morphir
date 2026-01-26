//! Morphir Live library - shared types and components.

mod app;
pub mod app_config;
mod components;
mod data;
pub mod models;
pub mod monaco;
pub mod routes;

#[cfg(not(target_arch = "wasm32"))]
pub mod cli;

pub use app::App;
pub use app_config::AppConfig;
pub use routes::Route;
