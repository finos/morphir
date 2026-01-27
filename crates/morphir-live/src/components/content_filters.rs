//! Content filter components for the search page.

use dioxus::prelude::*;

use crate::data::sample_workspaces;
use crate::models::{ActiveFilter, EntityType, FilterType, StatusFilter};

/// A filter chip that can be toggled or removed.
#[component]
pub fn FilterChip(
    label: String,
    active: bool,
    removable: bool,
    on_click: EventHandler<()>,
    #[props(default)] on_remove: Option<EventHandler<()>>,
) -> Element {
    let class = if active {
        "filter-chip active"
    } else {
        "filter-chip"
    };

    rsx! {
        button {
            class: "{class}",
            onclick: move |_| on_click.call(()),
            "{label}"
            if removable && on_remove.is_some() {
                span {
                    class: "filter-chip-remove",
                    onclick: move |e| {
                        e.stop_propagation();
                        if let Some(ref handler) = on_remove {
                            handler.call(());
                        }
                    },
                    "×"
                }
            }
        }
    }
}

/// Type filter dropdown (Workspace/Project/Model).
#[component]
pub fn TypeFilterDropdown(
    selected: Option<EntityType>,
    on_change: EventHandler<Option<EntityType>>,
) -> Element {
    let mut show_dropdown = use_signal(|| false);

    let label = selected
        .map(|t| t.label())
        .unwrap_or("Type");

    let class = if selected.is_some() {
        "filter-chip active"
    } else {
        "filter-chip"
    };

    rsx! {
        div { class: "type-filter-dropdown",
            button {
                class: "{class}",
                onclick: move |_| show_dropdown.toggle(),
                "{label} ▾"
            }
            if *show_dropdown.read() {
                div { class: "dropdown-menu",
                    div {
                        class: if selected.is_none() { "dropdown-item selected" } else { "dropdown-item" },
                        onclick: move |_| {
                            on_change.call(None);
                            show_dropdown.set(false);
                        },
                        "All Types"
                    }
                    div {
                        class: if selected == Some(EntityType::Workspace) { "dropdown-item selected" } else { "dropdown-item" },
                        onclick: move |_| {
                            on_change.call(Some(EntityType::Workspace));
                            show_dropdown.set(false);
                        },
                        "📁 Workspace"
                    }
                    div {
                        class: if selected == Some(EntityType::Project) { "dropdown-item selected" } else { "dropdown-item" },
                        onclick: move |_| {
                            on_change.call(Some(EntityType::Project));
                            show_dropdown.set(false);
                        },
                        "📂 Project"
                    }
                    div {
                        class: if selected == Some(EntityType::Model) { "dropdown-item selected" } else { "dropdown-item" },
                        onclick: move |_| {
                            on_change.call(Some(EntityType::Model));
                            show_dropdown.set(false);
                        },
                        "📐 Model"
                    }
                }
            }
        }
    }
}

/// Filter selection panel shown when adding new filters.
#[component]
pub fn FilterSelectionPanel(on_select: EventHandler<ActiveFilter>) -> Element {
    let mut show_location = use_signal(|| false);
    let mut show_status = use_signal(|| false);

    let workspaces = sample_workspaces();

    rsx! {
        div { class: "filter-selection-panel",
            h3 { class: "filter-selection-title", "Add a content filter" }
            p { class: "filter-selection-subtitle", "Select a filter below to add it to your Quick Access" }

            div { class: "filter-options",
                // Location dropdown
                div { class: "filter-option-dropdown",
                    button {
                        class: "filter-option-btn",
                        onclick: move |_| {
                            show_location.toggle();
                            show_status.set(false);
                        },
                        "📁 Location ▾"
                    }
                    if *show_location.read() {
                        div { class: "dropdown-menu",
                            for ws in workspaces.iter() {
                                div {
                                    class: "dropdown-item",
                                    onclick: {
                                        let ws_id = ws.id.clone();
                                        let ws_name = ws.name.clone();
                                        move |_| {
                                            on_select.call(ActiveFilter {
                                                filter_type: FilterType::Location(ws_id.clone()),
                                                label: ws_name.clone(),
                                            });
                                            show_location.set(false);
                                        }
                                    },
                                    "{ws.name}"
                                }
                            }
                        }
                    }
                }

                // Status dropdown
                div { class: "filter-option-dropdown",
                    button {
                        class: "filter-option-btn",
                        onclick: move |_| {
                            show_status.toggle();
                            show_location.set(false);
                        },
                        "⚡ Status ▾"
                    }
                    if *show_status.read() {
                        div { class: "dropdown-menu",
                            div {
                                class: "dropdown-item",
                                onclick: move |_| {
                                    on_select.call(ActiveFilter {
                                        filter_type: FilterType::Status(StatusFilter::Active),
                                        label: "Active".to_string(),
                                    });
                                    show_status.set(false);
                                },
                                "Active"
                            }
                            div {
                                class: "dropdown-item",
                                onclick: move |_| {
                                    on_select.call(ActiveFilter {
                                        filter_type: FilterType::Status(StatusFilter::Archived),
                                        label: "Archived".to_string(),
                                    });
                                    show_status.set(false);
                                },
                                "Archived"
                            }
                            div {
                                class: "dropdown-item",
                                onclick: move |_| {
                                    on_select.call(ActiveFilter {
                                        filter_type: FilterType::Status(StatusFilter::Favorite),
                                        label: "Favorite".to_string(),
                                    });
                                    show_status.set(false);
                                },
                                "Favorite"
                            }
                        }
                    }
                }

                // Tags (placeholder)
                button {
                    class: "filter-option-btn",
                    disabled: true,
                    "🏷️ Tags ▾"
                }
            }
        }
    }
}

/// Container for all content filters.
#[component]
pub fn ContentFilters(
    show_all: bool,
    type_filter: Option<EntityType>,
    active_filters: Vec<ActiveFilter>,
    show_filter_panel: bool,
    on_toggle_all: EventHandler<()>,
    on_type_change: EventHandler<Option<EntityType>>,
    on_add_filter: EventHandler<ActiveFilter>,
    on_remove_filter: EventHandler<usize>,
    on_toggle_panel: EventHandler<()>,
) -> Element {
    rsx! {
        div { class: "content-filters-container",
            div { class: "content-filters",
                // "All" chip
                FilterChip {
                    label: "All".to_string(),
                    active: show_all,
                    removable: false,
                    on_click: move |_| on_toggle_all.call(()),
                }

                // Type dropdown
                TypeFilterDropdown {
                    selected: type_filter,
                    on_change: move |t| on_type_change.call(t),
                }

                // Active filters
                for (idx, filter) in active_filters.iter().enumerate() {
                    FilterChip {
                        key: "{idx}",
                        label: filter.label.clone(),
                        active: true,
                        removable: true,
                        on_click: move |_| {},
                        on_remove: Some(EventHandler::new(move |_| on_remove_filter.call(idx))),
                    }
                }

                // "+ New" button
                button {
                    class: if show_filter_panel { "add-filter-btn active" } else { "add-filter-btn" },
                    onclick: move |_| on_toggle_panel.call(()),
                    "+ New"
                    if show_filter_panel {
                        " ×"
                    }
                }
            }

            // Filter selection panel
            if show_filter_panel {
                FilterSelectionPanel {
                    on_select: move |filter| on_add_filter.call(filter),
                }
            }
        }
    }
}
