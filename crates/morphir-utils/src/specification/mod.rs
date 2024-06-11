use std::fmt::Debug;
use std::marker::PhantomData;
use tracing::instrument;

pub mod path_spec;

pub trait Specification<T>: Sized
where
    T: Debug,
    Self: Debug,
{
    fn is_satisfied_by(&self, candidate: &T) -> bool;
    fn and<R>(self, other: R) -> AndSpecification<T, Self, R>
    where
        Self: Sized,
        R: Specification<T>,
    {
        AndSpecification {
            left: self,
            right: other,
            _phantom: PhantomData,
        }
    }

    fn or<R>(self, other: R) -> OrSpecification<T, Self, R>
    where
        Self: Sized,
        R: Specification<T>,
    {
        OrSpecification {
            left: self,
            right: other,
            _phantom: PhantomData,
        }
    }

    fn not(self) -> NotSpecification<T, Self>
    where
        Self: Sized,
    {
        NotSpecification {
            spec: self,
            _phantom: PhantomData,
        }
    }
}

#[derive(Clone, Debug)]
pub struct AndSpecification<T, L, R>
where
    L: Specification<T>,
    R: Specification<T>,
    T: Debug,
{
    left: L,
    right: R,
    _phantom: PhantomData<T>,
}

impl<T, A, B> Specification<T> for AndSpecification<T, A, B>
where
    A: Specification<T>,
    B: Specification<T>,
    T: Debug,
{
    fn is_satisfied_by(&self, candidate: &T) -> bool {
        self.left.is_satisfied_by(candidate) && self.right.is_satisfied_by(candidate)
    }
}

#[derive(Clone, Debug)]
pub struct OrSpecification<T, L, R>
where
    L: Specification<T>,
    R: Specification<T>,
    T: Debug,
{
    left: L,
    right: R,
    _phantom: PhantomData<T>,
}

impl<T, A, B> Specification<T> for OrSpecification<T, A, B>
where
    A: Specification<T> + Debug,
    B: Specification<T> + Debug,
    T: Debug,
    Self: Debug,
{
    fn is_satisfied_by(&self, candidate: &T) -> bool {
        self.left.is_satisfied_by(candidate) || self.right.is_satisfied_by(candidate)
    }
}

#[derive(Clone, Debug)]
pub struct NotSpecification<T, S>
where
    S: Specification<T>,
    T: Debug,
{
    spec: S,
    _phantom: PhantomData<T>,
}

impl<T, S> Specification<T> for NotSpecification<T, S>
where
    S: Specification<T>,
    T: Debug,
    Self: Debug,
{
    fn is_satisfied_by(&self, candidate: &T) -> bool {
        !self.spec.is_satisfied_by(candidate)
    }
}

#[inline]
#[instrument(level = "trace")]
pub fn is_satisfied_by<T, S>(candidate: &T, spec: &S) -> bool
where
    S: Specification<T>,
    T: Debug,
{
    spec.is_satisfied_by(candidate)
}

pub fn collect_all<I, T, S>(candidates: I, spec: &S) -> Vec<T>
where
    S: Specification<T>,
    I: IntoIterator<Item = T>,
    T: Debug,
{
    candidates
        .into_iter()
        .filter(|candidate| is_satisfied_by(candidate, spec))
        .collect()
}

#[cfg(test)]
mod tests {
    use tracing_test::traced_test;

    use super::*;
    use path_spec::{ContainsAnyOfTheseFiles, IsDir, IsFile};
    use std::path::Path;

    static MANIFEST_DIR: &str = env!("CARGO_MANIFEST_DIR");

    #[traced_test]
    #[test]
    fn test_is_satisfied_by() {
        let path = Path::new(MANIFEST_DIR);
        let is_dir = IsDir;
        let is_file = IsFile;
        assert!(is_satisfied_by(&path, &is_dir));
        assert!(!is_satisfied_by(&path, &is_file));
    }

    #[traced_test]
    #[test]
    fn test_and_spec() {
        let path = Path::new(MANIFEST_DIR);
        let is_dir = IsDir;
        let is_file = IsFile;
        let contains_any_of_these_files = ContainsAnyOfTheseFiles::new(["Cargo.toml"]);
        let contains_any_of_these_files2 = contains_any_of_these_files.clone();
        let spec = is_dir.and(contains_any_of_these_files);
        assert!(is_satisfied_by(&path, &spec));
        let spec = is_file.and(contains_any_of_these_files2);
        assert!(!is_satisfied_by(&path, &spec));
    }
}

//Match Spec + Traverse Spec
