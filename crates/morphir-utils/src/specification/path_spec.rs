use super::Specification;
use std::fmt::Debug;
use std::path::{Path, PathBuf};

#[derive(Debug)]
pub struct IsDir;

impl<T> Specification<T> for IsDir
where
    T: AsRef<Path> + Debug,
{
    fn is_satisfied_by(&self, candidate: &T) -> bool {
        candidate.as_ref().is_dir()
    }
}

#[derive(Debug)]
pub struct IsFile;

impl<T> Specification<T> for IsFile
where
    T: AsRef<Path> + Debug,
{
    fn is_satisfied_by(&self, candidate: &T) -> bool {
        candidate.as_ref().is_file()
    }
}

#[derive(Clone, Debug)]
pub struct ContainsAnyOfTheseFiles {
    candidates: Vec<PathBuf>,
}

impl ContainsAnyOfTheseFiles {
    pub fn new<I, P>(candidates: I) -> Self
    where
        I: IntoIterator<Item = P>,
        P: Into<PathBuf>,
    {
        let candidates = candidates.into_iter().map(Into::into).collect();
        Self { candidates }
    }
}

impl<T> Specification<T> for ContainsAnyOfTheseFiles
where
    T: AsRef<Path> + Debug,
{
    fn is_satisfied_by(&self, candidate: &T) -> bool {
        let candidate = candidate.as_ref();
        self.candidates
            .iter()
            .any(|path| candidate.join(path).exists())
    }
}

#[derive(Clone, Debug)]
pub struct ConatainsAllOfTheseFiles {
    candidates: Vec<PathBuf>,
}

impl ConatainsAllOfTheseFiles {
    pub fn new<I, P>(candidates: I) -> Self
    where
        I: IntoIterator<Item = P>,
        P: Into<PathBuf>,
    {
        let candidates = candidates.into_iter().map(Into::into).collect();
        Self { candidates }
    }
}

impl<T> Specification<T> for ConatainsAllOfTheseFiles
where
    T: AsRef<Path> + Debug,
{
    fn is_satisfied_by(&self, candidate: &T) -> bool {
        let candidate = candidate.as_ref();
        self.candidates
            .iter()
            .all(|path| candidate.join(path).exists())
    }
}