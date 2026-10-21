//! Genuine Run accounting controls for the borrowed command-argument bridge.
use super::*;

struct ClaimedLength<'a> {
    values: std::slice::Iter<'a, &'a OsStr>,
    claimed: usize,
}
impl<'a> Iterator for ClaimedLength<'a> {
    type Item = &'a OsStr;
    fn next(&mut self) -> Option<Self::Item> {
        self.values.next().copied()
    }
    fn size_hint(&self) -> (usize, Option<usize>) {
        (self.claimed, Some(self.claimed))
    }
}
impl ExactSizeIterator for ClaimedLength<'_> {
    fn len(&self) -> usize {
        self.claimed
    }
}
enum Case {
    Exact,
    Overrun,
    Underrun,
    Storage,
}
struct Probe {
    case: Case,
    entered: bool,
}
impl InstalledClientAdapter for Probe {
    fn observe(
        &mut self,
        mut run: InstalledClientRun<'_>,
    ) -> Result<InstalledClientMeasurements, InstalledAdapterError> {
        self.entered = true;
        let values = [
            OsStr::new("--originals-helper"),
            OsStr::new("/actual borrowed operand"),
        ];
        match self.case {
            Case::Exact => {
                let copied = run.copy_command_arguments(values.into_iter()).unwrap();
                assert_eq!(copied, values);
            }
            Case::Overrun | Case::Underrun => {
                let before = run.installed_observation_usage();
                let (slice, claimed) = match self.case {
                    Case::Overrun => (&values[..1], 0),
                    Case::Underrun => (&values[..0], 1),
                    _ => unreachable!(),
                };
                assert!(
                    run.copy_command_arguments(ClaimedLength {
                        values: slice.iter(),
                        claimed
                    })
                    .is_err()
                );
                assert_eq!(
                    run.receiving.ready().err(),
                    Some(&InstalledObservationError::LayoutMismatch)
                );
                let usage = run.installed_observation_usage();
                if matches!(self.case, Case::Overrun) {
                    // The extra yielded operand is refused before text copy or
                    // excess push. The zero-length vector requests no storage.
                    assert_eq!(usage, before);
                }
                assert!(run.copy_command_arguments(values.into_iter()).is_err());
                assert_eq!(run.installed_observation_usage(), usage);
            }
            Case::Storage => {
                let remaining = 16_777_216u64 - run.installed_observation_usage().retained_bytes();
                run.reserve_storage(usize::try_from(remaining - 1).unwrap())
                    .unwrap();
                assert!(run.copy_command_arguments(values.into_iter()).is_err());
                assert!(matches!(
                    run.receiving.ready(),
                    Err(InstalledObservationError::Resource {
                        kind: InstalledObservationResource::RetainedBytes,
                        ..
                    })
                ));
                let usage = run.installed_observation_usage();
                assert!(run.copy_command_arguments(values.into_iter()).is_err());
                assert_eq!(run.installed_observation_usage(), usage);
            }
        }
        Err(InstalledAdapterError::ObservationIncomplete)
    }
}
fn exercise(case: Case) {
    let mut probe = Probe {
        case,
        entered: false,
    };
    with_original_foundation_policy(&mut probe);
    assert!(probe.entered, "complete24 genuine callback required");
}
#[test]
fn copied_arguments_preserve_actual_borrowed_operands() {
    exercise(Case::Exact);
}
#[test]
fn advisory_iterator_lengths_cannot_copy_or_push_an_unfunded_extra_operand() {
    exercise(Case::Overrun);
    exercise(Case::Underrun);
}
#[test]
fn argument_table_storage_refusal_is_sticky_before_copy() {
    exercise(Case::Storage);
}
