//! Files come only from the borrowed compiled fixture recipes.
use crate::commands::mck::workbench::installed_launch::InstalledCommandPaths;
use morphir_mck::workbench::model_originals::installed::{
    InstalledAdapterError, InstalledClientRun, InstalledFixtureNode,
};
use std::{ffi::OsStr, io::Write, path::PathBuf, sync::atomic::AtomicBool};
use tokio::time::Instant;

pub(super) struct Fixture {
    _temporary: tempfile::TempDir,
    pub base: PathBuf,
    _base_directory: cap_std::fs::Dir,
    pub root: PathBuf,
    pub scratch: PathBuf,
    pub destination_directory: cap_std::fs::Dir,
    pub scratch_directory: cap_std::fs::Dir,
    pub paths: InstalledCommandPaths,
}
impl Fixture {
    pub fn materialize(
        run: &mut InstalledClientRun<'_>,
        end: Instant,
        interrupted: &AtomicBool,
    ) -> Result<Self, InstalledAdapterError> {
        let temporary = tempfile::tempdir().map_err(super::incomplete)?;
        let canonical = temporary.path().canonicalize().map_err(super::incomplete)?;
        let base = PathBuf::from(run.copy_command_operand(canonical.as_os_str())?);
        let base_directory =
            cap_std::fs::Dir::open_ambient_dir(&base, cap_std::ambient_authority())
                .map_err(super::incomplete)?;
        let root = run.command_path(&base, "workspace")?;
        let control = run.command_path(&base, "control")?;
        let destination = run.command_path(&base, "destination")?;
        let scratch = run.command_path(&base, "scratch")?;
        for path in [&root, &control, &destination, &scratch] {
            std::fs::create_dir(path).map_err(super::incomplete)?;
        }
        let destination_directory =
            cap_std::fs::Dir::open_ambient_dir(&destination, cap_std::ambient_authority())
                .map_err(super::incomplete)?;
        let scratch_directory =
            cap_std::fs::Dir::open_ambient_dir(&scratch, cap_std::ambient_authority())
                .map_err(super::incomplete)?;
        for node in run.fixture().nodes() {
            super::check(end, interrupted)?;
            let (relative, bytes) = match node {
                InstalledFixtureNode::Literal { path, bytes }
                | InstalledFixtureNode::ByteSource { path, bytes, .. } => (path, bytes),
            };
            let path = run.command_path(&root, relative.as_str())?;
            let parent = path
                .parent()
                .ok_or(InstalledAdapterError::ObservationIncomplete)?;
            std::fs::create_dir_all(parent).map_err(super::incomplete)?;
            let recipe = run.materialize_fixture_bytes(bytes)?;
            let mut file = std::fs::File::create(path).map_err(super::incomplete)?;
            let mut window = [0u8; 65_536];
            let mut offset = 0;
            while offset < recipe.byte_length() {
                super::check(end, interrupted)?;
                let count = window.len().min(recipe.byte_length() - offset);
                recipe
                    .fill_window(offset, &mut window[..count])
                    .map_err(super::incomplete)?;
                file.write_all(&window[..count])
                    .map_err(super::incomplete)?;
                offset += count;
            }
        }
        let launch = run.command_path(&control, "launch.txt")?;
        let connection = run.command_path(&control, "connection.json")?;
        let source = run.command_path(&control, "source.json")?;
        let project = run.command_path(&control, "project.json")?;
        let directory = PathBuf::from(run.copy_command_operand(base.as_os_str())?);
        let relative = PathBuf::from(run.copy_command_operand(OsStr::new("destination"))?);
        // Each new validation traversal is distinct from the funded copies:
        // absolute prefixes (including Windows UNC), relative components,
        // strip_prefix and suffix equality. Whole-target spans are conservative.
        for span in [
            launch.as_os_str().len(),
            connection.as_os_str().len(),
            source.as_os_str().len(),
            project.as_os_str().len(),
            directory.as_os_str().len(),
            destination.as_os_str().len(),
            relative.as_os_str().len(),
            destination.as_os_str().len(),
            directory.as_os_str().len(),
            destination.as_os_str().len(),
            relative.as_os_str().len(),
        ] {
            run.visit_observation_bytes(span)?;
        }
        let paths = InstalledCommandPaths::new_confined(
            launch,
            connection,
            source,
            project,
            directory,
            relative,
            destination,
        )
        .map_err(super::incomplete)?;
        Ok(Self {
            _temporary: temporary,
            base,
            _base_directory: base_directory,
            root,
            scratch,
            destination_directory,
            scratch_directory,
            paths,
        })
    }
    pub fn write_private(
        path: &std::path::Path,
        bytes: &[u8],
    ) -> Result<(), InstalledAdapterError> {
        let mut options = std::fs::OpenOptions::new();
        options.create_new(true).write(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt as _;
            options.mode(0o600);
        }
        let mut file = options.open(path).map_err(super::incomplete)?;
        file.write_all(bytes).map_err(super::incomplete)
    }
}
