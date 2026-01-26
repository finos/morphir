//! Morphir Live - Interactive visualization and management tool for Morphir IR.

use dioxus::prelude::*;

mod components;
mod data;
pub mod models;
pub mod monaco;
mod routes;

pub use routes::Route;

const FAVICON: Asset = asset!("/assets/favicon.ico");
const MAIN_CSS: Asset = asset!("/assets/main.css");
const TAILWIND_CSS: Asset = asset!("/assets/tailwind.css");

fn main() {
    dioxus::launch(App);
}

#[component]
fn App() -> Element {
    // Initialize Monaco Editor asynchronously on app startup
    use_effect(|| {
        monaco::init_monaco_on_startup();
    });

    rsx! {
        document::Link { rel: "icon", href: FAVICON }
        document::Link { rel: "stylesheet", href: MAIN_CSS }
        document::Link { rel: "stylesheet", href: TAILWIND_CSS }
        Router::<Route> {}
    }
}
