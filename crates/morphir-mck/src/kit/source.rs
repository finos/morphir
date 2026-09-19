//! Where a kit's bytes come from. The kit is read either from a directory
//! (`--kit`, usually a checkout of finos/morphir) or from the copy embedded in
//! the binary, and a `text` fence may name any file of the parent repository.
//! Every key is a repository-relative POSIX path, so one key space serves both.

use std::borrow::Cow;
use std::collections::BTreeMap;
use std::io;
use std::path::{Path, PathBuf};

use super::syntax::text::utf16_cmp;

/// The kit directory's repository-relative path.
pub const KIT_PATH: &str = "spec/ir/mck";

#[derive(Debug, Clone)]
pub enum KitSource {
    Directory {
        kit_root: PathBuf,
        repo_root: Option<PathBuf>,
    },
    Map {
        label: String,
        files: BTreeMap<String, Cow<'static, [u8]>>,
    },
}

/// Joins a repository-relative path under `root`, or refuses. A relative path
/// must stay inside its root: no absolute path, no `..`, and no backslash
/// (keys are POSIX; `..\secret` has no `/` segment equal to `..` and would walk
/// out of the root on Windows). As a second line of defence the joined path
/// must still start with the root, which also refuses a drive-relative
/// segment such as `C:x`.
fn safe_join(root: &Path, relative: &str) -> Option<PathBuf> {
    if relative.starts_with('/') || relative.contains('\\') || Path::new(relative).is_absolute() {
        return None;
    }
    let mut joined = root.to_path_buf();
    for segment in relative.split('/').filter(|s| !s.is_empty() && *s != ".") {
        if segment == ".." {
            return None;
        }
        joined.push(segment);
    }
    joined.starts_with(root).then_some(joined)
}

fn walk(directory: &Path, prefix: &str, out: &mut Vec<String>) -> io::Result<()> {
    let mut entries = std::fs::read_dir(directory)?.collect::<io::Result<Vec<_>>>()?;
    entries.sort_by(|a, b| {
        utf16_cmp(
            &a.file_name().to_string_lossy(),
            &b.file_name().to_string_lossy(),
        )
    });
    for entry in entries {
        let name = entry.file_name();
        let key = format!("{prefix}/{}", name.to_string_lossy());
        let kind = entry.file_type()?;
        if kind.is_dir() {
            walk(&entry.path(), &key, out)?;
        } else if kind.is_file() {
            out.push(key);
        }
    }
    Ok(())
}

impl KitSource {
    /// A kit directory. `repo_root` resolves `text` fences that name files
    /// outside the kit; when absent it is inferred for a directory whose path
    /// ends in `spec/ir/mck`.
    pub fn directory(kit_directory: &Path, repo_root: Option<&Path>) -> Self {
        let kit_root =
            std::path::absolute(kit_directory).unwrap_or_else(|_| kit_directory.to_path_buf());
        let inferred = || {
            let mut ancestors = kit_root.ancestors();
            let matches = KIT_PATH.rsplit('/').all(|segment| {
                ancestors
                    .next()
                    .and_then(Path::file_name)
                    .is_some_and(|name| name == segment)
            });
            matches
                .then(|| ancestors.next().map(Path::to_path_buf))
                .flatten()
        };
        let repo_root = match repo_root {
            Some(root) => Some(std::path::absolute(root).unwrap_or_else(|_| root.to_path_buf())),
            None => inferred(),
        };
        Self::Directory {
            kit_root,
            repo_root,
        }
    }

    pub fn map(label: impl Into<String>, files: BTreeMap<String, Cow<'static, [u8]>>) -> Self {
        Self::Map {
            label: label.into(),
            files,
        }
    }

    pub fn label(&self) -> String {
        match self {
            Self::Directory { kit_root, .. } => kit_root.display().to_string(),
            Self::Map { label, .. } => label.clone(),
        }
    }

    pub fn repo_root(&self) -> Option<&Path> {
        match self {
            Self::Directory { repo_root, .. } => repo_root.as_deref(),
            Self::Map { .. } => None,
        }
    }

    fn locate(&self, relative: &str) -> Option<PathBuf> {
        let Self::Directory {
            kit_root,
            repo_root,
        } = self
        else {
            return None;
        };
        match relative
            .strip_prefix(KIT_PATH)
            .and_then(|rest| rest.strip_prefix('/'))
        {
            Some(inside) => safe_join(kit_root, inside),
            None => safe_join(repo_root.as_deref()?, relative),
        }
    }

    /// Repository-relative paths of every file under the kit directory.
    pub fn list(&self) -> io::Result<Vec<String>> {
        match self {
            Self::Directory { kit_root, .. } => {
                let mut out = Vec::new();
                walk(kit_root, KIT_PATH, &mut out)?;
                Ok(out)
            }
            Self::Map { files, .. } => Ok(files
                .keys()
                .filter(|k| k.starts_with(&format!("{KIT_PATH}/")))
                .cloned()
                .collect()),
        }
    }

    /// The bytes at a repository-relative path, or `None` when the source
    /// cannot provide it.
    pub fn read(&self, relative: &str) -> Option<Cow<'_, [u8]>> {
        match self {
            Self::Directory { .. } => {
                let file = self.locate(relative)?;
                file.is_file()
                    .then(|| std::fs::read(file).ok())
                    .flatten()
                    .map(Cow::Owned)
            }
            Self::Map { files, .. } => files
                .get(relative)
                .map(|bytes| Cow::Borrowed(bytes.as_ref())),
        }
    }

    /// What to call the path in messages: the real file for a directory
    /// source, the key otherwise.
    pub fn display(&self, relative: &str) -> String {
        self.locate(relative)
            .map_or_else(|| relative.to_owned(), |path| path.display().to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn safe_join_confines_a_path_to_its_root() {
        let root = std::path::absolute("some-root").unwrap();
        assert_eq!(
            safe_join(&root, "a/b.json"),
            Some(root.join("a").join("b.json"))
        );
        assert_eq!(
            safe_join(&root, "a/./b.json"),
            Some(root.join("a").join("b.json"))
        );
        for escape in [
            "../x",
            "a/../../x",
            "/etc/passwd",
            "..\\x",
            "a\\..\\..\\x",
            "C:\\x",
            "C:x",
        ] {
            assert_eq!(safe_join(&root, escape), None, "{escape}");
        }
    }

    #[test]
    fn a_directory_source_lists_reads_and_confines() {
        let repo = tempfile::tempdir().unwrap();
        let kit = repo.path().join("spec").join("ir").join("mck");
        std::fs::create_dir_all(kit.join("documents")).unwrap();
        std::fs::write(kit.join("types.md"), "## types-0001: x\n").unwrap();
        std::fs::write(kit.join("documents").join("a.yaml"), "a: 1\n").unwrap();
        std::fs::write(repo.path().join("outside.json"), "{}").unwrap();

        let source = KitSource::directory(&kit, None);
        assert_eq!(
            source.repo_root(),
            Some(std::path::absolute(repo.path()).unwrap().as_path())
        );
        assert_eq!(
            source.list().unwrap(),
            vec!["spec/ir/mck/documents/a.yaml", "spec/ir/mck/types.md"]
        );
        assert_eq!(
            source.read("spec/ir/mck/documents/a.yaml").as_deref(),
            Some(b"a: 1\n".as_slice())
        );
        assert_eq!(
            source.read("outside.json").as_deref(),
            Some(b"{}".as_slice())
        );
        assert_eq!(source.read("../mck-secret.json"), None);
        assert_eq!(source.read("spec/ir/mck/../../../outside.json"), None);
        assert_eq!(source.read("spec/ir/mck"), None);
    }

    #[test]
    fn a_directory_not_named_spec_ir_mck_has_no_inferred_root() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::write(dir.path().join("outside.json"), "{}").unwrap();
        let source = KitSource::directory(dir.path(), None);
        assert_eq!(source.repo_root(), None);
        assert_eq!(source.read("outside.json"), None);
    }

    #[test]
    fn a_map_source_lists_only_kit_keys_and_displays_the_key() {
        let files = BTreeMap::from([
            (
                "spec/ir/mck/types.md".to_owned(),
                Cow::Borrowed(b"x".as_slice()),
            ),
            (
                "website/static/x.json".to_owned(),
                Cow::Borrowed(b"{}".as_slice()),
            ),
        ]);
        let source = KitSource::map("embedded kit", files);
        assert_eq!(source.list().unwrap(), vec!["spec/ir/mck/types.md"]);
        assert_eq!(
            source.read("website/static/x.json").as_deref(),
            Some(b"{}".as_slice())
        );
        assert_eq!(
            source.display("spec/ir/mck/types.md"),
            "spec/ir/mck/types.md"
        );
    }
}
