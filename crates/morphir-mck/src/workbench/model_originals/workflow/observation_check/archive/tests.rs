//! Prospective child of observation_check::archive, not a campaign case or authority.
//! Independently assembled ZIP64 STORE fixtures. No production writer is invoked.
//! All fixture Vec allocation is test setup; the proposed reader only borrows bytes
//! and this fixed stack scratch. No process, filesystem extraction or Blob is used.
mod product;

use super::super::{CompareLimits, CompareOwner, CompareResource, ObservationError};
use super::{EntrySlot, ZipStoreFault, ZipStoreMember, read};

const FLAGS: u16 = 0x0808; // UTF8 names and signed data descriptor.
const CHECK: &[u8] = b"123456789";
const CHECK_CRC32: u32 = 0xcbf4_3926; // Independent CRC-32/ISO-HDLC check vector.

#[derive(Clone, Copy)]
struct Row<'a> {
    name: &'a str,
    data: &'a [u8],
    crc: u32,
}
#[derive(Clone, Copy)]
struct Location {
    local: usize,
    name: usize,
    extra: usize,
    data: usize,
    descriptor: usize,
}
struct Fixture {
    bytes: Vec<u8>,
    local: Vec<Location>,
    central: Vec<usize>,
    zip64_end: usize,
    locator: usize,
    legacy_end: usize,
}
fn u16le(out: &mut Vec<u8>, value: u16) {
    out.extend_from_slice(&value.to_le_bytes());
}
fn u32le(out: &mut Vec<u8>, value: u32) {
    out.extend_from_slice(&value.to_le_bytes());
}
fn u64le(out: &mut Vec<u8>, value: u64) {
    out.extend_from_slice(&value.to_le_bytes());
}
fn put16(bytes: &mut [u8], at: usize, value: u16) {
    bytes[at..at + 2].copy_from_slice(&value.to_le_bytes());
}
fn put32(bytes: &mut [u8], at: usize, value: u32) {
    bytes[at..at + 4].copy_from_slice(&value.to_le_bytes());
}
fn put64(bytes: &mut [u8], at: usize, value: u64) {
    bytes[at..at + 8].copy_from_slice(&value.to_le_bytes());
}
fn size_extra(out: &mut Vec<u8>, size: usize) {
    u16le(out, 1);
    u16le(out, 16);
    u64le(out, size as u64);
    u64le(out, size as u64);
}
/// A tiny reference fixture encoder, not the reader implementation. Every
/// numeric field is written explicitly. CRC words are independent literal
/// inputs, never copied from a production archive or recomputed by this builder.
fn fixture(rows: &[Row<'_>], directory_order: &[usize]) -> Fixture {
    let mut bytes = Vec::new();
    let mut local = Vec::new();
    for row in rows {
        let start = bytes.len();
        u32le(&mut bytes, 0x0403_4b50);
        u16le(&mut bytes, 45);
        u16le(&mut bytes, FLAGS);
        u16le(&mut bytes, 0); // STORE
        u16le(&mut bytes, 0);
        u16le(&mut bytes, 0x21); // 1980-01-01
        u32le(&mut bytes, 0); // Local CRC deferred to signed descriptor.
        u32le(&mut bytes, u32::MAX);
        u32le(&mut bytes, u32::MAX);
        u16le(&mut bytes, u16::try_from(row.name.len()).unwrap());
        u16le(&mut bytes, 20);
        let name = bytes.len();
        bytes.extend_from_slice(row.name.as_bytes());
        let extra = bytes.len();
        size_extra(&mut bytes, row.data.len());
        let data = bytes.len();
        bytes.extend_from_slice(row.data);
        let descriptor = bytes.len();
        u32le(&mut bytes, 0x0807_4b50);
        u32le(&mut bytes, row.crc);
        u64le(&mut bytes, row.data.len() as u64);
        u64le(&mut bytes, row.data.len() as u64);
        local.push(Location {
            local: start,
            name,
            extra,
            data,
            descriptor,
        });
    }
    let central_start = bytes.len();
    let mut central = Vec::new();
    for &index in directory_order {
        let row = &rows[index];
        central.push(bytes.len());
        u32le(&mut bytes, 0x0201_4b50);
        u16le(&mut bytes, 45); // DOS made-by; no Unix special-file attributes.
        u16le(&mut bytes, 45);
        u16le(&mut bytes, FLAGS);
        u16le(&mut bytes, 0);
        u16le(&mut bytes, 0);
        u16le(&mut bytes, 0x21);
        u32le(&mut bytes, row.crc);
        u32le(&mut bytes, u32::MAX);
        u32le(&mut bytes, u32::MAX);
        u16le(&mut bytes, u16::try_from(row.name.len()).unwrap());
        u16le(&mut bytes, 20);
        u16le(&mut bytes, 0); // No member comment.
        u16le(&mut bytes, 0); // Disk zero.
        u16le(&mut bytes, 0);
        u32le(&mut bytes, if row.name.ends_with('/') { 0x10 } else { 0 });
        u32le(&mut bytes, u32::try_from(local[index].local).unwrap());
        bytes.extend_from_slice(row.name.as_bytes());
        size_extra(&mut bytes, row.data.len());
    }
    let zip64_end = bytes.len();
    u32le(&mut bytes, 0x0606_4b50);
    u64le(&mut bytes, 44);
    u16le(&mut bytes, 45);
    u16le(&mut bytes, 45);
    u32le(&mut bytes, 0);
    u32le(&mut bytes, 0);
    u64le(&mut bytes, directory_order.len() as u64);
    u64le(&mut bytes, directory_order.len() as u64);
    u64le(&mut bytes, (zip64_end - central_start) as u64);
    u64le(&mut bytes, central_start as u64);
    let locator = bytes.len();
    u32le(&mut bytes, 0x0706_4b50);
    u32le(&mut bytes, 0);
    u64le(&mut bytes, zip64_end as u64);
    u32le(&mut bytes, 1);
    let legacy_end = bytes.len();
    u32le(&mut bytes, 0x0605_4b50);
    // zip.js2.24 supportZip64SplitFile default emits legacy sentinels even
    // though authoritative ZIP64 disk fields/locator still specify one disk.
    for _ in 0..4 {
        u16le(&mut bytes, u16::MAX);
    }
    u32le(&mut bytes, u32::MAX);
    u32le(&mut bytes, u32::MAX);
    u16le(&mut bytes, 0);
    Fixture {
        bytes,
        local,
        central,
        zip64_end,
        locator,
        legacy_end,
    }
}
fn sample() -> Fixture {
    fixture(
        &[
            Row {
                name: "source/opaque.bin",
                data: CHECK,
                crc: CHECK_CRC32,
            },
            Row {
                name: "empty.bin",
                data: b"",
                crc: 0,
            },
            Row {
                name: "empty/",
                data: b"",
                crc: 0,
            },
        ],
        &[2, 0, 1],
    )
}
fn owner() -> CompareOwner {
    // Explicit unit-test limits, not a new production policy or default.
    CompareOwner::new(CompareLimits::new(100_000, 1_000_000, 100_000).unwrap())
}
fn failure(bytes: &[u8]) -> ZipStoreFault {
    let mut slots = std::array::from_fn::<_, 3, _>(|_| EntrySlot::vacant());
    let mut compare = owner();
    match read(bytes, &mut slots, &mut compare) {
        Ok(_) => panic!("malformed control must not yield a ready borrowed archive"),
        Err(fault) => fault,
    }
}
#[test]
fn zip64_store_members_are_exact_borrowed_data_not_authority() {
    let input = sample();
    let mut slots = std::array::from_fn::<_, 3, _>(|_| EntrySlot::vacant());
    let mut compare = owner();
    let archive = read(&input.bytes, &mut slots, &mut compare).expect("valid independent ZIP64");
    assert_eq!(archive.len(), 3);
    let mut members = archive.members();
    match members.next().unwrap() {
        ZipStoreMember::File { name, bytes } => {
            assert_eq!(name, "empty.bin");
            assert!(bytes.is_empty());
        }
        _ => panic!("empty original remains a file"),
    }
    match members.next().unwrap() {
        ZipStoreMember::Directory { name } => assert_eq!(name, "empty/"),
        _ => panic!("explicit empty directory remains a directory"),
    }
    match members.next().unwrap() {
        ZipStoreMember::File { name, bytes } => {
            assert_eq!(name, "source/opaque.bin");
            assert_eq!(bytes, CHECK);
            assert_eq!(bytes.as_ptr(), input.bytes[input.local[0].data..].as_ptr());
            let base = input.bytes.as_ptr() as usize;
            assert!((base..base + input.bytes.len()).contains(&(name.as_ptr() as usize)));
        }
        _ => panic!("nonempty original remains a file"),
    }
    assert!(members.next().is_none()); // No fabricated implicit source/ member.
}
#[test]
fn valid_utf8_name_and_zero_member_zip64_have_defined_borrowed_shapes() {
    let input = fixture(
        &[Row {
            name: "\u{03bb}.bin",
            data: CHECK,
            crc: CHECK_CRC32,
        }],
        &[0],
    );
    let mut slots = [EntrySlot::vacant()];
    let archive = read(&input.bytes, &mut slots, &mut owner()).expect("UTF8 flag/name");
    assert!(matches!(
        archive.members().next(),
        Some(ZipStoreMember::File {
            name: "\u{03bb}.bin",
            ..
        })
    ));
    let empty = fixture(&[], &[]);
    let mut no_slots = [];
    let archive =
        read(&empty.bytes, &mut no_slots, &mut owner()).expect("format-only empty archive");
    assert_eq!(archive.len(), 0);
    assert!(archive.members().next().is_none());
    // This does not claim an empty connected OriginalInventory is valid.
}
#[test]
fn every_truncated_prefix_and_trailing_byte_refuses_without_ready_output() {
    let input = sample();
    for end in 0..input.bytes.len() {
        let _specific_fault = failure(&input.bytes[..end]);
    }
    let mut trailing = input.bytes.clone();
    trailing.push(0);
    assert_eq!(failure(&trailing), ZipStoreFault::End);
}
#[test]
fn zip64_end_counts_offsets_disks_and_sentinels_are_cross_checked() {
    for mutation in 0..6 {
        let mut input = sample();
        match mutation {
            0 => put64(&mut input.bytes, input.locator + 8, u64::MAX),
            1 => put64(&mut input.bytes, input.zip64_end + 40, u64::MAX),
            2 => put64(&mut input.bytes, input.zip64_end + 32, 2),
            3 => put32(&mut input.bytes, input.locator + 16, 2),
            4 => put64(&mut input.bytes, input.zip64_end + 4, 43),
            5 => put16(&mut input.bytes, input.legacy_end + 10, 2),
            _ => unreachable!(),
        }
        assert_eq!(failure(&input.bytes), ZipStoreFault::End);
    }
}
#[test]
fn local_and_central_names_sizes_and_method_must_describe_the_same_member() {
    for mutation in 0..4 {
        let mut input = sample();
        let local = input.local[0];
        match mutation {
            0 => input.bytes[local.name] = b'X',
            1 => put64(&mut input.bytes, local.extra + 4, 8),
            2 => put16(&mut input.bytes, local.local + 8, 8),
            3 => put16(&mut input.bytes, local.local + 6, 0x0800),
            _ => unreachable!(),
        }
        assert_eq!(failure(&input.bytes), ZipStoreFault::Header);
    }
}
#[test]
fn signed_descriptor_signature_crc_and_both_sizes_are_required() {
    for mutation in 0..4 {
        let mut input = sample();
        let descriptor = input.local[0].descriptor;
        match mutation {
            0 => put32(&mut input.bytes, descriptor, 0),
            1 => put32(&mut input.bytes, descriptor + 4, 0),
            2 => put64(&mut input.bytes, descriptor + 8, 8),
            3 => put64(&mut input.bytes, descriptor + 16, 8),
            _ => unreachable!(),
        }
        assert_eq!(failure(&input.bytes), ZipStoreFault::Descriptor);
    }
}
#[test]
fn store_payload_crc_is_recomputed_instead_of_trusting_matching_claims() {
    let mut input = sample();
    input.bytes[input.local[0].data + 4] ^= 1;
    assert_eq!(failure(&input.bytes), ZipStoreFault::Crc);
    let mut coherent_wrong_crc = sample();
    put32(
        &mut coherent_wrong_crc.bytes,
        coherent_wrong_crc.local[0].descriptor + 4,
        1,
    );
    put32(
        &mut coherent_wrong_crc.bytes,
        coherent_wrong_crc.central[1] + 16,
        1,
    );
    assert_eq!(failure(&coherent_wrong_crc.bytes), ZipStoreFault::Crc);
}
#[test]
fn duplicate_raw_names_refuse_and_unclaimed_local_data_cannot_be_hidden() {
    let duplicated = fixture(
        &[
            Row {
                name: "same",
                data: b"",
                crc: 0,
            },
            Row {
                name: "same",
                data: b"",
                crc: 0,
            },
        ],
        &[0, 1],
    );
    assert_eq!(failure(&duplicated.bytes), ZipStoreFault::Duplicate);
    let unclaimed = fixture(
        &[
            Row {
                name: "kept",
                data: b"",
                crc: 0,
            },
            Row {
                name: "hidden",
                data: b"",
                crc: 0,
            },
        ],
        &[0],
    );
    assert_eq!(failure(&unclaimed.bytes), ZipStoreFault::Offsets);
    let mut outside = sample();
    put32(&mut outside.bytes, outside.central[0] + 42, u32::MAX - 1);
    assert_eq!(failure(&outside.bytes), ZipStoreFault::Offsets);
}
#[test]
fn unsupported_compression_encryption_and_extra_fields_are_not_credited_as_store() {
    for mutation in 0..4 {
        let mut input = fixture(
            &[Row {
                name: "file",
                data: CHECK,
                crc: CHECK_CRC32,
            }],
            &[0],
        );
        let local = input.local[0];
        let central = input.central[0];
        match mutation {
            0 => {
                put16(&mut input.bytes, local.local + 8, 8);
                put16(&mut input.bytes, central + 10, 8);
            }
            1 => {
                put16(&mut input.bytes, local.local + 6, FLAGS | 1);
                put16(&mut input.bytes, central + 8, FLAGS | 1);
            }
            2 => {
                put16(&mut input.bytes, local.extra, 0x5455);
                put16(&mut input.bytes, central + 46 + 4, 0x5455);
            }
            3 => {
                put16(&mut input.bytes, central + 4, (3 << 8) | 45);
                put32(&mut input.bytes, central + 38, 0o120777 << 16);
            }
            _ => unreachable!(),
        }
        assert_eq!(failure(&input.bytes), ZipStoreFault::Unsupported);
    }
}
#[test]
fn invalid_utf8_and_nonempty_directory_are_refused_as_headers() {
    let mut input = fixture(
        &[Row {
            name: "file",
            data: CHECK,
            crc: CHECK_CRC32,
        }],
        &[0],
    );
    input.bytes[input.local[0].name] = 0xff;
    input.bytes[input.central[0] + 46] = 0xff;
    assert_eq!(failure(&input.bytes), ZipStoreFault::Header);
    let directory = fixture(
        &[Row {
            name: "bad/",
            data: CHECK,
            crc: CHECK_CRC32,
        }],
        &[0],
    );
    assert_eq!(failure(&directory.bytes), ZipStoreFault::Header);
}
#[test]
fn fixed_scratch_shortage_refuses_before_filling_a_member_slot() {
    let input = sample();
    let mut slots = [EntrySlot::vacant(), EntrySlot::vacant()];
    let mut compare = owner();
    assert!(matches!(
        read(&input.bytes, &mut slots, &mut compare),
        Err(ZipStoreFault::Scratch)
    ));
    assert!(slots.iter().all(EntrySlot::is_vacant));
}
#[test]
fn same_comparison_owner_refusals_are_sticky_without_retry_spend() {
    let input = sample();
    for resource in [
        CompareResource::StructuralVisits,
        CompareResource::ComparisonBytes,
        CompareResource::Checks,
    ] {
        let (visits, bytes, checks) = match resource {
            CompareResource::StructuralVisits => (0, 1_000_000, 100_000),
            CompareResource::ComparisonBytes => (100_000, 0, 100_000),
            CompareResource::Checks => (100_000, 1_000_000, 0),
        };
        let mut compare = CompareOwner::new(CompareLimits::new(visits, bytes, checks).unwrap());
        let mut slots = std::array::from_fn::<_, 3, _>(|_| EntrySlot::vacant());
        let fault = match read(&input.bytes, &mut slots, &mut compare) {
            Ok(_) => panic!("zero selected work resource must refuse"),
            Err(fault) => fault,
        };
        assert_eq!(
            fault,
            ZipStoreFault::Work(ObservationError::Resource(resource))
        );
        let spent = compare.usage();
        assert_eq!(compare.ready(), Err(ObservationError::Resource(resource)));
        let repeated = match read(&input.bytes, &mut slots, &mut compare) {
            Ok(_) => panic!("same faulted owner cannot resume parsing"),
            Err(fault) => fault,
        };
        assert_eq!(repeated, fault);
        assert_eq!(compare.usage(), spent);
    }
}
