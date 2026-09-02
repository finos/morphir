//! Out root and module path for the running command.

use crate::error::CliError;
use morphir_devkit::{ConfigContext, TaskId, TaskPaths, module_path, resolve_out_root};
use std::ffi::OsString;
use std::path::{Path, PathBuf};

/// Environment variable that relocates the out root.
pub const OUT_DIR_ENV: &str = "MORPHIR_OUT_DIR";

/// Out root overrides supplied by the process: the global `--out-dir` flag and
/// the `MORPHIR_OUT_DIR` variable. Commands never read the environment.
#[derive(Debug, Clone, Default)]
pub struct OutOverrides {
    /// `--out-dir` value.
    pub flag: Option<PathBuf>,
    /// `MORPHIR_OUT_DIR` value.
    pub env: Option<OsString>,
}

impl OutOverrides {
    /// Capture the flag and the current process environment.
    pub fn from_process(flag: Option<PathBuf>) -> Self {
        Self {
            flag,
            env: std::env::var_os(OUT_DIR_ENV),
        }
    }
}

/// Resolved out root and module path for one command run.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OutContext {
    /// Absolute out root.
    pub root: PathBuf,
    /// Module path relative to the workspace root. Empty for the root module.
    pub module: PathBuf,
}

impl OutContext {
    /// Resolve from an optional configuration context, the process overrides,
    /// and the current directory.
    pub fn resolve(context: Option<&ConfigContext>, overrides: &OutOverrides, cwd: &Path) -> Self {
        Self {
            root: resolve_out_root(
                overrides.flag.as_deref(),
                overrides.env.as_deref(),
                context,
                cwd,
            ),
            module: context.map(module_path).unwrap_or_default(),
        }
    }

    /// Locations of one task.
    pub fn task(&self, task: &TaskId) -> TaskPaths {
        TaskPaths::new(&self.root, &self.module, task)
    }

    /// Locations of one task with an empty `.dest`, ready for a run.
    pub fn prepare_dest(&self, task: &TaskId) -> Result<TaskPaths, CliError> {
        let paths = self.task(task);
        if paths.dest.exists() {
            std::fs::remove_dir_all(&paths.dest).map_err(|error| CliError::FileSystem { error })?;
        }
        std::fs::create_dir_all(&paths.dest).map_err(|error| CliError::FileSystem { error })?;
        Ok(paths)
    }
}

/// Print configuration warnings (removed or renamed keys) to stderr.
pub fn report_config_warnings(context: &ConfigContext) {
    for warning in &context.warnings {
        eprintln!("warning: {warning}");
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use morphir_devkit::{TaskId, load_config_context};
    use std::ffi::OsString;
    use std::path::{Path, PathBuf};

    fn project(temp: &Path) -> morphir_devkit::ConfigContext {
        std::fs::write(
            temp.join("morphir.toml"),
            "[project]\nname = \"acme/app\"\nversion = \"1.0.0\"\n",
        )
        .unwrap();
        load_config_context(&temp.join("morphir.toml")).unwrap()
    }

    #[test]
    fn resolves_the_default_root_under_the_project() {
        let temp = tempfile::tempdir().unwrap();
        let context = project(temp.path());
        let out = OutContext::resolve(Some(&context), &OutOverrides::default(), Path::new("/x"));
        assert_eq!(out.root, temp.path().join(".morphir/out"));
        assert_eq!(out.module, PathBuf::new());
        let paths = out.task(&TaskId::compile());
        assert_eq!(paths.dest, temp.path().join(".morphir/out/compile.dest"));
    }

    #[test]
    fn overrides_win_over_config() {
        let temp = tempfile::tempdir().unwrap();
        let context = project(temp.path());
        let overrides = OutOverrides {
            flag: None,
            env: Some(OsString::from("env-out")),
        };
        let out = OutContext::resolve(Some(&context), &overrides, temp.path());
        assert_eq!(out.root, temp.path().join("env-out"));
    }

    #[test]
    fn prepare_dest_clears_previous_contents() {
        let temp = tempfile::tempdir().unwrap();
        let out = OutContext::resolve(None, &OutOverrides::default(), temp.path());
        let paths = out.prepare_dest(&TaskId::compile()).unwrap();
        std::fs::write(paths.dest.join("stale.txt"), "old").unwrap();
        let paths = out.prepare_dest(&TaskId::compile()).unwrap();
        assert!(paths.dest.is_dir());
        assert!(!paths.dest.join("stale.txt").exists());
    }
}
