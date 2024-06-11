use derive_more::{From, FromStr};
use serde::{Deserialize, Serialize};

pub mod error;

#[derive(Debug, Deserialize, Serialize)]
pub struct ProjectManifest {
    name: ProjectName,
}

impl ProjectManifest {
    pub fn name_as_string(&self) -> String {
        self.name.0.clone()
    }

    pub fn name(&self) -> &ProjectName {
        &self.name
    }
}

#[derive(Clone, Debug, Eq, Ord, PartialEq, PartialOrd, Serialize, Deserialize, From, FromStr)]
pub struct ProjectName(String);

impl From<&str> for ProjectName {
    fn from(s: &str) -> Self {
        ProjectName(s.to_string())
    }
}
