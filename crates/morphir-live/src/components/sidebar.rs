//! Sidebar section component.

use dioxus::prelude::*;

#[component]
pub fn SidebarSection(icon: Option<String>, title: String, children: Element) -> Element {
    rsx! {
        div { class: "sidebar-section",
            div { class: "section-header",
                if let Some(icon) = icon {
                    span { class: "section-header-icon", "{icon}" }
                }
                span { class: "section-header-title", "{title}" }
            }
            {children}
        }
    }
}
