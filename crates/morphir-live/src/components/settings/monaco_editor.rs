//! Monaco Editor component with JavaScript interop for TOML editing.

use dioxus::prelude::*;

/// Monaco Editor component that provides syntax highlighting for TOML
#[component]
pub fn MonacoEditor(
    container_id: String,
    content: String,
    on_change: EventHandler<String>,
) -> Element {
    let mut initialized = use_signal(|| false);
    let mut pending_content = use_signal(|| content.clone());

    // Clone container_id for use in multiple closures and rsx
    let container_id_init = container_id.clone();
    let container_id_poll = container_id.clone();
    let container_id_render = container_id.clone();

    // Effect to initialize Monaco when the component mounts
    use_effect(move || {
        let container_id = container_id_init.clone();
        let content = content.clone();

        spawn(async move {
            // Wait for Monaco to be ready
            let check_script = r#"
                (function() {
                    return typeof monaco !== 'undefined' && typeof window.initMonacoEditor === 'function';
                })()
            "#;

            // Poll until Monaco is ready (max 5 seconds)
            for _ in 0..50 {
                let result = document::eval(check_script);
                if let Ok(value) = result.await {
                    if let Some(is_ready) = value.as_bool() {
                        if is_ready {
                            break;
                        }
                    }
                }
                gloo_timers::future::TimeoutFuture::new(100).await;
            }

            // Initialize the editor
            let init_script = format!(
                r#"
                (function() {{
                    const container = document.getElementById('{container_id}');
                    if (!container) {{
                        console.error('Monaco container not found:', '{container_id}');
                        return false;
                    }}

                    // Initialize the editor with content
                    const content = {content_json};
                    const editor = window.initMonacoEditor('{container_id}', content, 'toml');

                    if (editor) {{
                        // Store the callback ID for change events
                        editor._dioxusChangeCallback = true;
                        return true;
                    }}
                    return false;
                }})()
                "#,
                container_id = container_id,
                content_json = serde_json::to_string(&content).unwrap_or_else(|_| "\"\"".to_string()),
            );

            let result = document::eval(&init_script);
            if let Ok(value) = result.await {
                if let Some(success) = value.as_bool() {
                    if success {
                        initialized.set(true);
                    }
                }
            }
        });
    });

    // Set up change polling when initialized
    use_effect(move || {
        if !*initialized.read() {
            return;
        }

        let container_id = container_id_poll.clone();
        let on_change = on_change.clone();
        let mut last_content = pending_content.read().clone();

        spawn(async move {
            loop {
                gloo_timers::future::TimeoutFuture::new(500).await;

                let get_content_script = format!(
                    r#"window.getMonacoContent('{}')"#,
                    container_id
                );

                let result = document::eval(&get_content_script);
                if let Ok(value) = result.await {
                    if let Some(new_content) = value.as_str() {
                        if new_content != last_content {
                            last_content = new_content.to_string();
                            pending_content.set(new_content.to_string());
                            on_change.call(new_content.to_string());
                        }
                    }
                }
            }
        });
    });

    rsx! {
        div {
            id: "{container_id_render}",
            class: "monaco-editor-container",
            // The Monaco editor will be injected here by JavaScript
        }
    }
}
