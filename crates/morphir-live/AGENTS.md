You are an expert [0.7 Dioxus](https://dioxuslabs.com/learn/0.7) assistant. Dioxus 0.7 changes every api in dioxus. Only use this up to date documentation. `cx`, `Scope`, and `use_state` are gone

Provide concise code examples with detailed descriptions

## ⚠️ CRITICAL: No AI Co-Authors in Commits

**DO NOT add Claude or any AI assistant as a commit co-author under any circumstances.**

This project uses EasyCLA (Easy Contributor License Agreement) for FINOS compliance. Adding AI co-authors:
- ❌ Breaks the CLA verification process
- ❌ Blocks pull requests from being merged
- ❌ Violates FINOS contribution requirements

**NEVER include lines like:**
```
Co-Authored-By: Claude <noreply@anthropic.com>
🤖 Generated with Claude Code
```

Only the human developer should be listed as the author/co-author.

# Dioxus Dependency

You can add Dioxus to your `Cargo.toml` like this:

```toml
[dependencies]
dioxus = { version = "0.7.1" }

[features]
default = ["web", "webview", "server"]
web = ["dioxus/web"]
webview = ["dioxus/desktop"]
server = ["dioxus/server"]
```

# Launching your application

You need to create a main function that sets up the Dioxus runtime and mounts your root component.

```rust
use dioxus::prelude::*;

fn main() {
	dioxus::launch(App);
}

#[component]
fn App() -> Element {
	rsx! { "Hello, Dioxus!" }
}
```

Then serve with `dx serve`:

```sh
curl -sSL http://dioxus.dev/install.sh | sh
dx serve
```

# UI with RSX

```rust
rsx! {
	div {
		class: "container", // Attribute
		color: "red", // Inline styles
		width: if condition { "100%" }, // Conditional attributes
		"Hello, Dioxus!"
	}
	// Prefer loops over iterators
	for i in 0..5 {
		div { "{i}" } // use elements or components directly in loops
	}
	if condition {
		div { "Condition is true!" } // use elements or components directly in conditionals
	}

	{children} // Expressions are wrapped in brace
	{(0..5).map(|i| rsx! { span { "Item {i}" } })} // Iterators must be wrapped in braces
}
```

# Assets

The asset macro can be used to link to local files to use in your project. All links start with `/` and are relative to the root of your project.

```rust
rsx! {
	img {
		src: asset!("/assets/image.png"),
		alt: "An image",
	}
}
```

## Styles

The `document::Stylesheet` component will inject the stylesheet into the `<head>` of the document

```rust
rsx! {
	document::Stylesheet {
		href: asset!("/assets/styles.css"),
	}
}
```

# Components

Components are the building blocks of apps

* Component are functions annotated with the `#[component]` macro.
* The function name must start with a capital letter or contain an underscore.
* A component re-renders only under two conditions:
	1.  Its props change (as determined by `PartialEq`).
	2.  An internal reactive state it depends on is updated.

```rust
#[component]
fn Input(mut value: Signal<String>) -> Element {
	rsx! {
		input {
            value,
			oninput: move |e| {
				*value.write() = e.value();
			},
			onkeydown: move |e| {
				if e.key() == Key::Enter {
					value.write().clear();
				}
			},
		}
	}
}
```

Each component accepts function arguments (props)

* Props must be owned values, not references. Use `String` and `Vec<T>` instead of `&str` or `&[T]`.
* Props must implement `PartialEq` and `Clone`.
* To make props reactive and copy, you can wrap the type in `ReadOnlySignal`. Any reactive state like memos and resources that read `ReadOnlySignal` props will automatically re-run when the prop changes.

# State

A signal is a wrapper around a value that automatically tracks where it's read and written. Changing a signal's value causes code that relies on the signal to rerun.

## Local State

The `use_signal` hook creates state that is local to a single component. You can call the signal like a function (e.g. `my_signal()`) to clone the value, or use `.read()` to get a reference. `.write()` gets a mutable reference to the value.

Use `use_memo` to create a memoized value that recalculates when its dependencies change. Memos are useful for expensive calculations that you don't want to repeat unnecessarily.

```rust
#[component]
fn Counter() -> Element {
	let mut count = use_signal(|| 0);
	let mut doubled = use_memo(move || count() * 2); // doubled will re-run when count changes because it reads the signal

	rsx! {
		h1 { "Count: {count}" } // Counter will re-render when count changes because it reads the signal
		h2 { "Doubled: {doubled}" }
		button {
			onclick: move |_| *count.write() += 1, // Writing to the signal rerenders Counter
			"Increment"
		}
		button {
			onclick: move |_| count.with_mut(|count| *count += 1), // use with_mut to mutate the signal
			"Increment with with_mut"
		}
	}
}
```

## Context API

The Context API allows you to share state down the component tree. A parent provides the state using `use_context_provider`, and any child can access it with `use_context`

```rust
#[component]
fn App() -> Element {
	let mut theme = use_signal(|| "light".to_string());
	use_context_provider(|| theme); // Provide a type to children
	rsx! { Child {} }
}

#[component]
fn Child() -> Element {
	let theme = use_context::<Signal<String>>(); // Consume the same type
	rsx! {
		div {
			"Current theme: {theme}"
		}
	}
}
```

# Async

For state that depends on an asynchronous operation (like a network request), Dioxus provides a hook called `use_resource`. This hook manages the lifecycle of the async task and provides the result to your component.

* The `use_resource` hook takes an `async` closure. It re-runs this closure whenever any signals it depends on (reads) are updated
* The `Resource` object returned can be in several states when read:
1. `None` if the resource is still loading
2. `Some(value)` if the resource has successfully loaded

```rust
let mut dog = use_resource(move || async move {
	// api request
});

match dog() {
	Some(dog_info) => rsx! { Dog { dog_info } },
	None => rsx! { "Loading..." },
}
```

# Routing

All possible routes are defined in a single Rust `enum` that derives `Routable`. Each variant represents a route and is annotated with `#[route("/path")]`. Dynamic Segments can capture parts of the URL path as parameters by using `:name` in the route string. These become fields in the enum variant.

The `Router<Route> {}` component is the entry point that manages rendering the correct component for the current URL.

You can use the `#[layout(NavBar)]` to create a layout shared between pages and place an `Outlet<Route> {}` inside your layout component. The child routes will be rendered in the outlet.

```rust
#[derive(Routable, Clone, PartialEq)]
enum Route {
	#[layout(NavBar)] // This will use NavBar as the layout for all routes
		#[route("/")]
		Home {},
		#[route("/blog/:id")] // Dynamic segment
		BlogPost { id: i32 },
}

#[component]
fn NavBar() -> Element {
	rsx! {
		a { href: "/", "Home" }
		Outlet<Route> {} // Renders Home or BlogPost
	}
}

#[component]
fn App() -> Element {
	rsx! { Router::<Route> {} }
}
```

```toml
dioxus = { version = "0.7.1", features = ["router"] }
```

# Fullstack

Fullstack enables server rendering and ipc calls. It uses Cargo features (`server` and a client feature like `web`) to split the code into a server and client binaries.

```toml
dioxus = { version = "0.7.1", features = ["fullstack"] }
```

## Server Functions

Use the `#[post]` / `#[get]` macros to define an `async` function that will only run on the server. On the server, this macro generates an API endpoint. On the client, it generates a function that makes an HTTP request to that endpoint.

```rust
#[post("/api/double/:path/&query")]
async fn double_server(number: i32, path: String, query: i32) -> Result<i32, ServerFnError> {
	tokio::time::sleep(std::time::Duration::from_secs(1)).await;
	Ok(number * 2)
}
```

## Hydration

Hydration is the process of making a server-rendered HTML page interactive on the client. The server sends the initial HTML, and then the client-side runs, attaches event listeners, and takes control of future rendering.

### Errors
The initial UI rendered by the component on the client must be identical to the UI rendered on the server.

* Use the `use_server_future` hook instead of `use_resource`. It runs the future on the server, serializes the result, and sends it to the client, ensuring the client has the data immediately for its first render.
* Any code that relies on browser-specific APIs (like accessing `localStorage`) must be run *after* hydration. Place this code inside a `use_effect` hook.

---

# Morphir Live Project Context

Morphir Live is an interactive visualization and management tool for Morphir IR. It provides:
- A Mastodon-style hierarchical navigation UI (Workspaces → Projects → Models)
- VS Code-style settings with both UI form and TOML editor tabs
- Monaco Editor integration for TOML syntax highlighting (web only)
- Cross-platform support (web, desktop, mobile)

## Project Structure

```
crates/morphir-live/
├── src/
│   ├── main.rs              # App entry point, Monaco initialization
│   ├── models.rs            # ViewState, MorphirConfig, data models
│   ├── monaco.rs            # Global Monaco state management (web only)
│   ├── components/
│   │   ├── layout.rs        # Main layout with sidebar and content area
│   │   ├── detail_views/    # Workspace, Project, Model detail views
│   │   └── settings/        # VS Code-style settings components
│   │       ├── monaco_editor.rs    # Monaco/textarea component
│   │       ├── settings_view.rs    # Main settings container
│   │       ├── settings_ui_tab.rs  # Form-based config
│   │       └── settings_toml_tab.rs # TOML editor tab
│   └── data/                # Mock data for development
├── assets/
│   ├── main.css             # Custom styles
│   └── tailwind.css         # Tailwind utilities
├── index.html               # Custom HTML with Monaco loader
├── Dioxus.toml              # Dioxus configuration
└── Cargo.toml               # Dependencies with target-specific deps
```

---

# Cross-Platform Components

## Switching Entire Components by Platform

When a component needs completely different implementations for web vs desktop (e.g., Monaco Editor on web, textarea on desktop), use this pattern:

### Pattern 1: Conditional Return in Single Component

```rust
#[cfg(target_arch = "wasm32")]
use crate::web_specific_module;

#[component]
pub fn MyEditor(content: String, on_change: EventHandler<String>) -> Element {
    #[cfg(target_arch = "wasm32")]
    {
        web_editor(content, on_change)
    }

    #[cfg(not(target_arch = "wasm32"))]
    {
        desktop_editor(content, on_change)
    }
}

#[cfg(target_arch = "wasm32")]
fn web_editor(content: String, on_change: EventHandler<String>) -> Element {
    // Full Monaco integration with web_sys, gloo-timers, etc.
    let monaco_ready = web_specific_module::use_monaco_ready();

    rsx! {
        div { class: "monaco-container",
            if monaco_ready {
                // Monaco editor initialization
            } else {
                "Loading editor..."
            }
        }
    }
}

#[cfg(not(target_arch = "wasm32"))]
fn desktop_editor(content: String, on_change: EventHandler<String>) -> Element {
    // Simple fallback - no web dependencies
    rsx! {
        textarea {
            class: "editor",
            value: "{content}",
            oninput: move |e| on_change.call(e.value())
        }
    }
}
```

### Pattern 2: Separate Module Files

For larger components, use separate files:

```
src/components/editor/
├── mod.rs           # Re-exports the right implementation
├── web.rs           # Web-specific implementation
└── desktop.rs       # Desktop-specific implementation
```

**mod.rs:**
```rust
#[cfg(target_arch = "wasm32")]
mod web;
#[cfg(target_arch = "wasm32")]
pub use web::Editor;

#[cfg(not(target_arch = "wasm32"))]
mod desktop;
#[cfg(not(target_arch = "wasm32"))]
pub use desktop::Editor;
```

### Pattern 3: Feature-Based Component Selection

Use Cargo features for more complex scenarios:

**Cargo.toml:**
```toml
[features]
default = ["web"]
web = ["dioxus/web", "dep:gloo-timers", "dep:web-sys", "dep:js-sys"]
desktop = ["dioxus/desktop"]
```

**Component:**
```rust
#[component]
pub fn PlatformEditor(content: String) -> Element {
    #[cfg(feature = "web")]
    return web_impl(content);

    #[cfg(feature = "desktop")]
    return desktop_impl(content);
}
```

## Target-Specific Dependencies

Only include web-specific crates for wasm32:

```toml
[dependencies]
dioxus = { workspace = true }
serde = { workspace = true }

[target.'cfg(target_arch = "wasm32")'.dependencies]
gloo-timers = { version = "0.3", features = ["futures"] }
js-sys = "0.3"
web-sys = { version = "0.3", features = ["Window"] }
wasm-bindgen = "0.2"
```

---

# JavaScript Interop - Lessons Learned

## Problem: `document::eval` Return Values Don't Work Reliably

Dioxus's `document::eval` can execute JavaScript but **cannot reliably return values**:

```rust
// DON'T DO THIS - eval return values are unreliable
let result = document::eval("typeof monaco !== 'undefined'").await;
// result.as_bool() often returns None or errors with:
// "Failed to stringify result - undefined or not valid utf16"
```

### Solution: Use `js_sys` and `web_sys` for Reading Values

Instead of trying to get return values from eval, use direct JS interop:

```rust
#[cfg(target_arch = "wasm32")]
fn check_flag_from_js() -> bool {
    use js_sys::Reflect;
    use wasm_bindgen::JsValue;

    let window = match web_sys::window() {
        Some(w) => w,
        None => return false,
    };

    let key = JsValue::from_str("myGlobalFlag");
    match Reflect::get(&window, &key) {
        Ok(value) => value.as_bool().unwrap_or(false),
        Err(_) => false,
    }
}
```

### Pattern: JS Sets Flag, Rust Reads It

1. **JavaScript side** (in index.html):
```javascript
window.myReady = false;
// ... after async operation completes ...
window.myReady = true;
console.log('[JS] Ready flag set');
```

2. **Rust side**:
```rust
// Use document::eval only for EXECUTING code (no return value needed)
let _ = document::eval("console.log('Hello from Rust')");

// Use js_sys/web_sys for READING values
let is_ready = check_flag_from_js();
```

---

# Monaco Editor Integration

## Architecture

1. **index.html** - Loads Monaco from CDN and defines bridge functions
2. **monaco.rs** - Global state management, polls for Monaco readiness on startup
3. **monaco_editor.rs** - Component that creates editor instances

## Key Implementation Details

### Global Initialization on App Startup

```rust
// main.rs
#[component]
fn App() -> Element {
    use_effect(|| {
        monaco::init_monaco_on_startup();
    });
    // ...
}
```

### Monaco Bridge Functions (index.html)

```javascript
window.monacoReady = false;
window.initMonacoEditor = function(containerId, content, language) { /* ... */ };
window.getMonacoContent = function(containerId) { /* ... */ };
window.setMonacoContent = function(containerId, content) { /* ... */ };
```

### Polling Pattern for Async JS Libraries

```rust
#[cfg(target_arch = "wasm32")]
pub fn init_monaco_on_startup() {
    spawn(async move {
        for _ in 0..100 {  // Max 10 seconds
            if check_monaco_ready_js() {
                *MONACO_READY.write() = true;
                return;
            }
            gloo_timers::future::TimeoutFuture::new(100).await;
        }
    });
}
```

---

# Troubleshooting

## Build Errors

| Error | Cause | Solution |
|-------|-------|----------|
| `use of unresolved crate 'gloo_timers'` | Using wasm-only crate in desktop build | Wrap in `#[cfg(target_arch = "wasm32")]` |
| `extern blocks must be unsafe` | Rust 2024 edition change | Use `js_sys::Reflect` instead of raw `extern "C"` |
| `Unexpected token '<'` for .js file | Asset path issue, HTML served instead of JS | Inline JS in index.html or fix Dioxus.toml paths |

## Runtime Errors

| Error | Cause | Solution |
|-------|-------|----------|
| `Failed to stringify result` | Dioxus eval can't serialize JS return value | Don't rely on eval return values; use js_sys |
| `panic: not implemented on non-wasm32` | Called wasm-only code on desktop | Add cfg guards |
| Monaco timeout but JS shows "loaded" | Eval return value issue | Use js_sys to read `window.monacoReady` flag |

## Debugging Tips

1. **Add console logs on both sides** with prefixes like `[JS]` and `[Rust]` to trace execution
2. **Hard refresh** (Ctrl+Shift+R) when changing index.html - browsers cache aggressively
3. **Check both builds**: `cargo check --features web` AND `cargo check --features desktop`
4. **Use dx build** for final verification - it compiles to wasm32 which may reveal different errors than `cargo check`
5. **Use Playwright MCP** for automated web debugging and testing - it can interact with the running app, inspect DOM state, capture screenshots, and verify UI behavior programmatically

## Using Playwright MCP for Web Debugging

When troubleshooting web-specific issues, the Playwright MCP server provides powerful browser automation capabilities:

### Common Debugging Tasks

```
# Navigate to the app and take a screenshot
playwright_navigate to http://localhost:8080
playwright_screenshot

# Click on elements and inspect results
playwright_click on "Settings" button
playwright_screenshot

# Get console logs to see JS/Rust communication
playwright_console_logs

# Evaluate JavaScript in the browser context
playwright_evaluate "window.monacoReady"
playwright_evaluate "Object.keys(window.monacoEditors)"
```

### When to Use Playwright MCP

- **Verifying Monaco loaded correctly**: Check `window.monacoReady` and `window.monacoEditors`
- **Debugging UI state**: Take screenshots at different navigation states
- **Testing cross-browser behavior**: Run the same tests in different browsers
- **Inspecting DOM structure**: Verify elements are rendered correctly
- **Checking console output**: Capture `[JS]` and `[Rust]` log messages programmatically
