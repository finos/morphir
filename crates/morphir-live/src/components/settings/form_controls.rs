//! Reusable form control components for the settings UI.

use dioxus::prelude::*;

/// Text input field with label
#[component]
pub fn SettingsTextInput(
    label: String,
    value: String,
    placeholder: Option<String>,
    on_change: EventHandler<String>,
) -> Element {
    rsx! {
        div { class: "settings-field",
            label { class: "settings-label", "{label}" }
            input {
                class: "settings-input",
                r#type: "text",
                value: "{value}",
                placeholder: placeholder.unwrap_or_default(),
                oninput: move |e| on_change.call(e.value())
            }
        }
    }
}

/// Multi-line text area with label
#[component]
pub fn SettingsTextArea(
    label: String,
    value: String,
    rows: Option<usize>,
    placeholder: Option<String>,
    on_change: EventHandler<String>,
) -> Element {
    let rows = rows.unwrap_or(3);
    rsx! {
        div { class: "settings-field",
            label { class: "settings-label", "{label}" }
            textarea {
                class: "settings-textarea",
                rows: rows as i64,
                value: "{value}",
                placeholder: placeholder.unwrap_or_default(),
                oninput: move |e| on_change.call(e.value())
            }
        }
    }
}

/// Toggle switch with label and optional description
#[component]
pub fn SettingsToggle(
    label: String,
    description: Option<String>,
    checked: bool,
    on_change: EventHandler<bool>,
) -> Element {
    rsx! {
        div { class: "settings-field settings-toggle-field",
            div { class: "settings-toggle-content",
                label { class: "settings-label", "{label}" }
                if let Some(desc) = description {
                    span { class: "settings-description", "{desc}" }
                }
            }
            label { class: "settings-toggle",
                input {
                    r#type: "checkbox",
                    checked: checked,
                    onchange: move |e| on_change.call(e.checked())
                }
                span { class: "settings-toggle-slider" }
            }
        }
    }
}

/// Dropdown select with label
#[component]
pub fn SettingsSelect(
    label: String,
    value: String,
    options: Vec<(String, String)>,
    on_change: EventHandler<String>,
) -> Element {
    rsx! {
        div { class: "settings-field",
            label { class: "settings-label", "{label}" }
            select {
                class: "settings-select",
                value: "{value}",
                onchange: move |e| on_change.call(e.value()),
                for (val, display) in options {
                    option {
                        value: "{val}",
                        selected: val == value,
                        "{display}"
                    }
                }
            }
        }
    }
}

/// Number input with label
#[component]
pub fn SettingsNumberInput(
    label: String,
    value: u64,
    min: Option<u64>,
    max: Option<u64>,
    on_change: EventHandler<u64>,
) -> Element {
    rsx! {
        div { class: "settings-field",
            label { class: "settings-label", "{label}" }
            input {
                class: "settings-input",
                r#type: "number",
                value: "{value}",
                min: min.map(|v| v.to_string()).unwrap_or_default(),
                max: max.map(|v| v.to_string()).unwrap_or_default(),
                oninput: move |e| {
                    if let Ok(num) = e.value().parse::<u64>() {
                        on_change.call(num);
                    }
                }
            }
        }
    }
}

/// Tag input for lists (like exposed_modules, members, exclude)
#[component]
pub fn SettingsTagInput(
    label: String,
    tags: Vec<String>,
    placeholder: Option<String>,
    on_change: EventHandler<Vec<String>>,
) -> Element {
    let mut input_value = use_signal(String::new);
    let tags_clone = tags.clone();

    let add_tag = move |_| {
        let value = input_value.read().trim().to_string();
        if !value.is_empty() && !tags_clone.contains(&value) {
            let mut new_tags = tags_clone.clone();
            new_tags.push(value);
            on_change.call(new_tags);
            input_value.set(String::new());
        }
    };

    rsx! {
        div { class: "settings-field",
            label { class: "settings-label", "{label}" }
            div { class: "settings-tag-input-container",
                div { class: "settings-tags",
                    for (idx, tag) in tags.iter().enumerate() {
                        span {
                            key: "{idx}",
                            class: "settings-tag",
                            "{tag}"
                            button {
                                class: "settings-tag-remove",
                                onclick: {
                                    let tags = tags.clone();
                                    let on_change = on_change;
                                    move |_| {
                                        let mut new_tags = tags.clone();
                                        new_tags.remove(idx);
                                        on_change.call(new_tags);
                                    }
                                },
                                "×"
                            }
                        }
                    }
                }
                div { class: "settings-tag-input-row",
                    input {
                        class: "settings-input settings-tag-input",
                        r#type: "text",
                        value: "{input_value}",
                        placeholder: placeholder.unwrap_or_else(|| "Add item...".to_string()),
                        oninput: move |e| input_value.set(e.value()),
                        onkeypress: move |e| {
                            if e.key() == Key::Enter {
                                let value = input_value.read().trim().to_string();
                                if !value.is_empty() && !tags.contains(&value) {
                                    let mut new_tags = tags.clone();
                                    new_tags.push(value);
                                    on_change.call(new_tags);
                                    input_value.set(String::new());
                                }
                            }
                        }
                    }
                    button {
                        class: "btn-secondary settings-tag-add",
                        onclick: add_tag,
                        "Add"
                    }
                }
            }
        }
    }
}
