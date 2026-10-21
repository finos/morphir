//! Exact downloaded product output, retained as a format-only test input.
//! This test never supplies source, action, revision or download authority.
use super::{CompareLimits, CompareOwner, EntrySlot, ZipStoreFault, ZipStoreMember, read};
use sha2::{Digest, Sha256};

const PRODUCT: &[u8] = include_bytes!("fixtures/browser-originals.zip");
const ORIGINAL: &[u8] = b"\xef\xbb\xbf# original\r\nformatVersion: 4\r\n";
const MEMBERS: usize = 1002;

fn owner() -> CompareOwner {
    // Explicit test-only grants for the captured 1002-member input. These do
    // not change a production policy or pay for a future caller's scratch.
    CompareOwner::new(CompareLimits::new(2_000_000, 8_000_000, 2_000_000).unwrap())
}

fn failure(bytes: &[u8]) -> ZipStoreFault {
    let mut scratch = std::array::from_fn::<_, MEMBERS, _>(|_| EntrySlot::vacant());
    match read(bytes, &mut scratch, &mut owner()) {
        Ok(_) => panic!("mutated product archive must not yield ready borrowed DATA"),
        Err(fault) => fault,
    }
}

#[test]
fn actual_browser_zip_is_exact_borrowed_membership_and_original_bytes() {
    assert_eq!(PRODUCT.len(), 174443);
    assert_eq!(
        <[u8; 32]>::from(Sha256::digest(PRODUCT)),
        [
            0xbd, 0xd4, 0xa0, 0xfe, 0x79, 0x39, 0x27, 0x91, 0x2f, 0xd3, 0x16, 0x61, 0xff, 0x31,
            0x0e, 0xfa, 0x6e, 0xee, 0x2c, 0xb2, 0x99, 0x91, 0xfe, 0x02, 0x9c, 0xce, 0x00, 0x27,
            0xb9, 0x57, 0x86, 0xa5,
        ]
    );
    let mut scratch = std::array::from_fn::<_, MEMBERS, _>(|_| EntrySlot::vacant());
    let mut compare = owner();
    let archive = read(PRODUCT, &mut scratch, &mut compare).expect("captured product ZIP64 STORE");
    assert_eq!(archive.len(), MEMBERS);
    let mut members = archive.members();
    match members.next().unwrap() {
        ZipStoreMember::File { name, bytes } => {
            assert_eq!(name, "model.yaml");
            assert_eq!(bytes, ORIGINAL); // Exact BOM and CRLF, no normalization.
            let base = PRODUCT.as_ptr() as usize;
            assert!((base..base + PRODUCT.len()).contains(&(name.as_ptr() as usize)));
            assert!((base..base + PRODUCT.len()).contains(&(bytes.as_ptr() as usize)));
        }
        _ => panic!("model.yaml remains a file"),
    }
    match members.next().unwrap() {
        ZipStoreMember::Directory { name } => assert_eq!(name, "notes/"),
        _ => panic!("explicit notes remains a directory"),
    }
    for index in 0..1000 {
        match members.next().unwrap() {
            ZipStoreMember::Directory { name } => {
                assert_eq!(name, format!("notes/empty-{index:04}/"));
                let base = PRODUCT.as_ptr() as usize;
                assert!((base..base + PRODUCT.len()).contains(&(name.as_ptr() as usize)));
            }
            _ => panic!("every captured empty directory retains its kind"),
        }
    }
    assert!(members.next().is_none()); // No missing or fabricated member.
}

#[test]
fn actual_browser_payload_mutation_is_crc_refusal() {
    let positions: Vec<_> = PRODUCT
        .windows(ORIGINAL.len())
        .enumerate()
        .filter_map(|(at, bytes)| (bytes == ORIGINAL).then_some(at))
        .collect();
    assert_eq!(positions.len(), 1); // Independent literal bytes select the payload.
    let mut changed = PRODUCT.to_vec();
    changed[positions[0] + 3] ^= 1;
    assert_eq!(failure(&changed), ZipStoreFault::Crc);
}

#[test]
fn actual_browser_local_central_name_disagreement_is_refused() {
    let positions: Vec<_> = PRODUCT
        .windows(b"model.yaml".len())
        .enumerate()
        .filter_map(|(at, bytes)| (bytes == b"model.yaml").then_some(at))
        .collect();
    assert_eq!(positions.len(), 2); // Local and central literal spellings.
    let mut changed = PRODUCT.to_vec();
    changed[positions[1]] = b'M';
    assert_eq!(failure(&changed), ZipStoreFault::Header);
}

#[test]
fn actual_browser_end_count_and_trailing_bytes_are_refused() {
    let locator = PRODUCT.len() - 22 - 20;
    assert_eq!(
        &PRODUCT[locator..locator + 4],
        &0x0706_4b50u32.to_le_bytes()
    );
    let end = usize::try_from(u64::from_le_bytes(
        PRODUCT[locator + 8..locator + 16].try_into().unwrap(),
    ))
    .unwrap();
    let mut changed = PRODUCT.to_vec();
    changed[end + 32] ^= 1; // Only total count, leaving per-disk count unchanged.
    assert_eq!(failure(&changed), ZipStoreFault::End);
    let mut trailing = PRODUCT.to_vec();
    trailing.push(0);
    assert_eq!(failure(&trailing), ZipStoreFault::End);
}
