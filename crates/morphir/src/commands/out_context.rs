//! Out root and module path for the running command.

use crate::error::CliError;
use morphir_devkit::{ConfigContext, TaskId, TaskPaths, TaskResult, module_path, resolve_out_root};
use std::collections::BTreeMap;
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

    /// Locations of one task with an empty `.dest` and no stale result
    /// record, ready for a run, plus the `ejected` map the previous record
    /// (if any) carried. Starting a task invalidates whatever it recorded
    /// last time, so the previous `.json` is removed along with the previous
    /// `.dest`: a run that fails after this point must not leave a prior
    /// success record behind for a later task to misread as current.
    ///
    /// `ejected` describes what is actually on disk at eject targets from
    /// past runs, not anything about the run that is about to happen, so it
    /// must survive the record being cleared here: the caller is expected to
    /// copy `previous_ejected` onto the new record it builds before writing
    /// it, so that `eject::maybe_eject` sees an accurate previous-files list
    /// and can remove files a target no longer produces. A failed run
    /// between two ejects still loses this map — nothing carries it forward
    /// across the deleted record — which can leave at most one stale file at
    /// a target; closing that would need an in-progress record that
    /// `generate` would then have to tell apart from a real one, which is
    /// out of scope here.
    ///
    /// A record that exists but fails to decode (hand-edited, truncated, or
    /// written by an incompatible version) is the *previous* run's
    /// bookkeeping, not a precondition of this run: this function treats it
    /// as absent rather than failing the run over it. It prints one
    /// `warning: ...` line naming the file and the decode error, proceeds
    /// with an empty `previous_ejected`, and still removes the file below,
    /// same as a record that parsed cleanly. `TaskResult::read` itself stays
    /// strict — callers that genuinely need the record (`generate` reading
    /// its input) still get a hard error from a corrupt one.
    pub fn prepare_dest(&self, task: &TaskId) -> Result<PreparedTask, CliError> {
        let paths = self.task(task);
        let previous_ejected = match TaskResult::read(&paths.result) {
            Ok(record) => record.map(|record| record.ejected).unwrap_or_default(),
            Err(error) => {
                eprintln!(
                    "warning: could not read previous task record at {}: {error}",
                    paths.result.display()
                );
                BTreeMap::new()
            }
        };
        if paths.dest.exists() {
            std::fs::remove_dir_all(&paths.dest).map_err(|error| CliError::FileSystem { error })?;
        }
        std::fs::create_dir_all(&paths.dest).map_err(|error| CliError::FileSystem { error })?;
        match std::fs::remove_file(&paths.result) {
            Ok(()) => {}
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
            Err(error) => return Err(CliError::FileSystem { error }),
        }
        Ok(PreparedTask {
            paths,
            previous_ejected,
        })
    }
}

/// Result of [`OutContext::prepare_dest`]: a task's paths, ready for a run,
/// plus the `ejected` map its previous result record carried before that
/// record was removed.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PreparedTask {
    /// Locations of the task, with a freshly emptied `.dest` and no result
    /// record on disk.
    pub paths: TaskPaths,
    /// The previous result record's `ejected` map, read before the record
    /// was removed. Empty when there was no previous record. Callers must
    /// set this on the new record they build for this run, before writing
    /// it, so that eject bookkeeping survives across runs.
    pub previous_ejected: BTreeMap<String, Vec<String>>,
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
        let prepared = out.prepare_dest(&TaskId::compile()).unwrap();
        std::fs::write(prepared.paths.dest.join("stale.txt"), "old").unwrap();
        let prepared = out.prepare_dest(&TaskId::compile()).unwrap();
        assert!(prepared.paths.dest.is_dir());
        assert!(!prepared.paths.dest.join("stale.txt").exists());
    }

    #[test]
    fn prepare_dest_removes_a_stale_result_record() {
        let temp = tempfile::tempdir().unwrap();
        let out = OutContext::resolve(None, &OutOverrides::default(), temp.path());
        let prepared = out.prepare_dest(&TaskId::compile()).unwrap();
        TaskResult::new(&TaskId::compile(), Path::new(""))
            .write(&prepared.paths.result)
            .unwrap();
        assert!(prepared.paths.result.is_file());

        let prepared = out.prepare_dest(&TaskId::compile()).unwrap();
        assert!(
            !prepared.paths.result.exists(),
            "a previous run's result record must not survive prepare_dest"
        );
    }

    #[test]
    fn prepare_dest_returns_the_previous_records_ejected_map_and_still_removes_it() {
        let temp = tempfile::tempdir().unwrap();
        let out = OutContext::resolve(None, &OutOverrides::default(), temp.path());
        let prepared = out.prepare_dest(&TaskId::compile()).unwrap();
        assert!(
            prepared.previous_ejected.is_empty(),
            "there is no previous record on the first run"
        );

        let mut record = TaskResult::new(&TaskId::compile(), Path::new(""));
        record
            .ejected
            .insert("/abs/dist".to_owned(), vec!["morphir-ir.json".to_owned()]);
        record.write(&prepared.paths.result).unwrap();

        let prepared = out.prepare_dest(&TaskId::compile()).unwrap();
        assert_eq!(
            prepared.previous_ejected.get("/abs/dist"),
            Some(&vec!["morphir-ir.json".to_owned()]),
            "prepare_dest must carry the previous record's ejected map forward"
        );
        assert!(
            !prepared.paths.result.exists(),
            "the stale record file is still removed"
        );
    }

    #[test]
    fn prepare_dest_treats_an_unreadable_record_as_absent() {
        let temp = tempfile::tempdir().unwrap();
        let out = OutContext::resolve(None, &OutOverrides::default(), temp.path());
        let prepared = out.prepare_dest(&TaskId::compile()).unwrap();
        std::fs::write(&prepared.paths.result, "not valid json").unwrap();
        assert!(prepared.paths.result.is_file());

        let prepared = out
            .prepare_dest(&TaskId::compile())
            .expect("a corrupt previous record must not fail the run");
        assert!(
            prepared.previous_ejected.is_empty(),
            "a corrupt record carries no ejected bookkeeping forward"
        );
        assert!(
            !prepared.paths.result.exists(),
            "the corrupt record file is still removed"
        );
    }
}
