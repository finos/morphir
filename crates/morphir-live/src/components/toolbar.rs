//! Toolbar component for content area headers.

use dioxus::prelude::*;

use crate::Route;

/// A single breadcrumb item in the navigation path.
#[derive(Clone, PartialEq)]
pub struct BreadcrumbItem {
    /// Display label for this breadcrumb
    pub label: String,
    /// Optional route to navigate to when clicked (None for current/last item)
    pub route: Option<Route>,
}

impl BreadcrumbItem {
    /// Create a new breadcrumb item with a route (clickable)
    pub fn new(label: impl Into<String>, route: Route) -> Self {
        Self {
            label: label.into(),
            route: Some(route),
        }
    }

    /// Create a new breadcrumb item without a route (current page, not clickable)
    pub fn current(label: impl Into<String>) -> Self {
        Self {
            label: label.into(),
            route: None,
        }
    }
}

#[component]
pub fn Toolbar(
    title: String,
    #[props(default)] breadcrumbs: Vec<BreadcrumbItem>,
    on_config: EventHandler<()>,
    #[props(default)] show_back: bool,
    on_back: Option<EventHandler<()>>,
) -> Element {
    let nav = navigator();

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
                div { class: "toolbar-title", "{title}" }
                // Breadcrumb navigation
                if !breadcrumbs.is_empty() {
                    nav { class: "toolbar-breadcrumb",
                        for (idx , crumb) in breadcrumbs.iter().enumerate() {
                            if idx > 0 {
                                span { class: "breadcrumb-separator", "/" }
                            }
                            if let Some(route) = &crumb.route {
                                a {
                                    class: "breadcrumb-link",
                                    href: "#",
                                    onclick: {
                                        let route = route.clone();
                                        move |e: Event<MouseData>| {
                                            e.prevent_default();
                                            nav.push(route.clone());
                                        }
                                    },
                                    "{crumb.label}"
                                }
                            } else {
                                span { class: "breadcrumb-current", "{crumb.label}" }
                            }
                        }
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
