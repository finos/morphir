//! Sidebar section component.

use dioxus::prelude::*;

#[component]
pub fn SidebarSection(title: String, children: Element) -> Element {
    rsx! {
        div { class: "sidebar-section",
            div { class: "section-header", "{title}" }
            {children}
        }
    }
}
