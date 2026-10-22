//! Immutable acquired application DATA, paid once per preparation. This is not
//! a BrowserRun, a document ingress or evidence of browser/body completion.
#[cfg(test)]
#[path = "assets/tests.rs"]
mod tests;
use super::*;
use cap_fs_ext::{DirExt as _, FollowSymlinks, OpenOptionsFollowExt as _, OpenOptionsSyncExt as _};
use cap_std::fs::{Dir, OpenOptions};
use morphir_mck::workbench::BrowserApplicationSource;
use sha2::{Digest as _, Sha256};
use std::{
    io::Read as _,
    ops::Range,
    path::{Component, Path},
    sync::atomic::AtomicUsize,
};

pub(super) struct ApplicationSource<'a> {
    pub(super) commit: &'a str,
    pub(super) tree: &'a str,
    pub(super) build_manifest_sha256: [u8; 32],
}
pub(super) struct ApplicationFile<'a> {
    pub(super) path: &'a str,
    pub(super) bytes: usize,
    pub(super) sha256: [u8; 32],
}
pub(super) struct ApplicationManifest<'a> {
    pub(super) source: ApplicationSource<'a>,
    pub(super) files: &'a [ApplicationFile<'a>],
}
pub(super) struct AcquiredObservedWorkbench<'a> {
    pub(super) root: &'a Dir,
    pub(super) manifest: ApplicationManifest<'a>,
}
#[derive(Debug)]
pub(super) enum ObservedAssetsFault {
    Funding(BrowserInputError),
    Source,
    End,
    Shape,
    FileKind,
    Size,
    SizeOverflow,
    Hash { file: usize, actual: [u8; 32] },
    Allocation(std::collections::TryReserveError),
    Io(std::io::Error),
    Host(ControlledHostSetupFault),
}
impl From<BrowserInputError> for ObservedAssetsFault {
    fn from(cause: BrowserInputError) -> Self {
        Self::Funding(cause)
    }
}
#[derive(Clone, Copy)]
enum AssetMime {
    JavaScript,
    Json,
    Css,
    Svg,
    Html,
    Text,
}
// All suffix/equality operands in AssetMime::of, including short-circuited ones.
const ORDINARY_TEMPLATE: &str = "index.html";
const OBSERVED_TEMPLATE: &str = "observed-index.html";
const OBSERVED_ENTRY_MODULE: &str = "observed-document-entry.js";
const OBSERVED_PREFIX: &str = "/observed/";
const OBSERVED_QUERY: &str = "mode=connected-originals";
// Two MIME classifications and one role classification may compare this name.
// Prepay both operands of every newly introduced equality before the scans.
const OBSERVED_NAME_PROBES: usize = 3;
const OBSERVED_NAME_PROBE_BYTES: usize = 2 * OBSERVED_TEMPLATE.len();
const MIME_PROBE_BYTES_PER_PASS: usize =
    3 + 5 + 4 + 4 + 4 + ORDINARY_TEMPLATE.len() + OBSERVED_NAME_PROBE_BYTES + 4;
const ROLE_PROBE_BYTES: usize = OBSERVED_NAME_PROBE_BYTES;
// Fixed route guards: prefix, both raw-template names, and the sole entry
// query. Each operand is charged twice; runtime length checks precede scans.
const ROUTE_GUARD_BYTES: usize = 2
    * (OBSERVED_PREFIX.len()
        + ORDINARY_TEMPLATE.len()
        + OBSERVED_TEMPLATE.len()
        + OBSERVED_QUERY.len());
const ROUTE_GUARD_VISITS: usize = 8;
// Shape bytes, slash splitting, Path::components traversal, and prefix work.
const PATH_SCAN_PASSES: usize = 5;
impl AssetMime {
    fn of(path: &str) -> Result<Self, ObservedAssetsFault> {
        if path.ends_with(".js") {
            Ok(Self::JavaScript)
        } else if path.ends_with(".json") || path.ends_with(".map") {
            Ok(Self::Json)
        } else if path.ends_with(".css") {
            Ok(Self::Css)
        } else if path.ends_with(".svg") {
            Ok(Self::Svg)
        } else if path == ORDINARY_TEMPLATE || path == OBSERVED_TEMPLATE {
            Ok(Self::Html)
        } else if path.ends_with(".txt") {
            Ok(Self::Text)
        } else {
            Err(ObservedAssetsFault::Shape)
        }
    }
    fn text(self) -> &'static str {
        match self {
            Self::JavaScript => "text/javascript; charset=utf-8",
            Self::Json => "application/json",
            Self::Css => "text/css; charset=utf-8",
            Self::Svg => "image/svg+xml",
            Self::Html => "text/html; charset=utf-8",
            Self::Text => "text/plain; charset=utf-8",
        }
    }
    fn header(self) -> HeaderValue {
        HeaderValue::from_static(self.text())
    }
}
struct AssetRecord {
    name: Range<usize>,
    content: Range<usize>,
    mime: AssetMime,
    role: AssetRole,
}
enum AssetRole {
    Template,
    ObservedTemplate,
    Asset,
}
struct ApplicationPin {
    commit: [u8; 40],
    tree: [u8; 40],
    build: [u8; 32],
}
struct ImmutableApplication {
    names: Vec<u8>,
    records: Vec<AssetRecord>,
    raw: axum::body::Bytes,
    pin: ApplicationPin,
    maximum_path: usize,
}
pub(super) struct RunObservedApplication {
    source: BrowserApplicationSource,
    image: Arc<ImmutableApplication>,
    end: Instant,
}
fn add(a: usize, b: usize) -> Result<usize, ObservedAssetsFault> {
    a.checked_add(b).ok_or(ObservedAssetsFault::SizeOverflow)
}
fn mul(a: usize, b: usize) -> Result<usize, ObservedAssetsFault> {
    a.checked_mul(b).ok_or(ObservedAssetsFault::SizeOverflow)
}
fn array<T>(n: usize) -> Result<usize, ObservedAssetsFault> {
    Layout::array::<T>(n)
        .map(|layout| layout.size())
        .map_err(|_| ObservedAssetsFault::SizeOverflow)
}
pub(super) fn allocate<T>(
    n: usize,
    loans: &mut BrowserLoans<'_, '_>,
    source: &BrowserApplicationSource,
    end: Instant,
) -> Result<Vec<T>, ObservedAssetsFault> {
    let result = source_work(source, end, || {
        let mut result = Vec::new();
        result
            .try_reserve_exact(n)
            .map_err(ObservedAssetsFault::Allocation)?;
        Ok(result)
    })?;
    let excess = result
        .capacity()
        .checked_sub(n)
        .ok_or(ObservedAssetsFault::SizeOverflow)?;
    loans.reserve_application_storage(source, array::<T>(excess)?, 0, 0)?;
    Ok(result)
}
fn check(source: &BrowserApplicationSource, end: Instant) -> Result<(), ObservedAssetsFault> {
    source_work(source, end, || Ok(()))
}
pub(super) fn source_work<R>(
    source: &BrowserApplicationSource,
    end: Instant,
    work: impl FnOnce() -> Result<R, ObservedAssetsFault>,
) -> Result<R, ObservedAssetsFault> {
    source
        .while_source_active(|| {
            if Instant::now() >= end {
                Err(ObservedAssetsFault::End)
            } else {
                work()
            }
        })
        .map_err(|_| ObservedAssetsFault::Source)?
}
impl RunObservedApplication {
    pub(super) fn prepare(
        acquired: &AcquiredObservedWorkbench<'_>,
        loans: &mut BrowserLoans<'_, '_>,
        end: Instant,
    ) -> Result<Self, ObservedAssetsFault> {
        let source = loans.prepare_application_source()?;
        let result = Self::prepare_image(acquired, loans, &source, end).and_then(|image| {
            source
                .while_source_active(|| {
                    if Instant::now() >= end {
                        Err(ObservedAssetsFault::End)
                    } else {
                        Ok(Arc::new(image))
                    }
                })
                .map_err(|_| ObservedAssetsFault::Source)?
        });
        match result {
            Ok(image) => Ok(Self { source, image, end }),
            Err(cause) => {
                let _ = loans.refuse_application(&source);
                Err(cause)
            }
        }
    }
    fn prepare_image(
        acquired: &AcquiredObservedWorkbench<'_>,
        loans: &mut BrowserLoans<'_, '_>,
        source: &BrowserApplicationSource,
        end: Instant,
    ) -> Result<ImmutableApplication, ObservedAssetsFault> {
        check(source, end)?;
        let manifest = &acquired.manifest;
        let n = manifest.files.len();
        loans.reserve_application_comparison(source, n, 0, 1)?;
        if n == 0 {
            return Err(ObservedAssetsFault::Shape);
        }
        loans.reserve_application_storage(
            source,
            0,
            0,
            add(
                mul(
                    add(manifest.source.commit.len(), manifest.source.tree.len())?,
                    2,
                )?,
                32,
            )?,
        )?;
        fn revision(value: &str) -> Result<[u8; 40], ObservedAssetsFault> {
            if value.len() != 40
                || !value
                    .bytes()
                    .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
            {
                return Err(ObservedAssetsFault::Shape);
            }
            value
                .as_bytes()
                .try_into()
                .map_err(|_| ObservedAssetsFault::Shape)
        }
        let pin = source_work(source, end, || {
            Ok(ApplicationPin {
                commit: revision(manifest.source.commit)?,
                tree: revision(manifest.source.tree)?,
                build: manifest.source.build_manifest_sha256,
            })
        })?;
        let mut bytes = 0;
        let mut names = 0;
        let mut maximum_path = 0;
        let mut previous: Option<&str> = None;
        for file in manifest.files {
            loans.reserve_application_storage(
                source,
                0,
                0,
                add(
                    mul(file.path.len(), PATH_SCAN_PASSES)?,
                    add(mul(MIME_PROBE_BYTES_PER_PASS, 2)?, ROLE_PROBE_BYTES)?,
                )?,
            )?;
            loans.reserve_application_comparison(
                source,
                add(1, OBSERVED_NAME_PROBES)?,
                add(
                    add(previous.map_or(0, str::len), file.path.len())?,
                    mul(OBSERVED_NAME_PROBE_BYTES, OBSERVED_NAME_PROBES)?,
                )?,
                1,
            )?;
            source_work(source, end, || {
                if file.path.is_empty()
                    || file.path.starts_with('/')
                    || file.path.bytes().any(|b| {
                        b == b'\\' || b == b'%' || b == b'?' || b == b'#' || b < 0x20 || b == 0x7f
                    })
                    || file
                        .path
                        .split('/')
                        .any(|part| part.is_empty() || part == "." || part == "..")
                    || previous.is_some_and(|prior| prior >= file.path)
                {
                    return Err(ObservedAssetsFault::Shape);
                }
                AssetMime::of(file.path)?;
                Ok(())
            })?;
            previous = Some(file.path);
            bytes = add(bytes, file.bytes)?;
            names = add(names, file.path.len())?;
            maximum_path = maximum_path.max(file.path.len());
        }
        // Input source declarations are retained as DATA, not executable/source permission.
        // bytes1.12.1 Owned<Vec<u8>> is repr(C), refcount followed by the owner.
        let owned = Layout::new::<AtomicUsize>()
            .extend(Layout::new::<Vec<u8>>())
            .map_err(|_| ObservedAssetsFault::SizeOverflow)?
            .0
            .pad_to_align()
            .size();
        let requested = add(
            add(add(bytes, names)?, array::<AssetRecord>(n)?)?,
            add(
                owned,
                add(
                    arc_layout::<ImmutableApplication>()
                        .map_err(ObservedAssetsFault::Host)?
                        .size(),
                    std::mem::size_of::<Self>(),
                )?,
            )?,
        )?;
        // Raw initialization, actual content writes and SHA input, plus the name
        // arena copy. Charge before any destination allocation/initialization.
        let work = add(mul(bytes, 3)?, names)?;
        loans.reserve_application_storage(source, requested, add(n, 2)?, work)?;
        let mut raw = allocate::<u8>(bytes, loans, source, end)?;
        let mut name_arena = allocate::<u8>(names, loans, source, end)?;
        let mut records = allocate::<AssetRecord>(n, loans, source, end)?;
        source_work(source, end, || {
            raw.resize(bytes, 0);
            Ok(())
        })?;
        let mut offset = 0;
        for (index, file) in manifest.files.iter().enumerate() {
            check(source, end)?;
            let finish = add(offset, file.bytes)?;
            let mut options = OpenOptions::new();
            options.read(true).follow(FollowSymlinks::No).nonblock(true);
            let mut components = Path::new(file.path).components().peekable();
            let mut directory = None;
            let mut leaf = None;
            while let Some(component) = components.next() {
                let Component::Normal(component) = component else {
                    return Err(ObservedAssetsFault::Shape);
                };
                if components.peek().is_none() {
                    leaf = Some(component);
                    break;
                }
                loans.reserve_application_comparison(source, 1, 0, 0)?;
                directory = Some(
                    source
                        .while_source_active(|| {
                            if Instant::now() >= end {
                                return Err(ObservedAssetsFault::End);
                            }
                            directory
                                .as_ref()
                                .unwrap_or(acquired.root)
                                .open_dir_nofollow(component)
                                .map_err(ObservedAssetsFault::Io)
                        })
                        .map_err(|_| ObservedAssetsFault::Source)??,
                );
            }
            let mut actual = source
                .while_source_active(|| {
                    if Instant::now() >= end {
                        return Err(ObservedAssetsFault::End);
                    }
                    directory
                        .as_ref()
                        .unwrap_or(acquired.root)
                        .open_with(leaf.ok_or(ObservedAssetsFault::Shape)?, &options)
                        .map_err(ObservedAssetsFault::Io)
                })
                .map_err(|_| ObservedAssetsFault::Source)??;
            let metadata = source
                .while_source_active(|| {
                    if Instant::now() >= end {
                        return Err(ObservedAssetsFault::End);
                    }
                    actual.metadata().map_err(ObservedAssetsFault::Io)
                })
                .map_err(|_| ObservedAssetsFault::Source)??;
            if !metadata.is_file() {
                return Err(ObservedAssetsFault::FileKind);
            }
            if usize::try_from(metadata.len()).map_err(|_| ObservedAssetsFault::SizeOverflow)?
                != file.bytes
            {
                return Err(ObservedAssetsFault::Size);
            }
            let mut position = offset;
            while position < finish {
                let requested = (finish - position).min(65536);
                loans.reserve_application_comparison(source, 1, 0, 0)?;
                let permission = loans.prepare_application_read(source, requested)?;
                let read = source
                    .while_source_active(|| {
                        if Instant::now() >= end {
                            return Err(ObservedAssetsFault::End);
                        }
                        actual
                            .read(&mut raw[position..position + requested])
                            .map_err(ObservedAssetsFault::Io)
                    })
                    .map_err(|_| ObservedAssetsFault::Source)??;
                permission.finish(read)?;
                if read == 0 {
                    return Err(ObservedAssetsFault::Size);
                }
                position = add(position, read)?;
            }
            loans.reserve_application_storage(source, 0, 0, 1)?;
            let permission = loans.prepare_application_read(source, 1)?;
            let mut extra = [0];
            let read = source
                .while_source_active(|| {
                    if Instant::now() >= end {
                        return Err(ObservedAssetsFault::End);
                    }
                    actual.read(&mut extra).map_err(ObservedAssetsFault::Io)
                })
                .map_err(|_| ObservedAssetsFault::Source)??;
            permission.finish(read)?;
            if read != 0 {
                return Err(ObservedAssetsFault::Size);
            }
            loans.reserve_application_comparison(source, 1, 64, 1)?;
            source_work(source, end, || {
                let digest: [u8; 32] = Sha256::digest(&raw[offset..finish]).into();
                if digest != file.sha256 {
                    return Err(ObservedAssetsFault::Hash {
                        file: index,
                        actual: digest,
                    });
                }
                Ok(())
            })?;
            source_work(source, end, || {
                let start = name_arena.len();
                let mime = AssetMime::of(file.path)?;
                name_arena.extend_from_slice(file.path.as_bytes());
                records.push(AssetRecord {
                    name: start..name_arena.len(),
                    content: offset..finish,
                    mime,
                    role: if matches!(mime, AssetMime::Html) && file.path == OBSERVED_TEMPLATE {
                        AssetRole::ObservedTemplate
                    } else if matches!(mime, AssetMime::Html) {
                        AssetRole::Template
                    } else {
                        AssetRole::Asset
                    },
                });
                Ok(())
            })?;
            offset = finish;
        }
        // These are fixed maintained entry module names, never caller modules.
        for required in [
            b"index.html".as_slice(),
            b"observed-bootstrap.js",
            b"product-observer.js",
        ] {
            loans.reserve_application_comparison(source, n, mul(names, 2)?, 1)?;
            source_work(source, end, || {
                if !records
                    .iter()
                    .any(|record| &name_arena[record.name.clone()] == required)
                {
                    return Err(ObservedAssetsFault::Shape);
                }
                Ok(())
            })?;
        }
        check(source, end)?;
        source
            .while_source_active(|| {
                if Instant::now() >= end {
                    return Err(ObservedAssetsFault::End);
                }
                Ok(ImmutableApplication {
                    names: name_arena,
                    records,
                    raw: axum::body::Bytes::from_owner(raw),
                    pin,
                    maximum_path,
                })
            })
            .map_err(|_| ObservedAssetsFault::Source)?
    }
}
enum AssetDelivery {
    Available(HeaderMap),
    Taken,
}
struct DeliveryState {
    entries: Vec<AssetDelivery>,
    lookups: usize,
}
const ASSET_HEADER_COUNT: usize = 4;
const HEADER_INDEX_COUNT: usize = 8;
struct HeaderTablePlan {
    requested: usize,
    initialized: usize,
    slots: usize,
}
// Same checked source-field upper-bound method as the pinned strict reader.
// This bounds every possible field gap, not the private field order or size.
fn source_fields_upper_layout(fields: &[Layout]) -> Result<Layout, ObservedAssetsFault> {
    let mut bytes = 0;
    let mut alignment = 1;
    for field in fields {
        bytes = add(bytes, add(field.size(), field.align() - 1)?)?;
        alignment = alignment.max(field.align());
    }
    let padded = add(bytes, alignment - 1)? & !(alignment - 1);
    Layout::from_size_align(padded, alignment).map_err(|_| ObservedAssetsFault::SizeOverflow)
}
fn header_table_plan() -> Result<HeaderTablePlan, ObservedAssetsFault> {
    // http1.5.0 map.rs286-328: Size=u16; HashValue(u16);
    // Pos{Size,HashValue}; Links{usize,usize}; Bucket{HashValue,HeaderName,T,Option<Links>}.
    // Bound Option by a usize tag and its payload, without relying on niches.
    let hash = source_fields_upper_layout(&[Layout::new::<u16>()])?;
    let position = source_fields_upper_layout(&[Layout::new::<u16>(), hash])?;
    let links = source_fields_upper_layout(&[Layout::new::<usize>(), Layout::new::<usize>()])?;
    let option_links = source_fields_upper_layout(&[Layout::new::<usize>(), links])?;
    let bucket = source_fields_upper_layout(&[
        hash,
        Layout::new::<axum::http::HeaderName>(),
        Layout::new::<HeaderValue>(),
        option_links,
    ])?;
    // First insertion grows the empty map to8 indices/6 entries. Four distinct
    // static keys neither grow it again nor allocate extra_values. Probe length
    // is below the pinned FORWARD_SHIFT_THRESHOLD512, so no random rehash.
    let indices = HEADER_INDEX_COUNT;
    let entries = indices - indices / 4;
    let owner = std::mem::size_of::<HeaderMap>();
    Ok(HeaderTablePlan {
        requested: add(
            owner,
            add(mul(indices, position.size())?, mul(entries, bucket.size())?)?,
        )?,
        // Initial Pos table, inserted buckets, and at most one full-table
        // forward-shift per insertion (two Pos moves per shifted index).
        initialized: add(
            owner,
            add(
                add(
                    mul(indices, position.size())?,
                    mul(ASSET_HEADER_COUNT, bucket.size())?,
                )?,
                mul(mul(indices, ASSET_HEADER_COUNT)?, mul(2, position.size())?)?,
            )?,
        )?,
        slots: add(1, add(indices, entries)?)?,
    })
}
fn asset_headers(mime: AssetMime) -> HeaderMap {
    let mut headers = HeaderMap::new();
    headers.insert(header::CONTENT_TYPE, mime.header());
    headers.insert(header::CACHE_CONTROL, HeaderValue::from_static("no-store"));
    secure_headers(&mut headers);
    headers
}
fn prepare_asset_headers(
    mime: AssetMime,
    loans: &mut BrowserLoans<'_, '_>,
    source: &BrowserApplicationSource,
    end: Instant,
) -> Result<HeaderMap, ObservedAssetsFault> {
    loans.validate_application_source(source)?;
    let plan = header_table_plan()?;
    // Four distinct static names (62 bytes; longest22), and their static values.
    // Hashing/validation scans and both at-most8-probe insertion phases are paid
    // before HeaderMap initializes its selected-source tables. Static HeaderName
    // and HeaderValue payloads borrow their literals and allocate no payload.
    let names = 12 + 13 + 22 + 15;
    let values = add(mime.text().len(), 8 + 7 + 11)?;
    loans.reserve_application_storage(
        source,
        plan.requested,
        plan.slots,
        add(plan.initialized, add(names, values)?)?,
    )?;
    let probes = mul(mul(2, HEADER_INDEX_COUNT)?, ASSET_HEADER_COUNT)?;
    loans.reserve_application_comparison(
        source,
        probes,
        mul(mul(2, 22)?, probes)?,
        ASSET_HEADER_COUNT,
    )?;
    source_work(source, end, || Ok(asset_headers(mime)))
}
pub(super) fn prepare_document_headers(
    loans: &mut BrowserLoans<'_, '_>,
    source: &BrowserApplicationSource,
    end: Instant,
) -> Result<HeaderMap, ObservedAssetsFault> {
    prepare_asset_headers(AssetMime::Json, loans, source, end)
}
pub(super) struct HostAssets {
    image: Arc<ImmutableApplication>,
    delivery: Mutex<DeliveryState>,
    maximum_uri: usize,
    entry: EntryPreparation,
}
#[derive(Clone, Copy)]
enum EntryPreparation {
    Unprepared,
    Prepared,
}
pub(super) enum AssetRouteFault {
    TransportNotPrepared,
    Limit,
    Unknown,
    Taken,
    Poisoned,
}
impl AssetRouteFault {
    pub(super) fn response(self) -> Response {
        match self {
            Self::Unknown => StatusCode::NOT_FOUND,
            Self::Taken => StatusCode::CONFLICT,
            Self::TransportNotPrepared | Self::Limit | Self::Poisoned => {
                StatusCode::SERVICE_UNAVAILABLE
            }
        }
        .into_response()
    }
}
impl HostAssets {
    fn prepare(
        application: &RunObservedApplication,
        stimulus: &ControlledHostStimulus,
        loans: &mut BrowserLoans<'_, '_>,
        end: Instant,
    ) -> Result<Self, ObservedAssetsFault> {
        Self::prepare_entries(
            application,
            stimulus,
            loans,
            end,
            EntryPreparation::Unprepared,
        )
    }

    fn prepare_observed_document(
        application: &RunObservedApplication,
        stimulus: &ControlledHostStimulus,
        loans: &mut BrowserLoans<'_, '_>,
        end: Instant,
    ) -> Result<Self, ObservedAssetsFault> {
        loans.validate_controlled_application(&application.source, stimulus)?;
        check(&application.source, end)?;
        let mut both_recorded = true;
        for required in [
            OBSERVED_TEMPLATE.as_bytes(),
            OBSERVED_ENTRY_MODULE.as_bytes(),
        ] {
            let names = application.image.names.len();
            let visits = application.image.records.len();
            // Slice equality first checks length, so only equal-sized operands
            // can inspect content; twice the whole name arena covers both sides.
            let comparisons = mul(names, 2)?;
            loans.reserve_application_comparison(&application.source, visits, comparisons, 1)?;
            loans.reserve_application_storage(&application.source, 0, 0, comparisons)?;
            let recorded = source_work(&application.source, end, || {
                Ok(application
                    .image
                    .records
                    .iter()
                    .any(|record| &application.image.names[record.name.clone()] == required))
            })?;
            both_recorded &= recorded;
        }
        let entry = if both_recorded {
            EntryPreparation::Prepared
        } else {
            EntryPreparation::Unprepared
        };
        Self::prepare_entries(application, stimulus, loans, end, entry)
    }

    fn prepare_entries(
        application: &RunObservedApplication,
        stimulus: &ControlledHostStimulus,
        loans: &mut BrowserLoans<'_, '_>,
        end: Instant,
        entry: EntryPreparation,
    ) -> Result<Self, ObservedAssetsFault> {
        loans.validate_controlled_application(&application.source, stimulus)?;
        check(&application.source, end)?;
        let n = application.image.records.len();
        let tickets = add(n, 1)?;
        let comparisons = usize::try_from(usize::BITS - n.leading_zeros())
            .map_err(|_| ObservedAssetsFault::SizeOverflow)?;
        let path = add(OBSERVED_PREFIX.len(), application.image.maximum_path)?;
        let compare_bytes = mul(
            tickets,
            add(mul(mul(comparisons, 2)?, path)?, ROUTE_GUARD_BYTES)?,
        )?;
        loans.reserve_application_comparison(
            &application.source,
            add(mul(tickets, add(comparisons, ROUTE_GUARD_VISITS)?)?, 1)?,
            compare_bytes,
            tickets,
        )?;
        // Body::from(Bytes) boxes a Full<Bytes> followed by a zero-sized error
        // function item. Field gaps are conservatively included from these
        // pinned axum-core/http-body-util source fields, not an RSS estimate.
        let body = add(
            std::mem::size_of::<Option<axum::body::Bytes>>(),
            mul(2, std::mem::align_of::<Option<axum::body::Bytes>>() - 1)?,
        )?;
        let backing = add(
            array::<AssetDelivery>(n)?,
            add(std::mem::size_of::<Self>(), mul(tickets, body)?)?,
        )?;
        loans.reserve_application_storage(
            &application.source,
            backing,
            add(n, tickets)?,
            add(n, compare_bytes)?,
        )?;
        let mut entries = allocate::<AssetDelivery>(n, loans, &application.source, end)?;
        for record in &application.image.records {
            let entry = match record.role {
                AssetRole::Template => AssetDelivery::Taken,
                AssetRole::ObservedTemplate if matches!(entry, EntryPreparation::Unprepared) => {
                    AssetDelivery::Taken
                }
                AssetRole::ObservedTemplate | AssetRole::Asset => AssetDelivery::Available(
                    prepare_asset_headers(record.mime, loans, &application.source, end)?,
                ),
            };
            source_work(&application.source, end, || {
                entries.push(entry);
                Ok(())
            })?;
        }
        source_work(&application.source, end, || {
            Ok(Self {
                image: Arc::clone(&application.image),
                delivery: Mutex::new(DeliveryState {
                    entries,
                    lookups: tickets,
                }),
                maximum_uri: path,
                entry,
            })
        })
    }
    pub(super) fn response(&self, uri: &axum::http::Uri) -> Result<Response, AssetRouteFault> {
        let mut delivery = self
            .delivery
            .lock()
            .map_err(|_| AssetRouteFault::Poisoned)?;
        let left = delivery
            .lookups
            .checked_sub(1)
            .ok_or(AssetRouteFault::Limit)?;
        delivery.lookups = left;
        let path = uri.path();
        if path.len() > self.maximum_uri {
            return Err(AssetRouteFault::Unknown);
        }
        let path = path
            .strip_prefix(OBSERVED_PREFIX)
            .ok_or(AssetRouteFault::Unknown)?;
        if path == ORDINARY_TEMPLATE || path == OBSERVED_TEMPLATE {
            return Err(AssetRouteFault::TransportNotPrepared);
        }
        let path = if path.is_empty() {
            let query = uri.query().ok_or(AssetRouteFault::Unknown)?;
            if query.len() != OBSERVED_QUERY.len() || query != OBSERVED_QUERY {
                return Err(AssetRouteFault::Unknown);
            }
            match self.entry {
                EntryPreparation::Unprepared => return Err(AssetRouteFault::TransportNotPrepared),
                EntryPreparation::Prepared => OBSERVED_TEMPLATE,
            }
        } else {
            path
        };
        let mut low = 0;
        let mut high = self.image.records.len();
        while low < high {
            let middle = low + (high - low) / 2;
            let record = &self.image.records[middle];
            match self.image.names[record.name.clone()].cmp(path.as_bytes()) {
                std::cmp::Ordering::Less => low = middle + 1,
                std::cmp::Ordering::Greater => high = middle,
                std::cmp::Ordering::Equal => {
                    let headers = match std::mem::replace(
                        &mut delivery.entries[middle],
                        AssetDelivery::Taken,
                    ) {
                        AssetDelivery::Taken => return Err(AssetRouteFault::Taken),
                        AssetDelivery::Available(headers) => headers,
                    };
                    let mut response =
                        Response::new(Body::from(self.image.raw.slice(record.content.clone())));
                    *response.headers_mut() = headers;
                    return Ok(response);
                }
            }
        }
        Err(AssetRouteFault::Unknown)
    }
}
impl BoundControlledUiHost {
    pub(super) async fn bind_with_observed_document(
        stimulus: ControlledHostStimulus,
        application: &RunObservedApplication,
        loans: &mut BrowserLoans<'_, '_>,
        limits: ingress::DocumentIngressLimits,
        end: Instant,
    ) -> Result<Self, ingress::DocumentSetupFault> {
        let end = end.min(application.end);
        let assets = HostAssets::prepare_observed_document(application, &stimulus, loans, end)
            .map_err(ingress::DocumentSetupFault::Assets)?;
        Self::bind_prepared_document(stimulus, Some(assets), loans, limits, end).await
    }

    pub(super) async fn bind_with_observed_assets(
        stimulus: ControlledHostStimulus,
        application: &RunObservedApplication,
        loans: &mut BrowserLoans<'_, '_>,
        end: Instant,
    ) -> Result<Self, ObservedAssetsFault> {
        let end = end.min(application.end);
        let assets = HostAssets::prepare(application, &stimulus, loans, end)?;
        Self::bind_inner(stimulus, Some(assets), None, 2, loans, end)
            .await
            .map_err(ObservedAssetsFault::Host)
    }
}
