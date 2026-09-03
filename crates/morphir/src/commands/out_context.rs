//! Out root and module path for the running command.

use crate::error::CliError;
use morphir_devkit::{ConfigContext, TaskId, TaskPaths, TaskResult, module_path, resolve_out_root};
use std::collections::BTreeMap;
use std::ffi::OsString;
use std::fs::File;
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

    /// Locations of one task with an empty `.dest`, ready for a run, plus
    /// the `installed` map the previous record (if any) carried. Starting a
    /// task invalidates whatever `.dest` held last time, so `.dest` is
    /// cleared here.
    ///
    /// The previous `.json`, if there is one, is not deleted — it is
    /// overwritten with a TOMBSTONE: the same record with `tombstone` set to
    /// true, `value` and `inputs` emptied, `language` and `ir` set to `None`,
    /// and `extra` (the `#[serde(flatten)]` catch-all for fields this version
    /// does not know, such as a future `inputsHash`) cleared too — a
    /// tombstone's `.dest` is empty, so nothing computed from the previous
    /// `.dest` may ride along on it. `installed` (and `completedAt`) are left
    /// exactly as they were.
    ///
    /// The `tombstone` flag is what readers go by. An empty `value` says
    /// nothing on its own: a run can succeed and produce no artifacts at all,
    /// and such a run still has to retire whatever it installed last time.
    /// If the run that is about to happen succeeds, the caller overwrites
    /// the tombstone with a real record built from `previous_installed`,
    /// same as always. If it fails instead, the tombstone is what stays on
    /// disk: `generate` treats a tombstone the same as a missing record (see
    /// its IR-input resolution), and a later `install::maybe_install` still
    /// finds the ledger of what an earlier successful run put at each `-o`
    /// target, so it does not mistake its own earlier output for foreign
    /// content. A plain delete-on-start, which is what this function used to
    /// do, loses that ledger the moment any run fails, which is the bug a
    /// tombstone fixes.
    ///
    /// The tombstone is written *before* `.dest` is cleared, not after: if
    /// the process were to crash (or `record.write` itself were to fail)
    /// between the two, writing the tombstone first means the failure leaves
    /// the previous run's SUCCESSFUL record sitting beside its own intact
    /// `.dest` — a state every reader already treats as a complete,
    /// consumable run. Clearing `.dest` first and writing the tombstone
    /// second would instead risk leaving the full previous record (still
    /// claiming a real `ir`) beside an empty `.dest`, which would make
    /// `generate` try to read IR that is no longer there and fail deep
    /// inside `read_value` with a raw I/O error instead of the friendly
    /// missing-record message.
    ///
    /// `installed` describes what is actually on disk at install targets
    /// from past runs, not anything about the run that is about to happen,
    /// so it must survive independently of the tombstone: the caller is
    /// expected to copy `previous_installed` onto the new record it builds
    /// before writing it, so that `install::maybe_install` sees an accurate
    /// previous-files list and can remove files a target no longer produces.
    ///
    /// A record that exists but fails to decode (hand-edited, truncated, or
    /// written by an incompatible version) is the *previous* run's
    /// bookkeeping, not a precondition of this run: this function treats it
    /// as absent rather than failing the run over it. It prints one
    /// `warning: ...` line naming the file and the decode error, proceeds
    /// with an empty `previous_installed`, and removes the file rather than
    /// trying to turn something unreadable into a tombstone. `TaskResult::read`
    /// itself stays strict — callers that genuinely need the record
    /// (`generate` reading its input) still get a hard error from a corrupt
    /// one.
    ///
    /// Everything from here on runs under an exclusive lock on the task, taken
    /// before the previous record is even read and released only when the
    /// returned [`PreparedTask`] is dropped. Two runs of the same task in one
    /// workspace share one `.dest` and one `.json`, so without it one run
    /// deletes `.dest` while the other is writing into it, and whichever
    /// finishes last overwrites the other's record — including its install
    /// ledger. Waiting is the right answer rather than failing: the second run
    /// wants the same task done, and once the first is finished it can simply
    /// take its turn.
    pub fn prepare_dest(&self, task: &TaskId) -> Result<PreparedTask, CliError> {
        let paths = self.task(task);
        let lock = TaskLock::acquire(&task_lock_path(&paths))?;
        let previous = TaskResult::read(&paths.result);
        let previous_installed = match &previous {
            Ok(Some(record)) => record.installed.clone(),
            Ok(None) => BTreeMap::new(),
            Err(error) => {
                eprintln!(
                    "warning: could not read previous task record at {}: {error}",
                    paths.result.display()
                );
                BTreeMap::new()
            }
        };
        match previous {
            Ok(Some(mut record)) => {
                record.tombstone = true;
                record.value = Vec::new();
                record.ir = None;
                record.inputs = Vec::new();
                record.language = None;
                record.extra = BTreeMap::new();
                record
                    .write(&paths.result)
                    .map_err(|error| CliError::Config { error })?;
            }
            Ok(None) => {}
            Err(_) => match std::fs::remove_file(&paths.result) {
                Ok(()) => {}
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
                Err(error) => return Err(CliError::FileSystem { error }),
            },
        }
        if paths.dest.exists() {
            std::fs::remove_dir_all(&paths.dest).map_err(|error| CliError::FileSystem { error })?;
        }
        std::fs::create_dir_all(&paths.dest).map_err(|error| CliError::FileSystem { error })?;
        Ok(PreparedTask {
            paths,
            previous_installed,
            lock,
        })
    }
}

/// The lock file guarding one task: `<task>.lock`, beside its `.dest` and
/// `.json`.
pub fn task_lock_path(paths: &TaskPaths) -> PathBuf {
    paths.result.with_extension("lock")
}

/// An exclusive advisory lock on one task, held for as long as this value
/// lives.
///
/// The lock is advisory, so it only keeps out other Morphir runs, which is
/// exactly the scope of the problem: nothing stops a user from deleting
/// `.dest` by hand while a run is in progress. The lock file itself is left on
/// disk between runs — removing it would race with another process that has
/// just opened it — and is empty, so it costs nothing to keep.
#[derive(Debug)]
pub struct TaskLock {
    file: File,
}

impl TaskLock {
    /// Take the lock, waiting for whoever holds it. Prints one line to stderr
    /// if the wait is not instant, so a run that appears to hang says why.
    fn acquire(path: &Path) -> Result<Self, CliError> {
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent).map_err(|error| CliError::FileSystem { error })?;
        }
        let file = std::fs::OpenOptions::new()
            .create(true)
            .truncate(false)
            .read(true)
            .write(true)
            .open(path)
            .map_err(|error| CliError::FileSystem { error })?;
        match fs2::FileExt::try_lock_exclusive(&file) {
            Ok(()) => {}
            Err(error) if error.raw_os_error() == fs2::lock_contended_error().raw_os_error() => {
                eprintln!(
                    "waiting for another Morphir run to finish this task ({})",
                    path.display()
                );
                fs2::FileExt::lock_exclusive(&file)
                    .map_err(|error| CliError::FileSystem { error })?;
            }
            Err(error) => return Err(CliError::FileSystem { error }),
        }
        Ok(Self { file })
    }
}

impl Drop for TaskLock {
    fn drop(&mut self) {
        // Closing the file releases the lock anyway; unlocking first just
        // makes the release explicit. Nothing useful can be done if it fails.
        drop(fs2::FileExt::unlock(&self.file));
    }
}

/// Result of [`OutContext::prepare_dest`]: a task's paths, ready for a run,
/// plus the `installed` map its previous result record carried before that
/// record was overwritten with a tombstone (or removed, if it was
/// unreadable).
#[derive(Debug)]
pub struct PreparedTask {
    /// Locations of the task, with a freshly emptied `.dest`. The result
    /// record, if there was one, is now a tombstone rather than gone.
    pub paths: TaskPaths,
    /// The previous result record's `installed` map, read before the record
    /// was turned into a tombstone. Empty when there was no previous record.
    /// Callers must set this on the new record they build for this run,
    /// before writing it, so that install bookkeeping survives across runs.
    pub previous_installed: BTreeMap<String, Vec<String>>,
    /// The task's exclusive lock. Callers hold it until the run's record is
    /// written and its install is finished, then drop it.
    pub lock: TaskLock,
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
        // The task lock is held until `prepared` is dropped, and a second
        // `prepare_dest` for the same task waits for it, so a test standing in
        // for two consecutive runs has to end the first one first.
        drop(prepared);
        let prepared = out.prepare_dest(&TaskId::compile()).unwrap();
        assert!(prepared.paths.dest.is_dir());
        assert!(!prepared.paths.dest.join("stale.txt").exists());
    }

    #[test]
    fn prepare_dest_leaves_the_previous_record_as_a_tombstone_instead_of_deleting_it() {
        let temp = tempfile::tempdir().unwrap();
        let out = OutContext::resolve(None, &OutOverrides::default(), temp.path());
        let prepared = out.prepare_dest(&TaskId::compile()).unwrap();
        let mut record = TaskResult::new(&TaskId::compile(), Path::new(""));
        record.language = Some("gleam".to_owned());
        record.inputs = vec!["parse".to_owned()];
        record.value = vec!["morphir-ir.json".to_owned()];
        record.ir = Some(morphir_devkit::IrDescriptor {
            path: "morphir-ir.json".to_owned(),
            layout: morphir_devkit::IrLayout::SingleFile,
            format: "json".to_owned(),
            version: "v4".to_owned(),
        });
        record
            .extra
            .insert("inputsHash".to_owned(), serde_json::json!("sha256:abc"));
        record.write(&prepared.paths.result).unwrap();

        drop(prepared);
        let prepared = out.prepare_dest(&TaskId::compile()).unwrap();
        assert!(
            prepared.paths.result.is_file(),
            "the previous record must survive as a tombstone, not be deleted"
        );
        let tombstone = TaskResult::read(&prepared.paths.result).unwrap().unwrap();
        assert!(tombstone.tombstone, "a tombstone says so outright");
        assert!(tombstone.ir.is_none(), "a tombstone has no ir");
        assert!(tombstone.value.is_empty(), "a tombstone has no value");
        assert!(tombstone.inputs.is_empty(), "a tombstone has no inputs");
        assert!(tombstone.language.is_none(), "a tombstone has no language");
        assert!(
            tombstone.extra.is_empty(),
            "a tombstone must not carry forward unknown fields like inputsHash, \
             since they were computed from a .dest the tombstone no longer has: {:?}",
            tombstone.extra
        );
    }

    #[test]
    fn prepare_dest_leaves_a_tombstone_with_the_installed_map_intact_and_no_ir() {
        let temp = tempfile::tempdir().unwrap();
        let out = OutContext::resolve(None, &OutOverrides::default(), temp.path());
        let prepared = out.prepare_dest(&TaskId::compile()).unwrap();
        assert!(
            prepared.previous_installed.is_empty(),
            "there is no previous record on the first run"
        );

        let mut record = TaskResult::new(&TaskId::compile(), Path::new(""));
        record
            .installed
            .insert("/abs/dist".to_owned(), vec!["morphir-ir.json".to_owned()]);
        record.write(&prepared.paths.result).unwrap();

        drop(prepared);
        let prepared = out.prepare_dest(&TaskId::compile()).unwrap();
        assert_eq!(
            prepared.previous_installed.get("/abs/dist"),
            Some(&vec!["morphir-ir.json".to_owned()]),
            "prepare_dest must carry the previous record's installed map forward"
        );
        assert!(
            prepared.paths.result.is_file(),
            "the record must be left on disk as a tombstone, not removed"
        );
        let tombstone = TaskResult::read(&prepared.paths.result).unwrap().unwrap();
        assert_eq!(
            tombstone.installed.get("/abs/dist"),
            Some(&vec!["morphir-ir.json".to_owned()]),
            "the tombstone written to disk must keep the installed map intact"
        );
        assert!(tombstone.ir.is_none(), "a tombstone has no ir");
    }

    #[test]
    fn prepare_dest_treats_an_unreadable_record_as_absent() {
        let temp = tempfile::tempdir().unwrap();
        let out = OutContext::resolve(None, &OutOverrides::default(), temp.path());
        let prepared = out.prepare_dest(&TaskId::compile()).unwrap();
        std::fs::write(&prepared.paths.result, "not valid json").unwrap();
        assert!(prepared.paths.result.is_file());

        drop(prepared);
        let prepared = out
            .prepare_dest(&TaskId::compile())
            .expect("a corrupt previous record must not fail the run");
        assert!(
            prepared.previous_installed.is_empty(),
            "a corrupt record carries no installed bookkeeping forward"
        );
        assert!(
            !prepared.paths.result.exists(),
            "the corrupt record file is still removed"
        );
    }

    #[test]
    fn prepare_dest_holds_an_exclusive_lock_on_the_task() {
        let temp = tempfile::tempdir().unwrap();
        let out = OutContext::resolve(None, &OutOverrides::default(), temp.path());
        let prepared = out.prepare_dest(&TaskId::compile()).unwrap();

        let lock_path = task_lock_path(&prepared.paths);
        assert_eq!(lock_path, temp.path().join(".morphir/out/compile.lock"));
        let contender = std::fs::OpenOptions::new()
            .read(true)
            .write(true)
            .open(&lock_path)
            .unwrap();
        let error = fs2::FileExt::try_lock_exclusive(&contender)
            .expect_err("the prepared task holds the lock");
        assert_eq!(
            error.raw_os_error(),
            fs2::lock_contended_error().raw_os_error()
        );

        drop(prepared);
        fs2::FileExt::try_lock_exclusive(&contender)
            .expect("dropping the prepared task releases the lock");
        fs2::FileExt::unlock(&contender).unwrap();
    }

    #[test]
    fn a_second_prepare_dest_waits_for_the_first_to_finish() {
        use std::sync::mpsc::{RecvTimeoutError, channel};
        use std::time::Duration;

        let temp = tempfile::tempdir().unwrap();
        let out = OutContext::resolve(None, &OutOverrides::default(), temp.path());
        let first = out.prepare_dest(&TaskId::compile()).unwrap();

        let second_out = out.clone();
        let (finished, waiting) = channel();
        let second = std::thread::spawn(move || {
            let prepared = second_out.prepare_dest(&TaskId::compile()).unwrap();
            finished.send(()).unwrap();
            prepared
        });

        assert_eq!(
            waiting.recv_timeout(Duration::from_millis(250)),
            Err(RecvTimeoutError::Timeout),
            "the second run must wait while the first holds the task lock"
        );

        drop(first);
        waiting
            .recv_timeout(Duration::from_secs(30))
            .expect("the second run proceeds once the first releases the lock");
        second.join().unwrap();
    }
}
