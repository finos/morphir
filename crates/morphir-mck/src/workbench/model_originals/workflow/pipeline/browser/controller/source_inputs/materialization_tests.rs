//! The actual selected archive is explicit input. These are source reader
//! controls, not filesystem, browser, installation or launch qualification.
use super::super::super::adapter::execution_loans::{
    with_source_controller_artifact_control, with_source_controller_limits,
};
use super::*;

const ONE_GIB_READER_LIMITS: &[u8] = br#"{"rpcFrames":"checker-capture","retainedBytes":67108864,"stdoutPrefixBytes":4096,"stderrPrefixBytes":4096,"snapshotReadBytes":33554432,"byteVisits":1073741824,"records":0}"#;

fn actual_archive() -> Vec<u8> {
    std::fs::read(
        std::env::var_os("MORPHIR_MCK_BROWSER_PLAYWRIGHT_ARCHIVE")
            .expect("explicit selected package archive required"),
    )
    .unwrap()
}

#[test]
#[ignore = "requires exact selected package archive; reader only, no runtime effects"]
fn browser_runtime_reader_01_actual_complete_chunks_and_descriptor_association() {
    let raw = actual_archive();
    with_source_controller_artifact_control(|lifetime, loans| {
        let package = SelectedRuntimePackage::prepare(&raw, &lifetime, loans).unwrap();
        let dimensions = package.dimensions();
        assert_eq!(dimensions.file_count(), 115);
        assert_eq!(dimensions.total_file_bytes(), FILE_BYTES);
        assert_eq!(dimensions.total_name_bytes(), NAME_BYTES);
        assert_eq!(dimensions.max_path_bytes(), MAX_NAME);
        assert_eq!(dimensions.component_count(), 417);
        assert_eq!(
            package
                .files()
                .map(|file| file.path().split('/').count())
                .sum::<usize>(),
            417
        );
        eprintln!(
            "source-visible validation bound: calls={}, bytes_per_call={}",
            super::materialization::validation_calls_upper().unwrap(),
            SourceControllerActivity::validation_work_upper().unwrap()
        );
        eprintln!(
            "source-visible partial-read bound: calls={}, bytes_per_call={}",
            super::materialization::partial_reads_upper().unwrap(),
            super::materialization::partial_read_work_upper().unwrap()
        );
        let prepared = package
            .prepare_materialization::<io::ErrorKind>(&lifetime, loans)
            .unwrap_or_else(|failure| {
                panic!(
                    "same owners prepay the second real pass: {:?}",
                    failure.fault()
                )
            });
        let mut observed_files = 0;
        let mut observed_bytes = 0;
        let result = prepared.materialize(loans, |descriptor, reader| {
            let mut actual = Sha256::new();
            let mut count = 0;
            while let Some(chunk) = reader.next_chunk().unwrap() {
                assert!(!chunk.is_empty() && chunk.len() <= WINDOW);
                count += chunk.len() as u64;
                actual.update(chunk);
            }
            assert_eq!(count, descriptor.byte_length());
            assert_eq!(<[u8; 32]>::from(actual.finalize()), *descriptor.sha256());
            observed_files += 1;
            observed_bytes += count;
            Ok(())
        });
        let (consumed, source, sink) = result.into_parts();
        assert!(matches!(
            source,
            RuntimeArchiveReadTerminal::Complete {
                files: 115,
                bytes: FILE_BYTES
            }
        ));
        assert!(matches!(
            sink,
            RuntimeSinkTerminal::Returned { entries: 115 }
        ));
        assert_eq!(consumed.files().len(), 115);
        assert!(
            matches!(consumed.tail(),RuntimeArchiveTail::ReadEof {bytes} if bytes<=TAR_BYTES-FILE_BYTES as usize-FILES*512)
        );
        assert_eq!((observed_files, observed_bytes), (115, FILE_BYTES));
    });
}

#[test]
#[ignore = "requires exact selected package archive; preparation refusal only"]
fn browser_runtime_reader_03_prior_owner_refusal_retains_original_package() {
    let raw = actual_archive();
    with_source_controller_limits(ONE_GIB_READER_LIMITS, |lifetime, loans| {
        let package = SelectedRuntimePackage::prepare(&raw, &lifetime, loans).unwrap();
        assert!(
            loans
                .reserve_controlled_host_storage(usize::MAX, 0, 0)
                .is_err()
        );
        let refused = package
            .prepare_materialization::<io::ErrorKind>(&lifetime, loans)
            .err()
            .expect("same owner refuses before new reader allocation");
        assert!(matches!(refused.fault(), RuntimeAssociationFault::Input(_)));
        assert_eq!(refused.files().len(), 115);
        assert_eq!(refused.dimensions().component_count(), 417);
    });
}

#[test]
#[ignore = "requires exact selected package archive; reader only, no runtime effects"]
fn browser_runtime_reader_02_unread_entry_and_actual_sink_error_remain_distinct() {
    let raw = actual_archive();
    with_source_controller_artifact_control(|lifetime, loans| {
        let package = SelectedRuntimePackage::prepare(&raw, &lifetime, loans).unwrap();
        let prepared = package
            .prepare_materialization::<io::ErrorKind>(&lifetime, loans)
            .unwrap_or_else(|_| panic!("second pass funded before effects"));
        let result = prepared.materialize(loans, |_, _| Ok(()));
        let (_, source, sink) = result.into_parts();
        assert!(matches!(
            source,
            RuntimeArchiveReadTerminal::Incomplete {
                files: 0,
                first: Some(RuntimeArchiveReadFault::Inventory),
                ..
            }
        ));
        assert!(matches!(sink, RuntimeSinkTerminal::Returned { entries: 1 }));
    });
    with_source_controller_artifact_control(|lifetime, loans| {
        let package = SelectedRuntimePackage::prepare(&raw, &lifetime, loans).unwrap();
        let prepared = package
            .prepare_materialization::<io::ErrorKind>(&lifetime, loans)
            .unwrap_or_else(|_| panic!("second pass funded before effects"));
        let result = prepared.materialize(loans, |_, reader| {
            let _actual = reader.next_chunk().unwrap();
            Err(io::ErrorKind::PermissionDenied)
        });
        let (_, source, sink) = result.into_parts();
        assert!(matches!(
            source,
            RuntimeArchiveReadTerminal::Incomplete { files: 0, .. }
        ));
        assert!(matches!(
            sink,
            RuntimeSinkTerminal::Raised {
                completed_entries: 0,
                error: io::ErrorKind::PermissionDenied
            }
        ));
    });
}

#[test]
#[ignore = "requires exact selected archive; genuine prepared-then-document-terminal control"]
fn browser_runtime_reader_07_document_fault_or_end_refuses_before_decode_and_sink() {
    use super::super::super::adapter::execution_loans::with_source_controller_artifact_endpoint;
    enum ActualTerminal {
        Fault,
        Ended,
    }
    fn frame(kind: u8, sequence: u64, body: &[u8]) -> Vec<u8> {
        let mut raw = vec![0; 16];
        raw[0] = 1;
        raw[1] = kind;
        raw[4..12].copy_from_slice(&sequence.to_be_bytes());
        raw[12..16].copy_from_slice(&(body.len() as u32).to_be_bytes());
        raw.extend_from_slice(body);
        raw
    }
    let raw = actual_archive();
    for terminal in [ActualTerminal::Fault, ActualTerminal::Ended] {
        with_source_controller_artifact_endpoint(|lifetime, loans, producer| {
            let package = SelectedRuntimePackage::prepare(&raw, &lifetime, loans).unwrap();
            let prepared = package
                .prepare_materialization::<io::ErrorKind>(&lifetime, loans)
                .unwrap_or_else(|_| panic!("healthy current document prepays reader"));
            match terminal {
                ActualTerminal::Fault => {
                    assert!(producer.record_frame(loans, &[], lifetime.end()).is_err());
                }
                ActualTerminal::Ended => {
                    let fact = frame(1,1,br#"{"sequence":1,"kind":"model-closed","actual":{"workspace":"literal","opening":0}}"#);
                    let end = frame(2, 2, br#"{"lastSequence":1,"observer":{"kind":"closed"}}"#);
                    producer.record_frame(loans, &fact, lifetime.end()).unwrap();
                    producer.record_frame(loans, &end, lifetime.end()).unwrap();
                }
            }
            let mut sink_calls = 0;
            let result = prepared.materialize(loans, |_, reader| {
                sink_calls += 1;
                while reader.next_chunk().unwrap().is_some() {}
                Ok(())
            });
            let (_, source, sink) = result.into_parts();
            assert_eq!(
                sink_calls, 0,
                "actual document terminal must refuse before archive decode or sink call"
            );
            assert!(matches!(
                source,
                RuntimeArchiveReadTerminal::Incomplete {
                    files: 0,
                    bytes: 0,
                    first: Some(_)
                }
            ));
            assert!(matches!(sink, RuntimeSinkTerminal::NotAttempted));
        });
    }
}

#[test]
#[ignore = "requires exact selected archive; unchanged one-GiB configured refusal"]
fn browser_runtime_reader_08_one_gib_input_refuses_prepaid_pass_and_retains_original() {
    let raw = actual_archive();
    with_source_controller_limits(ONE_GIB_READER_LIMITS, |lifetime, loans| {
        let selected = SelectedRuntimePackage::prepare(&raw, &lifetime, loans).unwrap();
        assert!(loans.reserve_controlled_host_storage(0, 0, 0).is_ok());
        let refused = selected
            .prepare_materialization::<io::ErrorKind>(&lifetime, loans)
            .err()
            .expect("unchanged configured work input must refuse before prepared reader exists");
        assert!(matches!(refused.fault(), RuntimeAssociationFault::Input(_)));
        assert_eq!(refused.files().len(), 115);
        assert_eq!(refused.dimensions().total_file_bytes(), FILE_BYTES);
        assert!(
            loans.reserve_controlled_host_storage(0, 0, 0).is_err(),
            "actual SAME cumulative owner remains refused; this was not an end-only refusal"
        );
        // There is no prepared reader/port to invoke, and no physical sink was
        // created. The failure still owns the immutable authenticated package.
    });
}
