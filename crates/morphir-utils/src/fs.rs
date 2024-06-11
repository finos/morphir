use crate::fs_error::FsError;
use crate::fs_error::FsError::{AmbiguousMatches, NotFound};
use miette::Result;
use std::collections::HashSet;
use std::ffi::OsStr;
use std::fmt::Debug;
use std::path::{Path, PathBuf};
use tracing::instrument;

/// Return the name of a file or directory, or "unknown" if invalid UTF-8,
/// or unknown path component.
#[inline]
pub fn file_name<T: AsRef<Path>>(path: T) -> String {
    path.as_ref()
        .file_name()
        .unwrap_or_default()
        .to_str()
        .unwrap_or("<unknown>")
        .to_string()
}

#[inline]
pub fn find_upwards<F, S, P>(names: P, start_dir: S) -> Result<PathBuf, FsError>
where
    F: AsRef<OsStr> + Debug,
    S: AsRef<Path> + Debug,
    P: IntoIterator<Item = F> + Clone + Debug,
{
    find_upwards_until(names, start_dir, Path::new("/"))
}

#[inline]
#[instrument]
pub fn find_upwards_until<F, S, E, P>(
    names: P,
    start_dir: S,
    end_dir: E,
) -> Result<PathBuf, FsError>
where
    F: AsRef<OsStr> + Debug,
    S: AsRef<Path> + Debug,
    E: AsRef<Path> + Debug,
    P: IntoIterator<Item = F> + Clone + Debug,
{
    let candidate_names = names.clone();
    let unique_candidate_names = candidate_names
        .clone()
        .into_iter()
        .map(|n| n.as_ref().to_string_lossy().to_string())
        .collect::<HashSet<String>>();

    let dir = start_dir.as_ref();
    let candidates = candidate_names.into_iter().map(|n| dir.join(n.as_ref()));
    let mut found: HashSet<PathBuf> = HashSet::new();
    for candidate in candidates {
        match &candidate.canonicalize() {
            Ok(path) => {
                if path.is_file() {
                    found.insert(path.to_path_buf());
                }
            }
            _ => {
                if candidate.is_file() {
                    found.insert(candidate);
                }
            }
        }
    }

    match found.len() {
        0 => {
            if dir == end_dir.as_ref() {
                return Err(NotFound(unique_candidate_names));
            }

            if let Some(parent) = dir.parent() {
                find_upwards_until(names, parent, end_dir)
            } else {
                return Err(NotFound(unique_candidate_names));
            }
        }
        1 => {
            if let Some(item) = found.iter().next() {
                Ok(item.to_path_buf())
            } else {
                Err(NotFound(unique_candidate_names))
            }
        }
        _ => Err(AmbiguousMatches(found)),
    }
}

// pub fn find_upwards_until_pattern<S, E>(
//     pattern: Glob,
//     start_dir: S,
//     end_dir: E,
// ) -> Result<ManifestLocation>
// where
//     S: AsRef<Path> + Debug,
//     E: AsRef<Path> + Debug,
// {
//     trace!(
//         "Looking in {:?} for pattern {} up to {:?}",
//         start_dir,
//         pattern,
//         end_dir
//     );
//     let start_dir = start_dir.as_ref();

//     // let start_dir = start_dir
//     //     .canonicalize()
//     //     .into_diagnostic()
//     //     .wrap_err_with(|| format!("Failed to canonicalize path: {}", start_dir.display()))?;

//     if !start_dir.is_dir() {
//         if let Some(parent) = start_dir.parent() {
//             trace!("The provided start_dir is not a directory {:?} attempting to call with parent: {:?}", &start_dir, parent);
//             return find_upwards_until_pattern(pattern, parent, end_dir);
//         } else {
//             return Err(FsError::InvalidPath(start_dir.to_path_buf()))
//                 .into_diagnostic()
//                 .wrap_err_with(|| {
//                     format!("Failed to access parent for: {}", start_dir.display())
//                 })?;
//         }
//     }

//     let dir = start_dir;
//     let mut found: HashSet<PathBuf> = HashSet::new();
//     let walk = pattern.walk(dir);

//     for entry in walk {
//         match entry {
//             Ok(entry) => {
//                 let path = entry.path();
//                 trace!("Found path: {:?}", path);
//                 if path.is_file() {
//                     found.insert(path.to_path_buf());
//                 } else {
//                     trace!("Skipping directory: {:?}", path);
//                 }
//             }
//             Err(e) => {
//                 return Err(e).into_diagnostic().wrap_err_with(|| {
//                     format!("Failed to walk directory: {}", start_dir.display())
//                 })?;
//             }
//         }
//     }

//     match found.len() {
//         0 => {
//             if dir == end_dir.as_ref() {
//                 return Err(GlobPatternNotFound).into_diagnostic()?;
//             }

//             if let Some(parent) = dir.parent() {
//                 find_upwards_until(names, parent, end_dir)
//             } else {
//                 return Err(NotFound(unique_candidate_names));
//             }
//         }
//         1 => {
//             if let Some(item) = found.iter().next() {
//                 Ok(item.to_path_buf())
//             } else {
//                 Err(NotFound(unique_candidate_names))
//             }
//         }
//         _ => Err(AmbiguousMatches(found)),
//     }
// }

// pub struct ManifestLocation {
//     root: PathBuf,
//     manifest_path: PathBuf,
// }

// impl ManifestLocation {
//     #[inline]
//     pub fn root(&self) -> &Path {
//         &self.root
//     }

//     #[inline]
//     pub fn manifest_path(&self) -> &Path {
//         &self.manifest_path
//     }
// }

// pub trait FindStrategy {
//     type Location;

//     fn is_dir(path: &Path) -> bool {
//         path.is_dir()
//     }
//     fn satisfied(&self, dir: &Path) -> Result<Self::Location>;
// }

// pub struct MorphirManifestFinder;
// impl FindStrategy for MorphirManifestFinder {
//     type Location = ManifestLocation;

//     fn satisfied(&self, dir: &Path) -> Result<Self::Location> {
//         let manifest_path = find_upwards_until(
//             vec!["morphir.toml"],
//             dir,
//             Path::new("/"),
//         )?;
//         Ok(ManifestLocation {
//             root: dir.to_path_buf(),
//             manifest_path,
//         })
//     }
// }

#[cfg(test)]
pub mod test {
    //use path_absolutize::*;
    use std::path::{Path, PathBuf};
    //use tracing_test::traced_test;
    //use wax::Glob;
    //use smoothy::assert_that;

    static THIS_FILE: &str = file!();
    //static MANIFEST_DIR: &str = env!("CARGO_MANIFEST_DIR");
    #[test]
    pub fn test_find_upwards_until() {
        let this_dir: PathBuf = PathBuf::from(THIS_FILE).parent().unwrap().to_path_buf();
        let names = ["Cargo.toml"];
        let path = super::find_upwards_until(names, &this_dir, Path::new("/"));

        assert!(path.is_ok());
        let path = path.unwrap();
        assert_eq!(path.file_name().unwrap(), "Cargo.toml");
        assert_eq!(path.parent().unwrap().file_name().unwrap(), "morphir-utils");
    }
    #[test]
    pub fn test_find_upwards_until_with_multiple_names() {
        let this_dir: PathBuf = PathBuf::from(THIS_FILE).parent().unwrap().to_path_buf();
        let names = ["Cargo.toml", "cargo.toml"];
        let path = super::find_upwards_until(names, &this_dir, Path::new("/"));

        assert!(path.is_ok());
        let path = path.unwrap();
        assert_eq!(path.file_name().unwrap(), "Cargo.toml");
        assert_eq!(path.parent().unwrap().file_name().unwrap(), "morphir-utils");
    }

    // #[traced_test]
    // #[test]
    // pub fn test_find_upwards_until_pattern() -> Result<()> {
    //     let start_dir = PathBuf::from(MANIFEST_DIR)
    //         .join("../../tests-integration/workspace-layouts/multi/proj-a");
    //     let start_dir = start_dir.absolutize().into_diagnostic()?;
    //     let pattern = Glob::new(".morphir/workspace.toml").into_diagnostic()?;
    //     let location = super::find_upwards_until_pattern(pattern, &start_dir, Path::new("/"))?;

    //     assert_eq!(
    //         location.manifest_path.file_name().unwrap(),
    //         "workspace.toml"
    //     );
    //     Ok(())
    // }
}
