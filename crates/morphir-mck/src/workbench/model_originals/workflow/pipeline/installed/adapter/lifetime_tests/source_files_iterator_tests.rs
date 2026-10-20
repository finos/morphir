//! Safe iterator length claims do not authorize unbudgeted receiving growth.
use super::*;
use crate::workbench::model_originals::native::data;

struct WrongLength<I> {
    actual: I,
    declared: usize,
}
impl<I: Iterator> Iterator for WrongLength<I> {
    type Item = I::Item;
    fn next(&mut self) -> Option<Self::Item> {
        self.actual.next()
    }
    fn size_hint(&self) -> (usize, Option<usize>) {
        (self.declared, Some(self.declared))
    }
}
impl<I: Iterator> ExactSizeIterator for WrongLength<I> {}

struct IteratorProbe {
    declared: usize,
    actual: usize,
    completed: bool,
}
impl InstalledClientAdapter for IteratorProbe {
    fn observe(
        &mut self,
        mut run: InstalledClientRun<'_>,
    ) -> Result<InstalledClientMeasurements, InstalledAdapterError> {
        let fixture = run.fixture();
        let rows = || WrongLength {
            actual: fixture.witnesses().take(self.actual).map(|(role, path)| {
                (
                    role,
                    path,
                    data::ReadCounts {
                        attempts: data::ObservedCount(0),
                        read_calls: data::ObservedCount(0),
                        returned_bytes: data::ObservedCount(0),
                    },
                )
            }),
            declared: self.declared,
        };
        assert!(matches!(
            run.retain_source_files(rows()),
            Err(InstalledAdapterError::ObservationIncomplete)
        ));
        assert!(matches!(
            run.receiving.ready(),
            Err(InstalledObservationError::LayoutMismatch)
        ));
        assert!(run.attempt.fault.is_some());
        let receiving = run.receiving.usage();
        let decode = run.decode.usage();
        let comparison = run.comparison.usage();
        assert!(matches!(
            run.retain_source_files(rows()),
            Err(InstalledAdapterError::ObservationIncomplete)
        ));
        assert_eq!(run.receiving.usage(), receiving);
        assert_eq!(run.decode.usage(), decode);
        assert_eq!(run.comparison.usage(), comparison);
        self.completed = true;
        Err(InstalledAdapterError::ObservationIncomplete)
    }
}
fn exercise(declared: usize, actual: usize) {
    let kit = tempfile::tempdir().unwrap();
    std::fs::write(kit.path().join("cases.json"), CASES).unwrap();
    let mut probe = IteratorProbe {
        declared,
        actual,
        completed: false,
    };
    let report =
        run_configured_with_installed_client_adapter(kit.path(), &configuration(), &mut probe)
            .unwrap();
    assert!(probe.completed);
    assert!(!report.qualified());
}
#[test]
fn source_file_iterator_overrun_refuses_before_extra_row_copy_and_latches_layout() {
    exercise(1, 2);
}
#[test]
fn source_file_iterator_underrun_refuses_and_latches_same_owner_layout() {
    exercise(2, 1);
}
