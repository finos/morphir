//! Generate command for code generation from Morphir IR

mod artifacts;
mod options;
mod provider;

pub use options::GenerateOptions;

use crate::commands::ir_storage;
use crate::commands::out_context::{OutContext, report_config_warnings};
use crate::error::{CliError, convert_extension_diagnostics};
use crate::home::MorphirHome;
use morphir_devkit::{
    ConfigContext, TaskId, TaskResult, discover_config, ensure_morphir_structure,
    load_config_context,
};
use morphir_distribution::list_installed;
use morphir_extension_sdk::GenerateRequest;
use starbase::AppResult;
use std::path::{Path, PathBuf};

/// The task whose IR generate consumes. Today always `compile`. When
/// `[pipeline].transforms` exists this returns the last transform instead;
/// nothing else may hardcode `compile.dest`.
pub fn resolve_ir_task(_context: &ConfigContext) -> TaskId {
    TaskId::compile()
}

/// Run the generate command
pub async fn run_generate(options: GenerateOptions) -> AppResult<miette::Report> {
    use crate::output::{GenerateOutput, OutputFormat, write_generate_human, write_output};
    let GenerateOptions {
        target,
        input,
        output,
        config_path,
        project: _project,
        backend_options,
        json,
        json_lines,
        out,
    } = options;
    // Discover config if not provided
    let start_dir = std::env::current_dir().map_err(|e| CliError::FileSystem { error: e })?;

    let config_file = if let Some(cfg) = config_path {
        PathBuf::from(cfg)
    } else {
        discover_config(&start_dir)
            .map_err(|error| CliError::Config { error })?
            .ok_or_else(|| CliError::Config {
                error: anyhow::anyhow!("No morphir.toml, morphir.yaml, or morphir.json found"),
            })?
    };

    // Load config context
    let ctx = load_config_context(&config_file).map_err(|e| CliError::Config { error: e })?;

    // Ensure .morphir/ structure exists
    ensure_morphir_structure(&ctx.morphir_dir).map_err(|e| CliError::Config { error: e })?;

    // Determine target (from CLI or config)
    let target_lang = target
        .or_else(|| {
            ctx.config
                .codegen
                .as_ref()
                .and_then(|c| c.targets.first().cloned())
        })
        .ok_or_else(|| CliError::Config {
            error: anyhow::anyhow!("Target not specified and not found in config"),
        })?;

    let configured_options = options::target_options(ctx.config.codegen.as_ref(), &target_lang)
        .map_err(|error| CliError::Config { error })?;
    let backend_options = options::merge_options(configured_options, &backend_options)
        .map_err(|error| CliError::Config { error })?;

    report_config_warnings(&ctx);
    let out = OutContext::resolve(Some(&ctx), &out, &start_dir);

    // Determine IR input: either an explicit `-i` path, probed directly, or
    // the IR descriptor recorded by the task `resolve_ir_task` names.
    let (ir_base, descriptor, input_task) = match input {
        Some(explicit) => {
            let path = PathBuf::from(&explicit);
            let path = if path.is_absolute() {
                path
            } else {
                start_dir.join(path)
            };
            if !path.exists() {
                return Err(CliError::FileSystem {
                    error: std::io::Error::new(
                        std::io::ErrorKind::NotFound,
                        format!("IR input path does not exist: {}", path.display()),
                    ),
                }
                .into());
            }
            let (base, descriptor) = ir_storage::probe_external(&path)?;
            (base, descriptor, None)
        }
        None => {
            let task = resolve_ir_task(&ctx);
            let paths = out.task(&task);
            let record =
                TaskResult::read(&paths.result).map_err(|error| CliError::Config { error })?;
            // A missing record and a tombstone (left behind by
            // `prepare_dest` when a run starts, and still there if that run
            // failed) both mean the same thing here: there is no compile
            // output to read. A record that succeeded but produced no IR is
            // different — the task ran and produced *something*, just not IR
            // — and keeps its own message.
            let record = match record {
                Some(record) if !record.tombstone => record,
                _ => {
                    return Err(CliError::Validation {
                        message:
                            "compile output missing or incomplete, run `morphir compile` first"
                                .into(),
                    }
                    .into());
                }
            };
            let descriptor = record.ir.ok_or_else(|| CliError::Validation {
                message: format!("task '{}' produced no IR descriptor", record.task),
            })?;
            (paths.dest, descriptor, Some(task))
        }
    };
    let ir_data = ir_storage::read_value(&ir_base, &descriptor)?;
    let ir_version = provider::detect_ir_major(&ir_data)?;

    let generate_task = TaskId::generate(&target_lang);
    let prepared = out.prepare_dest(&generate_task)?;
    let generate_paths = prepared.paths;
    let output_path = generate_paths.dest.clone();

    let home = MorphirHome::resolve().map_err(|error| CliError::Config { error })?;
    let installed = list_installed(&home).map_err(|error| CliError::Extension {
        message: format!("Failed to list installed backend providers: {error}"),
    })?;
    let registry = crate::extensions::extension_registry(installed)?;
    let resolved = registry
        .resolve_backend(
            &target_lang,
            &ir_version,
            morphir_daemon::InvocationPolicy::PreferDirect,
        )
        .map_err(|error| CliError::Extension {
            message: format!("Failed to resolve backend for '{target_lang}': {error}"),
        })?;
    let workspace = ctx
        .project_root
        .clone()
        .unwrap_or_else(|| ctx.config_path.parent().unwrap().to_path_buf());
    let request = GenerateRequest {
        ir: ir_data,
        target: target_lang.clone(),
        options: serde_json::from_value(backend_options).map_err(|error| CliError::Config {
            error: error.into(),
        })?,
    };
    let result = crate::extensions::invoke_backend(&home, &workspace, &resolved, request).await?;

    let format = OutputFormat::from_flags(json, json_lines);

    let diagnostics = convert_extension_diagnostics(&result.diagnostics);

    if !result.success {
        let error_msg = "Code generation failed";
        let output = GenerateOutput {
            success: false,
            artifacts: vec![],
            diagnostics,
            output_path: output_path.to_string_lossy().to_string(),
            installed_path: None,
        };
        if format == OutputFormat::Human {
            write_generate_human(&output).map_err(CliError::from)?;
        } else {
            write_output(format, &output).map_err(CliError::from)?;
        }
        return Err(CliError::Compilation {
            message: error_msg.to_string(),
        }
        .into());
    }

    let artifacts = publish_returned_artifacts(&output_path, &result.artifacts)?;
    let artifacts: Vec<String> = artifacts
        .into_iter()
        .filter(|path| path != artifacts::MANIFEST_PATH)
        .collect();

    let mut record = TaskResult::new(&generate_task, &out.module);
    record.inputs = input_task
        .as_ref()
        .map(|task| vec![task.as_str().to_owned()])
        .unwrap_or_default();
    record.value = artifacts.clone();
    record.installed = prepared.previous_installed;
    record
        .write(&generate_paths.result)
        .map_err(|error| CliError::Config { error })?;
    let installed_path =
        crate::commands::install::maybe_install(&generate_paths, output.as_deref(), &start_dir)?;
    // The task is finished: its record is written and its install is done, so
    // the next run of this task may start.
    drop(prepared.lock);

    let output = GenerateOutput {
        success: true,
        artifacts,
        diagnostics,
        output_path: output_path.to_string_lossy().to_string(),
        installed_path,
    };
    if format == OutputFormat::Human {
        write_generate_human(&output).map_err(CliError::from)?;
    } else {
        write_output(format, &output).map_err(CliError::from)?;
    }

    Ok(None)
}

fn publish_returned_artifacts(
    output_path: &Path,
    returned: &[morphir_extension_sdk::Artifact],
) -> Result<Vec<String>, CliError> {
    artifacts::write_all(output_path, returned)
}

#[cfg(test)]
mod tests {
    use super::*;
    use morphir_extension_sdk::Artifact;
    use tempfile::tempdir;

    #[test]
    fn returned_legacy_artifacts_are_published_by_the_host_writer() {
        let root = tempdir().unwrap();
        let output = root.path().join("output");
        let returned = vec![Artifact {
            path: "nested/schema.avsc".to_owned(),
            content: "{\"type\":\"record\"}".to_owned(),
            binary: false,
        }];

        let paths = publish_returned_artifacts(&output, &returned).unwrap();

        assert_eq!(paths, ["nested/schema.avsc"]);
        assert_eq!(
            std::fs::read_to_string(output.join("nested/schema.avsc")).unwrap(),
            "{\"type\":\"record\"}"
        );
    }
}
