//! Selected item indicator component for the sidebar.

use dioxus::prelude::*;

/// Shows the currently selected workspace or project in the sidebar
/// with a visual indicator distinguishing it from filter items.
#[component]
pub fn SelectedItem(icon: String, name: String, on_click: EventHandler<()>) -> Element {
    rsx! {
        div { class: "selected-item", onclick: move |_| on_click.call(()),

            span { class: "selected-item-indicator", "▸" }
            span { class: "selected-item-icon", "{icon}" }
            span { class: "selected-item-name", "{name}" }
        }
    }
}
