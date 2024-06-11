use std::fmt::Debug;
use std::marker::PhantomData;
use tracing::instrument;

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

#[derive(Debug)]
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

#[derive(Debug)]
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

#[derive(Debug)]
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

#[instrument(level = "trace")]
pub fn is_satisfied_by<T, S>(candidate: &T, spec: S) -> bool
where
    S: Specification<T>,
    T: Debug,
{
    spec.is_satisfied_by(candidate)
}

#[cfg(test)]
mod tests {
    use tracing_test::traced_test;

    use super::*;
    use std::path::Path;

    static MANIFEST_DIR: &str = env!("CARGO_MANIFEST_DIR");
    #[derive(Debug)]
    struct IsDir;

    impl<T> Specification<T> for IsDir
    where
        T: AsRef<Path> + Debug,
    {
        fn is_satisfied_by(&self, candidate: &T) -> bool {
            candidate.as_ref().is_dir()
        }
    }

    #[derive(Debug)]
    struct IsFile;

    impl<T> Specification<T> for IsFile
    where
        T: AsRef<Path> + Debug,
    {
        fn is_satisfied_by(&self, candidate: &T) -> bool {
            candidate.as_ref().is_file()
        }
    }

    #[traced_test]
    #[test]
    fn test_is_satisfied_by() {
        let path = Path::new(MANIFEST_DIR);
        let is_dir = IsDir;
        let is_file = IsFile;
        assert!(is_satisfied_by(&path, is_dir));
        assert!(!is_satisfied_by(&path, is_file));
    }
}

//Match Spec + Traverse Spec
