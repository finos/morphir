//! Monaco Editor component for web platform with TOML syntax highlighting.

use crate::monaco;
use dioxus::prelude::*;
use wasm_bindgen::JsValue;

/// Check if the TOML editor has been initialized via JS global flag.
fn is_editor_initialized_js() -> bool {
    let window = web_sys::window().expect("no global window");
    let value = js_sys::Reflect::get(&window, &JsValue::from_str("__tomlEditorInitialized"))
        .unwrap_or(JsValue::FALSE);
    value.as_bool().unwrap_or(false)
}

/// Get Monaco editor content via JS global property (more reliable than eval return value).
fn get_editor_content_js(container_id: &str) -> Option<String> {
    let window = web_sys::window()?;
    // Read from window.__monacoContent_<container_id> which we set via JS
    let key = format!("__monacoContent_{}", container_id);
    let value = js_sys::Reflect::get(&window, &JsValue::from_str(&key)).ok()?;
    value.as_string()
}

/// Monaco-based TOML editor for web platform.
/// Provides full syntax highlighting, line numbers, and code editing features.
#[component]
pub fn TomlEditor(content: String, on_change: EventHandler<String>) -> Element {
    let mut editor_initialized = use_signal(|| false);
    let mut polling_started = use_signal(|| false);
    let mut pending_content = use_signal(|| content.clone());

    // Check global Monaco ready state - reading here subscribes component to changes
    let monaco_ready = monaco::use_monaco_ready();

    // Use a fixed container ID for the TOML editor
    let container_id = "toml-editor-container";

    // Effect to initialize the editor instance when Monaco is ready
    // Note: We also read monaco_ready INSIDE the effect to ensure the effect re-runs
    use_effect(move || {
        // Read Monaco ready state inside effect for proper reactivity
        // This ensures the effect re-runs when Monaco becomes ready
        let monaco_ready = monaco::use_monaco_ready();

        // Only proceed if Monaco is globally ready and we haven't initialized this editor yet
        if !monaco_ready || *editor_initialized.read() {
            return;
        }

        let content = content.clone();

        spawn(async move {
            // Small delay to ensure the DOM element is rendered
            gloo_timers::future::TimeoutFuture::new(50).await;

            // Initialize the editor and set a global flag for reliable detection
            // Also set up onChange handler to write content to a window property
            let init_script = format!(
                r#"
                (function() {{
                    const container = document.getElementById('toml-editor-container');
                    if (!container) {{
                        console.error('Monaco container not found: toml-editor-container');
                        window.__tomlEditorInitialized = false;
                        return;
                    }}

                    // Initialize the editor with content
                    const content = {content_json};
                    const editor = window.initMonacoEditor('toml-editor-container', content, 'toml');

                    // Set global flag for Rust to check via web_sys
                    window.__tomlEditorInitialized = !!editor;

                    // Set up content sync via window property (more reliable than eval return)
                    if (editor) {{
                        // Initialize content property
                        window.__monacoContent_toml_editor_container = content;

                        // Update on every change
                        editor.onDidChangeModelContent(() => {{
                            window.__monacoContent_toml_editor_container = editor.getValue();
                        }});
                    }}
                }})()
                "#,
                content_json =
                    serde_json::to_string(&content).unwrap_or_else(|_| "\"\"".to_string()),
            );

            // Execute the init script (don't rely on return value)
            let _ = document::eval(&init_script).await;

            // Check the global flag via web_sys instead of eval return value
            if is_editor_initialized_js() {
                editor_initialized.set(true);
            }
        });
    });

    // Set up change polling when editor is initialized
    use_effect(move || {
        // Only start polling once, and only after editor is initialized
        if !*editor_initialized.read() || *polling_started.read() {
            return;
        }

        // Mark polling as started to prevent duplicate loops
        polling_started.set(true);

        let on_change = on_change.clone();
        let mut last_content = pending_content.read().clone();

        spawn(async move {
            loop {
                gloo_timers::future::TimeoutFuture::new(500).await;

                // Read content via web_sys instead of unreliable eval return value
                if let Some(new_content) = get_editor_content_js("toml_editor_container") {
                    if new_content != last_content {
                        last_content = new_content.clone();
                        pending_content.set(new_content.clone());
                        on_change.call(new_content);
                    }
                }
            }
        });
    });

    rsx! {
        div {
            id: "{container_id}",
            class: "monaco-editor-container",
            // Show loading state while Monaco is initializing
            if !monaco_ready {
                div { class: "monaco-loading",
                    "Loading editor..."
                }
            }
        }
    }
}
