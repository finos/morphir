#![allow(dead_code, unused)]
pub mod project {

    #[derive(Debug, Eq, Ord, PartialOrd, PartialEq)]
    pub struct ProjectId(String);
    #[derive(Debug, Eq, Ord, PartialOrd, PartialEq)]
    pub struct ProjectAlias(String);

    #[derive(Debug, Eq, PartialEq)]
    pub struct Project {
        pub id: ProjectId,
        pub alias: Option<ProjectAlias>,
    }
}

pub mod workspace {
    use crate::models::project::Project;
    use crate::models::tools::ToolId;
    use starbase_utils::fs::find_upwards;
    use std::ffi::OsStr;
    use std::fmt::Debug;
    use std::path::{Path, PathBuf};
    use tracing::{instrument, trace};
    #[derive(Clone, Debug, Eq, Ord, PartialEq, PartialOrd)]
    pub struct WorkspaceRoot(PathBuf);
    impl WorkspaceRoot {
        #[inline]
        pub fn as_path(&self) -> &Path {
            self.0.as_path()
        }
    }

    impl From<PathBuf> for WorkspaceRoot {
        #[inline]
        fn from(path: PathBuf) -> Self {
            WorkspaceRoot(path)
        }
    }

    impl AsRef<Path> for WorkspaceRoot {
        #[inline]
        fn as_ref(&self) -> &Path {
            self.as_path()
        }
    }

    #[derive(Debug, Eq, PartialEq)]
    pub struct Workspace {
        root: WorkspaceRoot,
        projects: Vec<Project>,
    }

    impl Workspace {
        pub fn new(root: WorkspaceRoot) -> Self {
            Workspace {
                root,
                projects: Vec::new(),
            }
        }
        #[inline]
        #[instrument]
        pub fn find_root<F, S>(name: F, start_dir: S) -> Option<WorkspaceRoot>
        where
            F: AsRef<OsStr> + Debug,
            S: AsRef<Path> + Debug,
        {
            let found = find_upwards(name, start_dir);
            found.map(|p| WorkspaceRoot(p))
        }
    }
}

pub mod tools {

    #[derive(Clone, Debug, Eq, Ord, PartialEq, PartialOrd)]
    pub struct ToolId(String);

    impl ToolId {
        pub fn as_str(&self) -> &str {
            self.0.as_str()
        }
    }

    impl Default for ToolId {
        fn default() -> Self {
            ToolId("morphir".to_string())
        }
    }
}
