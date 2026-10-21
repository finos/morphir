//! Proposed child of pipeline::browser::archive_download; TEST ONLY, not mounted.
//! The caller loans explicit test grants. No BrowserRun, source/action/model/
//! revision binding, physical download EOF, driver buffer or qualification proof.
//! The real ZIP bytes are the committed product fixture, not a new oracle.
use super::{
    ArchiveByteCollection, ArchiveCollectionFault, ArchiveFormatOutcome, ArchiveStreamEnd,
};
use crate::json::strict::Document;
use crate::workbench::configuration::InstalledObservationLimits;
use crate::workbench::model_originals::workflow::{
    decode::{DecodeError, DecodeLimits, Decoder, OperandResource},
    observation_check::{
        CompareLimits, CompareOwner,
        archive::{self, EntrySlot, ZipStoreFault, ZipStoreMember},
    },
    pipeline::installed::observation::{
        InstalledObservationFault, InstalledObservationOwner, InstalledObservationResource,
    },
};

const PRODUCT: &[u8] = include_bytes!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/src/workbench/model_originals/workflow/observation_check/archive/tests/fixtures/browser-originals.zip"
));
// Private requested plan dimensions, independent of bytes or expected members.
const RAW_CAPACITY: usize = 200_000;
const ENTRY_CAPACITY: usize = 1_100;
const RETAINED: usize = 4_194_304;
const VISITS: usize = 8_388_608;
const SLOTS: usize = 20_000;
const ORIGINAL: &[u8] = b"\xef\xbb\xbf# original\r\nformatVersion: 4\r\n";

fn decoder(slots: usize) -> Decoder {
    Decoder::new(DecodeLimits::new(1_048_576, 1_048_576, 100_000, VISITS, slots).unwrap())
}
fn receiving(retained: usize, visits: usize) -> InstalledObservationOwner {
    // Existing storage-domain parser, not an installed-client selection/grant.
    let raw = format!(
        r#"{{"rpcFrames":"checker-capture","retainedBytes":{retained},"stdoutPrefixBytes":0,"stderrPrefixBytes":0,"snapshotReadBytes":0,"byteVisits":{visits},"records":0}}"#
    );
    let doc = Document::parse_unsigned_counts(raw.as_bytes()).unwrap();
    InstalledObservationOwner::new(&InstalledObservationLimits::from_document(&doc).unwrap())
}
fn comparison() -> CompareOwner {
    CompareOwner::new(CompareLimits::new(2_000_000, 8_000_000, 2_000_000).unwrap())
}
fn append_product(collection: &mut ArchiveByteCollection<'_>) {
    for chunk in PRODUCT.chunks(4_093) {
        collection.append(chunk).unwrap();
    }
}

#[test]
fn zero_and_one_short_raw_permission_refuse_before_collection() {
    for retained in [0, RAW_CAPACITY - 1] {
        let mut decode = decoder(SLOTS);
        let mut storage = receiving(retained, VISITS);
        let mut compare = comparison();
        let fault = match ArchiveByteCollection::prepare(
            &mut decode,
            &mut storage,
            &mut compare,
            RAW_CAPACITY,
            ENTRY_CAPACITY,
        ) {
            Err(fault) => fault,
            Ok(_) => panic!("raw request must be funded before any copy or vacant fill"),
        };
        assert!(matches!(fault, ArchiveCollectionFault::Receiving(
            InstalledObservationFault::Resource {
                kind: InstalledObservationResource::RetainedBytes,
                used: 0, requested, ..
            }
        ) if requested == RAW_CAPACITY as u64));
        assert_eq!(storage.usage().retained_bytes(), 0);
        assert_eq!(storage.usage().byte_visits(), 0);
        let used = (decode.usage(), storage.usage(), compare.usage());
        assert_eq!(
            ArchiveByteCollection::prepare(
                &mut decode,
                &mut storage,
                &mut compare,
                RAW_CAPACITY,
                ENTRY_CAPACITY,
            )
            .err()
            .unwrap(),
            fault
        );
        assert_eq!((decode.usage(), storage.usage(), compare.usage()), used);
    }
}

#[test]
fn zero_and_one_short_slot_permission_refuse_before_raw_or_vacant_fill() {
    // DecodeLimits are nonzero. Spend the single existing slot to leave zero.
    for (limit, already_used) in [(1, 1), (ENTRY_CAPACITY + 1, 0)] {
        let mut decode = decoder(limit);
        if already_used != 0 {
            decode.slots(already_used).unwrap();
        }
        let mut storage = receiving(RETAINED, VISITS);
        let mut compare = comparison();
        let fault = match ArchiveByteCollection::prepare(
            &mut decode,
            &mut storage,
            &mut compare,
            RAW_CAPACITY,
            ENTRY_CAPACITY,
        ) {
            Err(fault) => fault,
            Ok(_) => panic!("two Vec destinations plus each vacant entry need slots"),
        };
        assert_eq!(
            fault,
            ArchiveCollectionFault::Decode(DecodeError::Work(OperandResource::Slots))
        );
        assert_eq!(decode.usage().slots, already_used);
        assert_eq!(storage.usage().retained_bytes(), 0);
        assert_eq!(storage.usage().byte_visits(), 0);
    }
}

#[test]
fn one_short_entry_storage_refuses_before_either_buffer_is_filled() {
    let mut decode = decoder(SLOTS);
    let entry_bytes = ENTRY_CAPACITY * std::mem::size_of::<EntrySlot<'static>>();
    let mut storage = receiving(RAW_CAPACITY + entry_bytes - 1, VISITS);
    let mut compare = comparison();
    let fault = ArchiveByteCollection::prepare(
        &mut decode,
        &mut storage,
        &mut compare,
        RAW_CAPACITY,
        ENTRY_CAPACITY,
    )
    .err()
    .unwrap();
    assert!(matches!(fault, ArchiveCollectionFault::Receiving(
        InstalledObservationFault::Resource {
            kind: InstalledObservationResource::RetainedBytes, used, requested, ..
        }
    ) if used == RAW_CAPACITY as u64 && requested == entry_bytes as u64));
    assert_eq!(storage.usage().byte_visits(), 0);
    assert_eq!(storage.usage().retained_bytes(), RAW_CAPACITY as u64);
}

#[test]
fn actual_product_stream_eof_uses_fixed_storage_and_borrowed_reader() {
    assert_eq!(PRODUCT.len(), 174_443);
    let mut decode = decoder(SLOTS);
    let mut storage = receiving(RETAINED, VISITS);
    let mut compare = comparison();
    let mut collection = ArchiveByteCollection::prepare(
        &mut decode,
        &mut storage,
        &mut compare,
        RAW_CAPACITY,
        ENTRY_CAPACITY,
    )
    .unwrap();
    let reserved = collection.test_storage();
    assert_eq!(reserved.raw_length, 0);
    assert_eq!(reserved.entry_length, ENTRY_CAPACITY);
    assert!(reserved.raw_capacity >= RAW_CAPACITY);
    assert!(reserved.entry_capacity >= ENTRY_CAPACITY);
    append_product(&mut collection);
    let filled = collection.test_storage();
    assert_eq!(filled.raw_length, PRODUCT.len());
    assert_eq!(filled.raw_capacity, reserved.raw_capacity);
    assert_eq!(filled.entry_capacity, reserved.entry_capacity);
    let collected = collection
        .end(ArchiveStreamEnd::Eof)
        .unwrap_or_else(|rejected| panic!("{:?}", rejected.fault()));
    let outcome = collected.with_format(|raw, scratch, owner| {
        assert_eq!(raw, PRODUCT);
        assert_eq!(scratch.len(), ENTRY_CAPACITY);
        assert!(scratch.iter().all(EntrySlot::is_vacant));
        let view = archive::read(raw, scratch, owner)?;
        assert_eq!(view.len(), 1_002);
        let mut entries = view.members();
        match entries.next().unwrap() {
            ZipStoreMember::File { name, bytes } => {
                assert_eq!(name, "model.yaml");
                assert_eq!(bytes, ORIGINAL);
                let span = raw.as_ptr() as usize..raw.as_ptr() as usize + raw.len();
                assert!(span.contains(&(name.as_ptr() as usize)));
                assert!(span.contains(&(bytes.as_ptr() as usize)));
            }
            _ => panic!("the real file remains a file"),
        }
        assert!(matches!(
            entries.next(),
            Some(ZipStoreMember::Directory { name: "notes/" })
        ));
        for i in 0..1_000 {
            match entries.next().unwrap() {
                ZipStoreMember::Directory { name } => {
                    assert_eq!(name, format!("notes/empty-{i:04}/"))
                }
                _ => panic!("explicit real directory"),
            }
        }
        assert!(entries.next().is_none());
        Ok(view.len())
    });
    let raw = match outcome {
        ArchiveFormatOutcome::Parsed { raw, value } => {
            assert_eq!(value, 1_002);
            raw
        }
        ArchiveFormatOutcome::Refused { fault, .. } => panic!("{fault:?}"),
    };
    assert_eq!(raw.as_bytes(), PRODUCT);
    assert_eq!(raw.test_raw_capacity(), reserved.raw_capacity);
    raw.dispose(); // The outer caller still owns the actual bytes until here.
    assert_eq!(decode.usage().slots, ENTRY_CAPACITY + 2);
    let actual_storage =
        reserved.raw_capacity + reserved.entry_capacity * std::mem::size_of::<EntrySlot<'static>>();
    assert_eq!(storage.usage().retained_bytes(), actual_storage as u64);
    assert_eq!(
        storage.usage().byte_visits(),
        (ENTRY_CAPACITY * std::mem::size_of::<EntrySlot<'static>>() + PRODUCT.len()) as u64
    );
    assert!(decode.ready().is_ok() && storage.ready().is_ok() && compare.ready().is_ok());
}

#[test]
fn incomplete_stream_retains_storage_until_explicit_disposal_and_never_formats() {
    let mut decode = decoder(SLOTS);
    let mut storage = receiving(RETAINED, VISITS);
    let mut compare = comparison();
    let mut collection = ArchiveByteCollection::prepare(
        &mut decode,
        &mut storage,
        &mut compare,
        RAW_CAPACITY,
        ENTRY_CAPACITY,
    )
    .unwrap();
    collection.append(&PRODUCT[..37]).unwrap();
    let state = collection.test_storage();
    let used = collection.test_usage();
    let rejected = match collection.end(ArchiveStreamEnd::Incomplete) {
        Err(rejected) => rejected,
        Ok(_) => panic!("absence of explicit EOF cannot yield collected bytes"),
    };
    assert_eq!(rejected.fault(), &ArchiveCollectionFault::Incomplete);
    assert_eq!(rejected.test_storage(), state);
    assert_eq!(rejected.test_usage(), used); // No late parse or new credit.
    rejected.dispose();
    let before = (decode.usage(), storage.usage(), compare.usage());
    assert!(
        ArchiveByteCollection::prepare(
            &mut decode,
            &mut storage,
            &mut compare,
            RAW_CAPACITY,
            ENTRY_CAPACITY,
        )
        .is_err()
    );
    assert_eq!((decode.usage(), storage.usage(), compare.usage()), before);
}

#[test]
fn explicit_eof_truncation_retains_raw_after_scoped_scratch_disposal() {
    let mut decode = decoder(SLOTS);
    let mut storage = receiving(RETAINED, VISITS);
    let mut compare = comparison();
    let mut collection = ArchiveByteCollection::prepare(
        &mut decode,
        &mut storage,
        &mut compare,
        RAW_CAPACITY,
        ENTRY_CAPACITY,
    )
    .unwrap();
    collection.append(&PRODUCT[..PRODUCT.len() - 1]).unwrap();
    let state = collection.test_storage();
    let observed = std::cell::Cell::new(None);
    let collected = collection
        .end(ArchiveStreamEnd::Eof)
        .unwrap_or_else(|rejected| panic!("{:?}", rejected.fault()));
    let outcome = collected.with_format(|raw, scratch, owner| {
        assert_eq!(raw.len(), state.raw_length);
        assert_eq!(scratch.len(), state.entry_length);
        // Both actual backings are alive here. Filled borrowed scratch cannot
        // escape; raw must survive this error with the SAME backing address.
        observed.set(Some(raw.as_ptr() as usize));
        archive::read(raw, scratch, owner).map(|view| view.len())
    });
    let raw = match outcome {
        ArchiveFormatOutcome::Refused { raw, fault } => {
            assert_eq!(fault, ArchiveCollectionFault::Reader(ZipStoreFault::End));
            raw
        }
        ArchiveFormatOutcome::Parsed { .. } => {
            panic!("EOF does not repair a truncated ZIP structure")
        }
    };
    assert_eq!(observed.get(), Some(raw.as_bytes().as_ptr() as usize));
    assert_eq!(raw.as_bytes(), &PRODUCT[..PRODUCT.len() - 1]);
    assert_eq!(raw.test_raw_capacity(), state.raw_capacity);
    // Shortened scratch is gone, but the SAME raw DATA owner remains for the
    // outer failure/report path. It has no format-retry or credit-reset API.
    let failed_usage = raw.test_usage();
    raw.dispose();
    let used = (decode.usage(), storage.usage(), compare.usage());
    assert_eq!(used, failed_usage);
    assert!(
        ArchiveByteCollection::prepare(
            &mut decode,
            &mut storage,
            &mut compare,
            RAW_CAPACITY,
            ENTRY_CAPACITY,
        )
        .is_err()
    );
    assert_eq!((decode.usage(), storage.usage(), compare.usage()), used);
}

#[test]
fn raw_overrun_is_whole_chunk_refusal_and_sticky_before_any_more_copy() {
    let mut decode = decoder(SLOTS);
    let mut storage = receiving(RETAINED, VISITS);
    let mut compare = comparison();
    let mut collection =
        ArchiveByteCollection::prepare(&mut decode, &mut storage, &mut compare, 4, 1).unwrap();
    collection.append(b"abc").unwrap();
    let state = collection.test_storage();
    let used = collection.test_usage();
    let fault = collection.append(b"de").err().unwrap();
    assert_eq!(
        fault,
        ArchiveCollectionFault::Overrun {
            limit: 4,
            retained: 3,
            incoming: 2
        }
    );
    assert_eq!(collection.test_storage(), state);
    assert_eq!(collection.test_usage(), used);
    assert_eq!(collection.append(b"d").err().unwrap(), fault);
    assert_eq!(collection.test_usage(), used);
    let rejected = match collection.end(ArchiveStreamEnd::Eof) {
        Err(rejected) => rejected,
        Ok(_) => panic!("an EOF signal cannot clear the earlier overrun"),
    };
    assert_eq!(rejected.fault(), &fault);
    assert_eq!(rejected.test_storage(), state);
    rejected.dispose();
}

#[test]
fn receiving_copy_work_is_cumulative_and_retry_does_not_issue_credit() {
    let mut decode = decoder(SLOTS);
    let initialization = std::mem::size_of::<EntrySlot<'static>>();
    let mut storage = receiving(RETAINED, initialization + 3);
    let mut compare = comparison();
    let mut collection =
        ArchiveByteCollection::prepare(&mut decode, &mut storage, &mut compare, 16, 1).unwrap();
    collection.append(b"ab").unwrap();
    let state = collection.test_storage();
    let fault = collection.append(b"cd").err().unwrap();
    assert!(matches!(
        fault,
        ArchiveCollectionFault::Receiving(InstalledObservationFault::Resource {
            kind: InstalledObservationResource::ByteVisits,
            ..
        })
    ));
    assert_eq!(collection.test_storage(), state);
    let failed_usage = collection.test_usage();
    assert_eq!(collection.append(b"c").err().unwrap(), fault);
    assert_eq!(collection.test_usage(), failed_usage);
    let rejected = match collection.end(ArchiveStreamEnd::Eof) {
        Err(rejected) => rejected,
        Ok(_) => panic!("resource failure is sticky"),
    };
    assert_eq!(rejected.fault(), &fault);
    rejected.dispose();
    let used = (decode.usage(), storage.usage(), compare.usage());
    assert!(
        ArchiveByteCollection::prepare(&mut decode, &mut storage, &mut compare, 1, 0,).is_err()
    );
    assert_eq!((decode.usage(), storage.usage(), compare.usage()), used);
}

#[test]
fn prior_decoder_fault_wins_over_later_layout_overflow_without_spend() {
    let mut decode = decoder(1);
    assert_eq!(
        decode.slots(2),
        Err(DecodeError::Work(OperandResource::Slots))
    );
    let mut storage = receiving(RETAINED, VISITS);
    let mut compare = comparison();
    let used = (decode.usage(), storage.usage(), compare.usage());
    let fault = ArchiveByteCollection::prepare(
        &mut decode,
        &mut storage,
        &mut compare,
        usize::MAX,
        usize::MAX,
    )
    .err()
    .unwrap();
    assert_eq!(
        fault,
        ArchiveCollectionFault::Decode(DecodeError::Work(OperandResource::Slots))
    );
    assert_eq!((decode.usage(), storage.usage(), compare.usage()), used);
}

#[test]
fn prior_same_comparison_fault_wins_without_any_storage_or_decoder_spend() {
    let mut decode = decoder(SLOTS);
    let mut storage = receiving(RETAINED, VISITS);
    let mut compare = CompareOwner::new(CompareLimits::new(0, 0, 0).unwrap());
    let mut scratch = [];
    assert!(matches!(
        archive::read(&[], &mut scratch, &mut compare),
        Err(ZipStoreFault::Work(_))
    ));
    let prior = compare.ready().err().unwrap();
    let used = (decode.usage(), storage.usage(), compare.usage());
    let fault = ArchiveByteCollection::prepare(
        &mut decode,
        &mut storage,
        &mut compare,
        usize::MAX,
        usize::MAX,
    )
    .err()
    .unwrap();
    assert_eq!(fault, ArchiveCollectionFault::Comparison(prior));
    assert_eq!((decode.usage(), storage.usage(), compare.usage()), used);
}

#[test]
fn dropping_unfinished_collection_keeps_storage_spent_and_latches_abandonment() {
    let mut decode = decoder(SLOTS);
    let mut storage = receiving(RETAINED, VISITS);
    let mut compare = comparison();
    let mut collection =
        ArchiveByteCollection::prepare(&mut decode, &mut storage, &mut compare, 16, 1).unwrap();
    collection.append(b"PK").unwrap();
    let used = collection.test_usage();
    drop(collection);
    assert_eq!(storage.ready(), Err(&InstalledObservationFault::Abandoned));
    assert_eq!((decode.usage(), storage.usage(), compare.usage()), used);
    assert!(
        ArchiveByteCollection::prepare(&mut decode, &mut storage, &mut compare, 16, 1,).is_err()
    );
    assert_eq!((decode.usage(), storage.usage(), compare.usage()), used);
}

#[test]
fn entry_slot_vec_can_shorten_its_lifetime_by_consuming_it() {
    // This type check is the whole point. No unsafe, self-reference or read.
    fn shorten<'bytes>(_: &'bytes [u8], slots: Vec<EntrySlot<'static>>) -> Vec<EntrySlot<'bytes>> {
        slots
    }
    let raw = [0u8];
    let slots = shorten(&raw, Vec::new());
    assert!(slots.is_empty());
}
