//! UI-based settings tab with form controls organized in sections.

use dioxus::prelude::*;

use crate::models::{
    CacheConfig, CodegenConfig, IrConfig, LogFormat, LogLevel, LoggingConfig, MorphirConfig,
    OutputFormat, ProjectConfig, UiConfig, UiTheme, WorkspaceConfig,
};

use super::form_controls::{
    SettingsNumberInput, SettingsSelect, SettingsTagInput, SettingsTextInput, SettingsToggle,
};
use super::settings_section::SettingsSection;

#[component]
pub fn SettingsUITab(
    config: MorphirConfig,
    on_change: EventHandler<MorphirConfig>,
) -> Element {
    rsx! {
        div { class: "settings-ui-tab",
            // Project Section
            SettingsSection {
                title: "Project",
                icon: "📁",
                description: Some("Project identification and source configuration".to_string()),

                ProjectSettingsFields {
                    config: config.project.clone(),
                    on_change: {
                        let config = config.clone();
                        move |project: ProjectConfig| {
                            let mut new_config = config.clone();
                            new_config.project = project;
                            on_change.call(new_config);
                        }
                    }
                }
            }

            // Workspace Section
            SettingsSection {
                title: "Workspace",
                icon: "🏢",
                description: Some("Workspace directories and member configuration".to_string()),

                WorkspaceSettingsFields {
                    config: config.workspace.clone(),
                    on_change: {
                        let config = config.clone();
                        move |workspace: WorkspaceConfig| {
                            let mut new_config = config.clone();
                            new_config.workspace = workspace;
                            on_change.call(new_config);
                        }
                    }
                }
            }

            // Codegen Section
            SettingsSection {
                title: "Code Generation",
                icon: "⚙️",
                description: Some("Code generation targets and output format".to_string()),

                CodegenSettingsFields {
                    config: config.codegen.clone(),
                    on_change: {
                        let config = config.clone();
                        move |codegen: CodegenConfig| {
                            let mut new_config = config.clone();
                            new_config.codegen = codegen;
                            on_change.call(new_config);
                        }
                    }
                }
            }

            // IR Section
            SettingsSection {
                title: "IR",
                icon: "🔧",
                description: Some("Intermediate representation settings".to_string()),

                IrSettingsFields {
                    config: config.ir.clone(),
                    on_change: {
                        let config = config.clone();
                        move |ir: IrConfig| {
                            let mut new_config = config.clone();
                            new_config.ir = ir;
                            on_change.call(new_config);
                        }
                    }
                }
            }

            // Cache Section
            SettingsSection {
                title: "Cache",
                icon: "💾",
                description: Some("Caching behavior and limits".to_string()),

                CacheSettingsFields {
                    config: config.cache.clone(),
                    on_change: {
                        let config = config.clone();
                        move |cache: CacheConfig| {
                            let mut new_config = config.clone();
                            new_config.cache = cache;
                            on_change.call(new_config);
                        }
                    }
                }
            }

            // Logging Section
            SettingsSection {
                title: "Logging",
                icon: "📝",
                description: Some("Log output configuration".to_string()),

                LoggingSettingsFields {
                    config: config.logging.clone(),
                    on_change: {
                        let config = config.clone();
                        move |logging: LoggingConfig| {
                            let mut new_config = config.clone();
                            new_config.logging = logging;
                            on_change.call(new_config);
                        }
                    }
                }
            }

            // UI Section
            SettingsSection {
                title: "UI",
                icon: "🎨",
                description: Some("User interface preferences".to_string()),

                UiSettingsFields {
                    config: config.ui.clone(),
                    on_change: {
                        let config = config.clone();
                        move |ui: UiConfig| {
                            let mut new_config = config.clone();
                            new_config.ui = ui;
                            on_change.call(new_config);
                        }
                    }
                }
            }
        }
    }
}

// Individual section field components

#[component]
fn ProjectSettingsFields(
    config: ProjectConfig,
    on_change: EventHandler<ProjectConfig>,
) -> Element {
    rsx! {
        SettingsTextInput {
            label: "Name",
            value: config.name.clone(),
            placeholder: Some("my-project".to_string()),
            on_change: {
                let config = config.clone();
                move |name: String| {
                    let mut new_config = config.clone();
                    new_config.name = name;
                    on_change.call(new_config);
                }
            }
        }
        SettingsTextInput {
            label: "Version",
            value: config.version.clone(),
            placeholder: Some("1.0.0".to_string()),
            on_change: {
                let config = config.clone();
                move |version: String| {
                    let mut new_config = config.clone();
                    new_config.version = version;
                    on_change.call(new_config);
                }
            }
        }
        SettingsTextInput {
            label: "Source Directory",
            value: config.source_directory.clone(),
            placeholder: Some("src".to_string()),
            on_change: {
                let config = config.clone();
                move |source_directory: String| {
                    let mut new_config = config.clone();
                    new_config.source_directory = source_directory;
                    on_change.call(new_config);
                }
            }
        }
        SettingsTagInput {
            label: "Exposed Modules",
            tags: config.exposed_modules.clone(),
            placeholder: Some("Add module...".to_string()),
            on_change: {
                let config = config.clone();
                move |exposed_modules: Vec<String>| {
                    let mut new_config = config.clone();
                    new_config.exposed_modules = exposed_modules;
                    on_change.call(new_config);
                }
            }
        }
    }
}

#[component]
fn WorkspaceSettingsFields(
    config: WorkspaceConfig,
    on_change: EventHandler<WorkspaceConfig>,
) -> Element {
    rsx! {
        SettingsTextInput {
            label: "Root",
            value: config.root.clone(),
            placeholder: Some(".".to_string()),
            on_change: {
                let config = config.clone();
                move |root: String| {
                    let mut new_config = config.clone();
                    new_config.root = root;
                    on_change.call(new_config);
                }
            }
        }
        SettingsTextInput {
            label: "Output Directory",
            value: config.output_dir.clone(),
            placeholder: Some(".morphir".to_string()),
            on_change: {
                let config = config.clone();
                move |output_dir: String| {
                    let mut new_config = config.clone();
                    new_config.output_dir = output_dir;
                    on_change.call(new_config);
                }
            }
        }
        SettingsTagInput {
            label: "Members",
            tags: config.members.clone(),
            placeholder: Some("Add member pattern...".to_string()),
            on_change: {
                let config = config.clone();
                move |members: Vec<String>| {
                    let mut new_config = config.clone();
                    new_config.members = members;
                    on_change.call(new_config);
                }
            }
        }
        SettingsTagInput {
            label: "Exclude",
            tags: config.exclude.clone(),
            placeholder: Some("Add exclude pattern...".to_string()),
            on_change: {
                let config = config.clone();
                move |exclude: Vec<String>| {
                    let mut new_config = config.clone();
                    new_config.exclude = exclude;
                    on_change.call(new_config);
                }
            }
        }
    }
}

#[component]
fn CodegenSettingsFields(
    config: CodegenConfig,
    on_change: EventHandler<CodegenConfig>,
) -> Element {
    let output_format_value = match config.output_format {
        OutputFormat::Pretty => "pretty",
        OutputFormat::Compact => "compact",
        OutputFormat::Minified => "minified",
    };

    rsx! {
        SettingsTagInput {
            label: "Targets",
            tags: config.targets.clone(),
            placeholder: Some("Add target (go, typescript, scala, json-schema)...".to_string()),
            on_change: {
                let config = config.clone();
                move |targets: Vec<String>| {
                    let mut new_config = config.clone();
                    new_config.targets = targets;
                    on_change.call(new_config);
                }
            }
        }
        SettingsSelect {
            label: "Output Format",
            value: output_format_value.to_string(),
            options: vec![
                ("pretty".to_string(), "Pretty".to_string()),
                ("compact".to_string(), "Compact".to_string()),
                ("minified".to_string(), "Minified".to_string()),
            ],
            on_change: {
                let config = config.clone();
                move |format: String| {
                    let mut new_config = config.clone();
                    new_config.output_format = match format.as_str() {
                        "compact" => OutputFormat::Compact,
                        "minified" => OutputFormat::Minified,
                        _ => OutputFormat::Pretty,
                    };
                    on_change.call(new_config);
                }
            }
        }
    }
}

#[component]
fn IrSettingsFields(config: IrConfig, on_change: EventHandler<IrConfig>) -> Element {
    rsx! {
        SettingsNumberInput {
            label: "Format Version",
            value: config.format_version as u64,
            min: Some(1),
            max: Some(10),
            on_change: {
                let config = config.clone();
                move |version: u64| {
                    let mut new_config = config.clone();
                    new_config.format_version = version as u32;
                    on_change.call(new_config);
                }
            }
        }
        SettingsToggle {
            label: "Strict Mode",
            description: Some("Treat validation warnings as errors".to_string()),
            checked: config.strict_mode,
            on_change: {
                let config = config.clone();
                move |strict_mode: bool| {
                    let mut new_config = config.clone();
                    new_config.strict_mode = strict_mode;
                    on_change.call(new_config);
                }
            }
        }
    }
}

#[component]
fn CacheSettingsFields(config: CacheConfig, on_change: EventHandler<CacheConfig>) -> Element {
    rsx! {
        SettingsToggle {
            label: "Enabled",
            description: Some("Enable caching for faster builds".to_string()),
            checked: config.enabled,
            on_change: {
                let config = config.clone();
                move |enabled: bool| {
                    let mut new_config = config.clone();
                    new_config.enabled = enabled;
                    on_change.call(new_config);
                }
            }
        }
        SettingsTextInput {
            label: "Directory",
            value: config.dir.clone(),
            placeholder: Some("Default cache directory".to_string()),
            on_change: {
                let config = config.clone();
                move |dir: String| {
                    let mut new_config = config.clone();
                    new_config.dir = dir;
                    on_change.call(new_config);
                }
            }
        }
        SettingsNumberInput {
            label: "Max Size (bytes)",
            value: config.max_size,
            min: Some(0),
            max: None,
            on_change: {
                let config = config.clone();
                move |max_size: u64| {
                    let mut new_config = config.clone();
                    new_config.max_size = max_size;
                    on_change.call(new_config);
                }
            }
        }
    }
}

#[component]
fn LoggingSettingsFields(
    config: LoggingConfig,
    on_change: EventHandler<LoggingConfig>,
) -> Element {
    let level_value = match config.level {
        LogLevel::Debug => "debug",
        LogLevel::Info => "info",
        LogLevel::Warn => "warn",
        LogLevel::Error => "error",
    };

    let format_value = match config.format {
        LogFormat::Text => "text",
        LogFormat::Json => "json",
    };

    rsx! {
        SettingsSelect {
            label: "Level",
            value: level_value.to_string(),
            options: vec![
                ("debug".to_string(), "Debug".to_string()),
                ("info".to_string(), "Info".to_string()),
                ("warn".to_string(), "Warn".to_string()),
                ("error".to_string(), "Error".to_string()),
            ],
            on_change: {
                let config = config.clone();
                move |level: String| {
                    let mut new_config = config.clone();
                    new_config.level = match level.as_str() {
                        "debug" => LogLevel::Debug,
                        "warn" => LogLevel::Warn,
                        "error" => LogLevel::Error,
                        _ => LogLevel::Info,
                    };
                    on_change.call(new_config);
                }
            }
        }
        SettingsSelect {
            label: "Format",
            value: format_value.to_string(),
            options: vec![
                ("text".to_string(), "Text".to_string()),
                ("json".to_string(), "JSON".to_string()),
            ],
            on_change: {
                let config = config.clone();
                move |format: String| {
                    let mut new_config = config.clone();
                    new_config.format = match format.as_str() {
                        "json" => LogFormat::Json,
                        _ => LogFormat::Text,
                    };
                    on_change.call(new_config);
                }
            }
        }
        SettingsTextInput {
            label: "Log File",
            value: config.file.clone(),
            placeholder: Some("stderr (default)".to_string()),
            on_change: {
                let config = config.clone();
                move |file: String| {
                    let mut new_config = config.clone();
                    new_config.file = file;
                    on_change.call(new_config);
                }
            }
        }
    }
}

#[component]
fn UiSettingsFields(config: UiConfig, on_change: EventHandler<UiConfig>) -> Element {
    let theme_value = match config.theme {
        UiTheme::Default => "default",
        UiTheme::Light => "light",
        UiTheme::Dark => "dark",
    };

    rsx! {
        SettingsToggle {
            label: "Color Output",
            description: Some("Enable colored terminal output".to_string()),
            checked: config.color,
            on_change: {
                let config = config.clone();
                move |color: bool| {
                    let mut new_config = config.clone();
                    new_config.color = color;
                    on_change.call(new_config);
                }
            }
        }
        SettingsToggle {
            label: "Interactive Mode",
            description: Some("Enable interactive prompts".to_string()),
            checked: config.interactive,
            on_change: {
                let config = config.clone();
                move |interactive: bool| {
                    let mut new_config = config.clone();
                    new_config.interactive = interactive;
                    on_change.call(new_config);
                }
            }
        }
        SettingsSelect {
            label: "Theme",
            value: theme_value.to_string(),
            options: vec![
                ("default".to_string(), "Default".to_string()),
                ("light".to_string(), "Light".to_string()),
                ("dark".to_string(), "Dark".to_string()),
            ],
            on_change: {
                let config = config.clone();
                move |theme: String| {
                    let mut new_config = config.clone();
                    new_config.theme = match theme.as_str() {
                        "light" => UiTheme::Light,
                        "dark" => UiTheme::Dark,
                        _ => UiTheme::Default,
                    };
                    on_change.call(new_config);
                }
            }
        }
    }
}
