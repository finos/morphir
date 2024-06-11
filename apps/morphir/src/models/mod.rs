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
    pub use morphir_codemodel::workspace::WorkspaceRoot;
    use crate::models::project::Project;
    use crate::models::tools::ToolId;
    use std::ffi::OsStr;
    use std::fmt::Debug;
    use std::path::{Path, PathBuf};
    use tracing::{instrument, trace};

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
