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
    use std::ffi::OsString;
    use std::path::{Path, PathBuf};

    #[derive(Debug, Eq, Ord, PartialEq, PartialOrd)]
    pub struct WorkspaceRoot(PathBuf);

    #[derive(Debug, Eq, PartialEq)]
    pub struct Workspace {
        root: WorkspaceRoot,
        projects: Vec<Project>,
    }

    impl Workspace {
        fn find_root(
            config_dirname: &str,
            dir: &Path,
        ) -> Option<WorkspaceRoot> {
            let findable = dir.join(config_dirname);

            if findable.exists() {
                let root = findable.to_path_buf();
                return Some(WorkspaceRoot(root));
            }

            match dir.parent() {
                Some(parent_dir) => Self::find_root(config_dirname, parent_dir),
                None => None,
            }
        }
    }
}

pub mod tools {

    #[derive(Debug, Eq, Ord, PartialEq, PartialOrd)]
    pub struct ToolId(String);

    impl Default for ToolId {
        fn default() -> Self {
            ToolId("morphir".to_string())
        }
    }
}
