//! Navigation item component for the sidebar.

use dioxus::prelude::*;

#[component]
pub fn NavItem(icon: String, label: String, active: bool, on_click: EventHandler<()>) -> Element {
    let class_name = if active {
        "nav-item active"
    } else {
        "nav-item"
    };

    rsx! {
        div { class: "{class_name}", onclick: move |_| on_click.call(()),
            span { class: "nav-icon", "{icon}" }
            span { class: "nav-label", "{label}" }
        }
    }
}
