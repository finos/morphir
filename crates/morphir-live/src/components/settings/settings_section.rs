//! Settings section component - collapsible section with icon and title.

use dioxus::prelude::*;

/// A collapsible section in the settings UI
#[component]
pub fn SettingsSection(
    title: String,
    icon: String,
    description: Option<String>,
    children: Element,
) -> Element {
    let mut expanded = use_signal(|| true);

    rsx! {
        div { class: "settings-section",
            div {
                class: "settings-section-header",
                onclick: move |_| {
                    let current = *expanded.read();
                    expanded.set(!current);
                },

                span { class: "settings-section-expand",
                    if *expanded.read() {
                        "▼"
                    } else {
                        "▶"
                    }
                }
                span { class: "settings-section-icon", "{icon}" }
                div { class: "settings-section-title-group",
                    h3 { class: "settings-section-title", "{title}" }
                    if let Some(desc) = description {
                        span { class: "settings-section-description", "{desc}" }
                    }
                }
            }
            if *expanded.read() {
                div { class: "settings-section-body", {children} }
            }
        }
    }
}
