//! 404 Not Found page.

use dioxus::prelude::*;

use crate::Route;

#[component]
pub fn NotFound(route: Vec<String>) -> Element {
    let nav = navigator();

    rsx! {
        div { class: "not-found-page",
            div { class: "not-found-content",
                h1 { "404" }
                h2 { "Page Not Found" }
                p { "The page you're looking for doesn't exist." }
                p { class: "not-found-path", "Path: /{route.join(\"/\")}" }
                button {
                    class: "btn btn-primary",
                    onclick: move |_| {
                        nav.push(Route::Home {});
                    },
                    "Go Home"
                }
            }
        }
    }
}
