//! Toolbar component for content area headers.

use dioxus::prelude::*;

#[component]
pub fn Toolbar(
    title: String,
    subtitle: Option<String>,
    on_config: EventHandler<()>,
    #[props(default)] show_back: bool,
    on_back: Option<EventHandler<()>>,
) -> Element {
    rsx! {
        div { class: "toolbar",
            div { class: "toolbar-left",
                // Back button
                if show_back {
                    if let Some(on_back) = on_back {
                        button {
                            class: "toolbar-btn toolbar-back-btn",
                            title: "Go back",
                            onclick: move |_| on_back.call(()),
                            "←"
                        }
                    }
                }
                div { class: "toolbar-title",
                    "{title}"
                    if let Some(sub) = subtitle {
                        span { class: "toolbar-subtitle", "/ {sub}" }
                    }
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
