//! Toolbar component for content area headers.

use dioxus::prelude::*;

#[component]
pub fn Toolbar(title: String, subtitle: Option<String>, on_config: EventHandler<()>) -> Element {
    rsx! {
        div { class: "toolbar",
            div { class: "toolbar-title",
                "{title}"
                if let Some(sub) = subtitle {
                    span { class: "toolbar-subtitle", "/ {sub}" }
                }
            }
            div { class: "toolbar-actions",
                button {
                    class: "toolbar-btn",
                    title: "Settings",
                    onclick: move |_| on_config.call(()),
                    "⚙️"
                }
            }
        }
    }
}
