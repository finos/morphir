//! Private selected runtime artifact preparation. The archive authenticates a
//! package inventory, not an installed tree, browser, Page, or UI image.
//!
//! Selection provenance is the existing playwright-core@1.64.1 entry in
//! finos/morphir-moonbit a42427debd0f5b3d484446e22670d2527469a538:bun.lock
//! (whole source blob SHA256 c54a910631ae483db57d93b937f87069c094fd88c43f9c23c6847ee77bfdad1c).
//! No caller-supplied expected digest, package name, or program is accepted.
use super::super::adapter::execution_loans::{BrowserLoanStamp, SourceControllerLifetime};
use super::super::adapter::{BrowserInputError, BrowserLoans, BrowserSourceFault};
use base64::{Engine as _, engine::general_purpose::STANDARD};
use sha2::{Digest, Sha256, Sha512};
use std::{
    io::{self, Read},
    mem::size_of,
    ops::Range,
    time::Instant,
};

const ARCHIVE_BYTES: usize = 3_172_161;
const TAR_BYTES: usize = 13_746_688;
const FILE_BYTES: u64 = 13_656_167;
const FILES: usize = 115;
const NAME_BYTES: usize = 4_185;
const MAX_NAME: usize = 72;
const WINDOW: usize = 65_536;
const INTEGRITY: &str = include_str!("source_inputs/playwright-core-1.64.1.sri");

#[derive(Debug)]
pub(super) enum RuntimeAssociationFault {
    Input(BrowserInputError),
    Source(BrowserSourceFault),
    End,
    ArchiveLength { expected: usize, actual: usize },
    Integrity,
    ArchiveFormat(io::ErrorKind),
    UnsupportedEntry,
    UnsafePath,
    DuplicatePath,
    Inventory,
    Allocation,
    Overflow,
}
fn active<R>(
    lifetime: &SourceControllerLifetime,
    f: impl FnOnce() -> Result<R, RuntimeAssociationFault>,
) -> Result<R, RuntimeAssociationFault> {
    lifetime
        .while_active(|| {
            if Instant::now() >= lifetime.end() {
                Err(RuntimeAssociationFault::End)
            } else {
                f()
            }
        })
        .map_err(RuntimeAssociationFault::Source)?
}
fn add(a: usize, b: usize) -> Result<usize, RuntimeAssociationFault> {
    a.checked_add(b).ok_or(RuntimeAssociationFault::Overflow)
}
fn mul(a: usize, b: usize) -> Result<usize, RuntimeAssociationFault> {
    a.checked_mul(b).ok_or(RuntimeAssociationFault::Overflow)
}
fn inflater_backing_upper() -> Result<usize, RuntimeAssociationFault> {
    // Locked zlib-rs 0.6.8 inflate::State has 40 non-array fields or fewer.
    // Each is at most 512 bytes (including BitReader, Writer, Window and the
    // x86 CRC accumulator); add a full 63-byte alignment gap per field. The
    // remaining fields are exactly the three Code arrays (Code=u8,u8,u16),
    // lens[320] and work[288]. InflateAllocOffsets then adds a 32768+64 window
    // and two rounding/alignment allowances. This deliberately overpays, and
    // is not a claim that a two-window guess measured an opaque allocator.
    let fixed = add(
        mul(40, 512 + 63)?,
        add(mul(1332 * 2 + 592, 4)?, mul(320 + 288, 2)?)?,
    )?;
    let zlib = add(fixed, 32768 + 64 + 64 * 3)?;
    // miniz_oxide 0.9.1 InflateState: dictionary[32768], three Huffman tables
    // {look_up[i16;1024],tree[i16;576]}, four byte arrays, and <40 non-array
    // scalar/enum fields. A 16-byte field plus gap upper-bounds those scalars.
    let miniz = add(
        32768 + 3 * (1024 + 576) * 2 + 288 + 32 + 19 + 512,
        40 * (16 + 15),
    )?;
    Ok(zlib.max(miniz))
}
fn allocate<T>(
    n: usize,
    lifetime: &SourceControllerLifetime,
    loans: &mut BrowserLoans<'_, '_>,
) -> Result<Vec<T>, RuntimeAssociationFault> {
    let vector = active(lifetime, || {
        let mut vector = Vec::new();
        vector
            .try_reserve_exact(n)
            .map_err(|_| RuntimeAssociationFault::Allocation)?;
        Ok(vector)
    })?;
    let excess = vector
        .capacity()
        .checked_sub(n)
        .ok_or(RuntimeAssociationFault::Overflow)?;
    loans
        .reserve_controlled_host_storage(mul(excess, size_of::<T>())?, 0, 0)
        .map_err(RuntimeAssociationFault::Input)?;
    Ok(vector)
}
struct RuntimeFile {
    name: Range<usize>,
    bytes: u64,
    digest: [u8; 32],
    mode: u32,
}
/// A read-only descriptor of authenticated package DATA, not a filesystem grant.
pub(super) struct RuntimePackageFile<'a> {
    name: &'a str,
    file: &'a RuntimeFile,
}
impl RuntimePackageFile<'_> {
    pub(super) fn path(&self) -> &str {
        self.name
    }
    pub(super) fn byte_length(&self) -> u64 {
        self.file.bytes
    }
    pub(super) fn sha256(&self) -> &[u8; 32] {
        &self.file.digest
    }
    pub(super) fn mode(&self) -> u32 {
        self.file.mode
    }
}
/// Non-clone, SAME-child selected artifact. Only actual installed-file
/// verification may turn its descriptors into a runtime launch association.
pub(super) struct SelectedRuntimePackage {
    archive: Vec<u8>,
    names: Vec<u8>,
    files: Vec<RuntimeFile>,
    stamp: BrowserLoanStamp,
    end: Instant,
}
impl SelectedRuntimePackage {
    pub(super) fn prepare(
        raw: &[u8],
        lifetime: &SourceControllerLifetime,
        loans: &mut BrowserLoans<'_, '_>,
    ) -> Result<Self, RuntimeAssociationFault> {
        // Prior SAME owner/source/child refusal precedes inspection or funding.
        lifetime
            .validate(loans)
            .map_err(RuntimeAssociationFault::Input)?;
        active(lifetime, || Ok(()))?;
        if raw.len() != ARCHIVE_BYTES {
            return Err(RuntimeAssociationFault::ArchiveLength {
                expected: ARCHIVE_BYTES,
                actual: raw.len(),
            });
        }
        loans
            .reserve_controlled_host_storage(
                size_of::<Sha512>() + 3 * 64,
                0,
                add(raw.len(), 3 * 64)?,
            )
            .map_err(RuntimeAssociationFault::Input)?;
        active(lifetime, || {
            let mut expected = [0; 64];
            let text = INTEGRITY.strip_suffix('\n').unwrap_or(INTEGRITY);
            let text = text
                .strip_prefix("sha512-")
                .ok_or(RuntimeAssociationFault::Integrity)?;
            let n = STANDARD
                .decode_slice(text, &mut expected)
                .map_err(|_| RuntimeAssociationFault::Integrity)?;
            let actual: [u8; 64] = Sha512::digest(raw).into();
            if n != expected.len() || actual != expected {
                return Err(RuntimeAssociationFault::Integrity);
            }
            Ok(())
        })?;

        // Fixed artifact dimensions were measured only after the locked SRI
        // matched. They bound work/storage; they cannot authenticate other bytes.
        // flate2-1.1.10 uses one inflater allocation. Both locked Rust
        // implementations are covered by the source-field bound above.
        // C backends are not selected qualification inputs. No RSS claim.
        let inflater = inflater_backing_upper()?;
        // tar-0.4.46 raw regular entries allocate exactly one EntryIo::Data
        // in a Vec. Eight machine words upper-bound that enum's Take + tag.
        let entry_backing = mul(FILES, size_of::<[usize; 8]>())?;
        let reader_headers = add(
            size_of::<Vec<u8>>(),
            add(
                size_of::<tar::Entries<'_, &[u8]>>(),
                mul(2, size_of::<tar::Entry<'_, &[u8]>>())?,
            )?,
        )?;
        let metadata = add(
            reader_headers,
            add(
                mul(FILES, size_of::<Sha256>())?,
                add(
                    size_of::<Self>(),
                    add(
                        size_of::<flate2::bufread::GzDecoder<&[u8]>>(),
                        add(size_of::<tar::Archive<&[u8]>>(), size_of::<Sha512>())?,
                    )?,
                )?,
            )?,
        )?;
        let backing = add(
            add(
                add(ARCHIVE_BYTES, mul(NAME_BYTES, 2)?)?,
                mul(FILES, size_of::<RuntimeFile>())?,
            )?,
            add(add(WINDOW, inflater)?, add(entry_backing, metadata)?)?,
        )?;
        // Raw hash/copy, inflate output/copy/checksum, tar skip/read/file hash,
        // initialized backing and every pair of maximum-length portable names.
        let work = add(
            add(mul(ARCHIVE_BYTES, 3)?, mul(TAR_BYTES, 6)?)?,
            add(backing, mul(mul(FILES, FILES)?, mul(MAX_NAME, 2)?)?)?,
        )?;
        loans
            .reserve_controlled_host_storage(backing, add(FILES, add(FILES, 7)?)?, work)
            .map_err(RuntimeAssociationFault::Input)?;
        let stamp = loans
            .prepare_relation_stamp()
            .map_err(RuntimeAssociationFault::Input)?;
        let mut archive = allocate::<u8>(ARCHIVE_BYTES, lifetime, loans)?;
        let mut names = allocate::<u8>(NAME_BYTES, lifetime, loans)?;
        let mut files = allocate::<RuntimeFile>(FILES, lifetime, loans)?;
        active(lifetime, || {
            archive.extend_from_slice(raw);
            Ok(())
        })?;
        let mut window = allocate::<u8>(WINDOW, lifetime, loans)?;
        active(lifetime, || {
            window.resize(WINDOW, 0);
            Ok(())
        })?;
        let decoder = active(lifetime, || Ok(flate2::bufread::GzDecoder::new(raw)))?;
        let mut tar = tar::Archive::new(decoder.take((TAR_BYTES as u64) + 1));
        let mut total = 0u64;
        {
            let mut entries = active(lifetime, || {
                tar.entries()
                    .map(|entries| entries.raw(true))
                    .map_err(|error| RuntimeAssociationFault::ArchiveFormat(error.kind()))
            })?;
            loop {
                // Advancing tar performs reads/decompression; it must remain
                // under the SAME child/end gate just like an explicit read.
                let entry = active(lifetime, || {
                    entries
                        .next()
                        .transpose()
                        .map_err(|error| RuntimeAssociationFault::ArchiveFormat(error.kind()))
                })?;
                let Some(mut entry) = entry else {
                    break;
                };
                active(lifetime, || {
                    if files.len() == FILES {
                        return Err(RuntimeAssociationFault::Inventory);
                    }
                    if entry.header().entry_type() != tar::EntryType::Regular {
                        return Err(RuntimeAssociationFault::UnsupportedEntry);
                    }
                    let path = entry.path_bytes();
                    let name = package_relative(&path)?;
                    if files.iter().any(|file: &RuntimeFile| {
                        names[file.name.clone()].eq_ignore_ascii_case(name.as_bytes())
                    }) {
                        return Err(RuntimeAssociationFault::DuplicatePath);
                    }
                    if add(names.len(), name.len())? > NAME_BYTES {
                        return Err(RuntimeAssociationFault::Inventory);
                    }
                    let bytes = entry
                        .header()
                        .size()
                        .map_err(|error| RuntimeAssociationFault::ArchiveFormat(error.kind()))?;
                    total = total
                        .checked_add(bytes)
                        .ok_or(RuntimeAssociationFault::Overflow)?;
                    if total > FILE_BYTES {
                        return Err(RuntimeAssociationFault::Inventory);
                    }
                    let mode = entry
                        .header()
                        .mode()
                        .map_err(|error| RuntimeAssociationFault::ArchiveFormat(error.kind()))?;
                    if !matches!(mode, 0o644 | 0o755) {
                        return Err(RuntimeAssociationFault::UnsupportedEntry);
                    }
                    let start = names.len();
                    names.extend_from_slice(name.as_bytes());
                    files.push(RuntimeFile {
                        name: start..names.len(),
                        bytes,
                        digest: [0; 32],
                        mode,
                    });
                    Ok(())
                })?;
                let mut hash = Sha256::new();
                let mut read_bytes = 0u64;
                loop {
                    let count = active(lifetime, || {
                        entry
                            .read(&mut window)
                            .map_err(|error| RuntimeAssociationFault::ArchiveFormat(error.kind()))
                    })?;
                    if count == 0 {
                        break;
                    }
                    active(lifetime, || {
                        hash.update(&window[..count]);
                        Ok(())
                    })?;
                    read_bytes = read_bytes
                        .checked_add(count as u64)
                        .ok_or(RuntimeAssociationFault::Overflow)?;
                }
                active(lifetime, || {
                    let file = files.last_mut().ok_or(RuntimeAssociationFault::Inventory)?;
                    if read_bytes != file.bytes {
                        return Err(RuntimeAssociationFault::Inventory);
                    }
                    file.digest = hash.finalize().into();
                    Ok(())
                })?;
            }
        }
        // Drain real trailing tar blocks and actually observe gzip EOF. The
        // authenticated single member must expand to exactly the selected size.
        let mut remaining = tar.into_inner();
        loop {
            let count = active(lifetime, || {
                remaining
                    .read(&mut window)
                    .map_err(|error| RuntimeAssociationFault::ArchiveFormat(error.kind()))
            })?;
            if count == 0 {
                break;
            }
        }
        active(lifetime, || {
            if remaining.limit() != 1
                || files.len() != FILES
                || total != FILE_BYTES
                || names.len() != NAME_BYTES
            {
                return Err(RuntimeAssociationFault::Inventory);
            }
            Ok(Self {
                archive,
                names,
                files,
                stamp,
                end: lifetime.end(),
            })
        })
    }
    pub(super) fn validate(
        &self,
        lifetime: &SourceControllerLifetime,
        loans: &BrowserLoans<'_, '_>,
    ) -> Result<(), RuntimeAssociationFault> {
        lifetime
            .validate(loans)
            .map_err(RuntimeAssociationFault::Input)?;
        loans
            .validate_relation_stamp(&self.stamp)
            .map_err(RuntimeAssociationFault::Input)?;
        active(lifetime, || {
            if self.end == lifetime.end() {
                Ok(())
            } else {
                Err(RuntimeAssociationFault::Inventory)
            }
        })
    }
    pub(super) fn files(&self) -> impl ExactSizeIterator<Item = RuntimePackageFile<'_>> {
        self.files.iter().map(|file| RuntimePackageFile {
            // package_relative accepts ASCII; the retained arena is immutable.
            name: std::str::from_utf8(&self.names[file.name.clone()])
                .expect("validated package ASCII"),
            file,
        })
    }
    pub(super) fn archive(&self) -> &[u8] {
        &self.archive
    }
}
fn package_relative(raw: &[u8]) -> Result<&str, RuntimeAssociationFault> {
    let relative = raw
        .strip_prefix(b"package/")
        .ok_or(RuntimeAssociationFault::UnsafePath)?;
    if relative.len() > MAX_NAME || !relative.is_ascii() {
        return Err(RuntimeAssociationFault::UnsafePath);
    }
    let relative =
        std::str::from_utf8(relative).map_err(|_| RuntimeAssociationFault::UnsafePath)?;
    // Reuse the maintained portable-name policy. Bound its per-segment upper
    // case/error temporary storage in the already prepaid name/work backing.
    crate::kit::manifest::check_snapshot_path(relative)
        .map_err(|_| RuntimeAssociationFault::UnsafePath)?;
    Ok(relative)
}
#[cfg(test)]
mod tests;
