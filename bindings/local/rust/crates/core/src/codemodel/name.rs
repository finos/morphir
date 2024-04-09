use std::str::FromStr;

use crate::codemodel::run::Run;

pub struct NameBufDetails {
    pub runs: Vec<Run>,
    pub verified: bool,
}

pub struct NameStrDetails {
    pub value: String,
    pub verified: bool,
}

pub enum Name {
    NameBuf(NameBufDetails),
    NameStr(NameStrDetails),
}

pub enum NameParseError {
    InvalidName,
}

impl Name {
    
    pub fn is_verified(&self) -> bool {
        match self {
            Name::NameBuf(details) => details.verified,
            Name::NameStr(details) => details.verified,
        }
    }
}

impl FromStr for Name {
    type Err = NameParseError;

    fn from_str(_s: &str) -> Result<Self, Self::Err> {
        todo!()
    }
}
