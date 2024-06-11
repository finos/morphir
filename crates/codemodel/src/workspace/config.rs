use derive_more::{From, FromStr};
use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize, Serialize)]
pub struct WorkspaceManifest {
    pub members: Vec<WorkspaceMember>,
}

#[derive(Debug, Deserialize, Eq, PartialEq, Ord, PartialOrd, Serialize, From, FromStr)]
pub struct WorkspaceMember(String);

impl From<&str> for WorkspaceMember {
    fn from(s: &str) -> Self {
        WorkspaceMember(s.to_string())
    }
}

impl WorkspaceMember {}

#[cfg(test)]
mod tests {
    use super::*;
    use starbase_sandbox::create_empty_sandbox;
}
