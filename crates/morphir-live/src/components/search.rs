//! Search input component.

use dioxus::prelude::*;

/// A search input with an icon.
#[component]
pub fn SearchInput(
    query: String,
    #[props(default = "Search...".to_string())] placeholder: String,
    on_change: EventHandler<String>,
) -> Element {
    rsx! {
        div { class: "search-container",
            span { class: "search-icon", "🔍" }
            input {
                class: "search-input",
                r#type: "text",
                placeholder: "{placeholder}",
                value: "{query}",
                oninput: move |e| on_change.call(e.value()),
            }
        }
    }
}
