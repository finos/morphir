//! Literal lower-level Read controls. Selected package/authentication coverage
//! is the separate explicit actual archive group, not these small fixtures.
use super::super::super::super::adapter::execution_loans::with_source_controller_lifetime;
use super::*;
use std::cell::Cell;

fn file(bytes: u64, digest: [u8; 32]) -> RuntimeFile {
    RuntimeFile {
        name: 0..0,
        bytes,
        digest,
        mode: RuntimePackageMode::Regular,
    }
}

#[test]
fn browser_runtime_reader_04_literal_short_eof_retains_count_and_stops() {
    with_source_controller_lifetime(|lifetime, loans| {
        let activity = lifetime.prepare_activity(loans).unwrap();
        let mut input = io::Cursor::new(b"ab");
        let mut window = [0; 8];
        let expected = file(4, Sha256::digest(b"abcd").into());
        let mut reader = RuntimeArchiveFile {
            entry: &mut input,
            activity: &activity,
            loans,
            window: &mut window,
            expected: &expected,
            hash: Sha256::new(),
            progress: EntryProgress::Reading { actual: 0 },
        };
        assert!(matches!(
            reader.next_chunk(),
            Err(RuntimeArchiveReadFault::Truncated {
                expected: 4,
                actual: 2
            })
        ));
        assert_eq!(
            &reader.window[..2],
            b"ab",
            "actual partial bytes survive refusal without emitting a full chunk"
        );
        assert!(matches!(
            reader.next_chunk(),
            Err(RuntimeArchiveReadFault::Truncated {
                expected: 4,
                actual: 2
            })
        ));
        assert!(matches!(
            reader.progress,
            EntryProgress::Refused { actual: 2, .. }
        ));
    });
}

#[test]
fn browser_runtime_reader_05_literal_actual_error_is_not_eof_and_is_not_retried() {
    struct Fails<'a>(&'a Cell<usize>);
    impl Read for Fails<'_> {
        fn read(&mut self, _: &mut [u8]) -> io::Result<usize> {
            self.0.set(self.0.get() + 1);
            Err(io::ErrorKind::PermissionDenied.into())
        }
    }
    with_source_controller_lifetime(|lifetime, loans| {
        let activity = lifetime.prepare_activity(loans).unwrap();
        let reads = Cell::new(0);
        let mut input = Fails(&reads);
        let mut window = [0; 8];
        let expected = file(1, Sha256::digest(b"a").into());
        let mut reader = RuntimeArchiveFile {
            entry: &mut input,
            activity: &activity,
            loans,
            window: &mut window,
            expected: &expected,
            hash: Sha256::new(),
            progress: EntryProgress::Reading { actual: 0 },
        };
        assert!(matches!(
            reader.next_chunk(),
            Err(RuntimeArchiveReadFault::Archive(
                io::ErrorKind::PermissionDenied
            ))
        ));
        assert!(matches!(
            reader.next_chunk(),
            Err(RuntimeArchiveReadFault::Archive(
                io::ErrorKind::PermissionDenied
            ))
        ));
        assert_eq!(reads.get(), 1);
    });
}

#[test]
fn browser_runtime_reader_06_literal_empty_entry_requires_observed_zero_count() {
    with_source_controller_lifetime(|lifetime, loans| {
        let activity = lifetime.prepare_activity(loans).unwrap();
        let mut input = io::Cursor::new(b"");
        let mut window = [0; 8];
        let expected = file(0, Sha256::digest(b"").into());
        let mut reader = RuntimeArchiveFile {
            entry: &mut input,
            activity: &activity,
            loans,
            window: &mut window,
            expected: &expected,
            hash: Sha256::new(),
            progress: EntryProgress::Reading { actual: 0 },
        };
        assert!(matches!(
            reader.progress,
            EntryProgress::Reading { actual: 0 }
        ));
        assert!(reader.next_chunk().unwrap().is_none());
        assert!(matches!(
            reader.progress,
            EntryProgress::Complete { actual: 0 }
        ));
    });
}

#[test]
fn browser_runtime_reader_09_actual_short_reads_fill_one_bounded_chunk() {
    struct OneByte<'a> {
        bytes: &'a [u8],
        reads: &'a Cell<usize>,
    }
    impl Read for OneByte<'_> {
        fn read(&mut self, out: &mut [u8]) -> io::Result<usize> {
            self.reads.set(self.reads.get() + 1);
            let Some((first, remaining)) = self.bytes.split_first() else {
                return Ok(0);
            };
            out[0] = *first;
            self.bytes = remaining;
            Ok(1)
        }
    }
    with_source_controller_lifetime(|lifetime, loans| {
        let activity = lifetime.prepare_activity(loans).unwrap();
        let reads = Cell::new(0);
        let mut input = OneByte {
            bytes: b"abcd",
            reads: &reads,
        };
        let mut window = [0; 8];
        let expected = file(4, Sha256::digest(b"abcd").into());
        let mut reader = RuntimeArchiveFile {
            entry: &mut input,
            activity: &activity,
            loans,
            window: &mut window,
            expected: &expected,
            hash: Sha256::new(),
            progress: EntryProgress::Reading { actual: 0 },
        };
        assert_eq!(reader.next_chunk().unwrap().unwrap(), b"abcd");
        assert_eq!(
            reads.get(),
            4,
            "actual four partial reads, one filled chunk"
        );
        assert!(reader.next_chunk().unwrap().is_none());
        assert_eq!(reads.get(), 5, "actual entry EOF is separate");
    });
}

#[test]
fn browser_runtime_reader_10_original_end_is_checked_between_actual_partial_reads() {
    use super::super::super::super::adapter::execution_loans::with_source_controller_end;
    struct ReachesEnd<'a> {
        end: Instant,
        reads: &'a Cell<usize>,
    }
    impl Read for ReachesEnd<'_> {
        fn read(&mut self, out: &mut [u8]) -> io::Result<usize> {
            self.reads.set(self.reads.get() + 1);
            if self.reads.get() == 1 {
                std::thread::sleep(
                    self.end.saturating_duration_since(Instant::now())
                        + std::time::Duration::from_millis(1),
                );
            }
            out[0] = b'a';
            Ok(1)
        }
    }
    with_source_controller_end(std::time::Duration::from_millis(250), |lifetime, loans| {
        let activity = lifetime.prepare_activity(loans).unwrap();
        let reads = Cell::new(0);
        let mut input = ReachesEnd {
            end: lifetime.end(),
            reads: &reads,
        };
        let mut window = [0; 8];
        let expected = file(4, Sha256::digest(b"abcd").into());
        let mut reader = RuntimeArchiveFile {
            entry: &mut input,
            activity: &activity,
            loans,
            window: &mut window,
            expected: &expected,
            hash: Sha256::new(),
            progress: EntryProgress::Reading { actual: 0 },
        };
        assert!(matches!(
            reader.next_chunk(),
            Err(RuntimeArchiveReadFault::Activity(
                BrowserActivityFault::OriginalEnd
            ))
        ));
        assert_eq!(reads.get(), 1, "no second actual read after original end");
        assert!(matches!(
            reader.progress,
            EntryProgress::Refused { actual: 1, .. }
        ));
        assert_eq!(reader.window[0], b'a');
    });
}

#[test]
fn browser_runtime_reader_11_error_after_partial_read_keeps_count_without_emitting_chunk() {
    struct PartialThenError<'a>(&'a Cell<usize>);
    impl Read for PartialThenError<'_> {
        fn read(&mut self, out: &mut [u8]) -> io::Result<usize> {
            self.0.set(self.0.get() + 1);
            if self.0.get() == 1 {
                out[0] = b'a';
                Ok(1)
            } else {
                Err(io::ErrorKind::PermissionDenied.into())
            }
        }
    }
    with_source_controller_lifetime(|lifetime, loans| {
        let activity = lifetime.prepare_activity(loans).unwrap();
        let reads = Cell::new(0);
        let mut input = PartialThenError(&reads);
        let mut window = [0; 8];
        let expected = file(4, Sha256::digest(b"abcd").into());
        let mut reader = RuntimeArchiveFile {
            entry: &mut input,
            activity: &activity,
            loans,
            window: &mut window,
            expected: &expected,
            hash: Sha256::new(),
            progress: EntryProgress::Reading { actual: 0 },
        };
        assert!(matches!(
            reader.next_chunk(),
            Err(RuntimeArchiveReadFault::Archive(
                io::ErrorKind::PermissionDenied
            ))
        ));
        assert!(matches!(
            reader.progress,
            EntryProgress::Refused { actual: 1, .. }
        ));
        assert_eq!(reader.window[0], b'a');
        assert!(reader.next_chunk().is_err());
        assert_eq!(reads.get(), 2, "a failed stream is never retried");
    });
}
