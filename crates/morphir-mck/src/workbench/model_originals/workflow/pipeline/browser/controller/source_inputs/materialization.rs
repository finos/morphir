//! A separately prepaid consuming pass over the SAME immutable selected archive.
//! It emits source bytes to a caller-owned filesystem sink. Source completion
//! does not assert any write, close, process, browser or physical join outcome.
use super::*;
use std::marker::PhantomData;
use std::time::Instant;

#[derive(Clone, Copy, Debug)]
pub(in super::super) enum RuntimeArchiveReadFault {
    Source(BrowserSourceFault),
    Activity(BrowserActivityFault),
    Archive(io::ErrorKind),
    Truncated { expected: u64, actual: u64 },
    Inventory,
    PriorFault,
}
#[derive(Debug)]
pub(in super::super) enum RuntimeArchiveReadTerminal {
    Complete {
        files: usize,
        bytes: u64,
    },
    Incomplete {
        files: usize,
        bytes: u64,
        first: Option<RuntimeArchiveReadFault>,
    },
}
#[derive(Debug)]
pub(in super::super) enum RuntimeSinkTerminal<E> {
    NotAttempted,
    Returned { entries: usize },
    Raised { completed_entries: usize, error: E },
}
pub(in super::super) struct RuntimeMaterializationPreparationFailure {
    package: SelectedRuntimePackage,
    fault: RuntimeAssociationFault,
}
impl RuntimeMaterializationPreparationFailure {
    pub(in super::super) fn fault(&self) -> &RuntimeAssociationFault {
        &self.fault
    }
    pub(in super::super) fn dimensions(&self) -> RuntimePackageDimensions {
        self.package.dimensions()
    }
    pub(in super::super) fn files(&self) -> impl ExactSizeIterator<Item = RuntimePackageFile<'_>> {
        self.package.files()
    }
}
/// The original owner is consumed once, including on refusal. There is no
/// mutable funding loan at read time and no conversion back to a prepared pass.
pub(in super::super) struct PreparedRuntimeMaterialization<E> {
    package: SelectedRuntimePackage,
    window: Vec<u8>,
    sink: PhantomData<fn() -> E>,
}
#[derive(Clone, Copy, Debug)]
pub(in super::super) enum RuntimeArchiveTail {
    NotAttempted,
    Reading { bytes: usize },
    ReadEof { bytes: usize },
}
pub(in super::super) struct ConsumedRuntimePackage {
    package: SelectedRuntimePackage,
    tail: RuntimeArchiveTail,
}
impl ConsumedRuntimePackage {
    pub(in super::super) fn dimensions(&self) -> RuntimePackageDimensions {
        self.package.dimensions()
    }
    pub(in super::super) fn files(&self) -> impl ExactSizeIterator<Item = RuntimePackageFile<'_>> {
        self.package.files()
    }
    pub(in super::super) fn tail(&self) -> RuntimeArchiveTail {
        self.tail
    }
}
pub(in super::super) struct RuntimeMaterialization<E> {
    package: ConsumedRuntimePackage,
    source: RuntimeArchiveReadTerminal,
    sink: RuntimeSinkTerminal<E>,
}
impl<E> RuntimeMaterialization<E> {
    pub(in super::super) fn into_parts(
        self,
    ) -> (
        ConsumedRuntimePackage,
        RuntimeArchiveReadTerminal,
        RuntimeSinkTerminal<E>,
    ) {
        (self.package, self.source, self.sink)
    }
}
fn gate<R>(
    activity: &SourceControllerActivity,
    loans: &BrowserLoans<'_, '_>,
    action: impl FnOnce() -> Result<R, RuntimeArchiveReadFault>,
) -> Result<R, RuntimeArchiveReadFault> {
    // A sticky owner or foreign relation refuses before stream inspection.
    activity
        .while_business_active(loans, action)
        .map_err(|fault| {
            if let Some(cause) = fault.source_cause() {
                RuntimeArchiveReadFault::Source(cause)
            } else if let Some(cause) = fault.activity_cause() {
                RuntimeArchiveReadFault::Activity(cause)
            } else {
                RuntimeArchiveReadFault::PriorFault
            }
        })?
}
pub(super) fn validation_calls_upper() -> Result<usize, RuntimeAssociationFault> {
    let body = usize::try_from(FILE_BYTES).map_err(|_| RuntimeAssociationFault::Overflow)?;
    // The implemented fill loop holds ONE relation/journal guard until its
    // fixed window is full, EOF, error or original-end refusal. Summed file
    // ceilings are at most floor(total/WINDOW)+FILES, even with empty files.
    let body_and_eof = add(add(body / WINDOW, FILES)?, FILES)?;
    let header_advances = add(FILES, 1)?;
    let descriptor_checks = FILES;
    // Decoder, tar owner, iterator, and initial exact activity validation.
    let setup = 4;
    add(
        add(body_and_eof, header_advances)?,
        add(
            descriptor_checks,
            add(setup, add(tail_bytes_upper()? / WINDOW, 1)?)?,
        )?,
    )
}
fn tail_bytes_upper() -> Result<usize, RuntimeAssociationFault> {
    TAR_BYTES
        .checked_sub(usize::try_from(FILE_BYTES).map_err(|_| RuntimeAssociationFault::Overflow)?)
        .and_then(|n| n.checked_sub(FILES.checked_mul(512)?))
        .ok_or(RuntimeAssociationFault::Overflow)
}
pub(super) fn partial_reads_upper() -> Result<usize, RuntimeAssociationFault> {
    // Every nonzero body/tail read may return one byte. Every file and the
    // final tail also has an actual terminal zero-count/error read.
    add(
        add(
            usize::try_from(FILE_BYTES).map_err(|_| RuntimeAssociationFault::Overflow)?,
            FILES,
        )?,
        add(tail_bytes_upper()?, 1)?,
    )
}
pub(super) fn partial_read_work_upper() -> Result<usize, RuntimeAssociationFault> {
    // Actual source-visible fields used for one partial iteration: sampled
    // and original Instant, output slice range, filled/read counters, actual
    // and declared u64 counts, owned Read result and closed refusal value.
    // Full owner/source/journal traversal is separately paid once per chunk.
    // This bounds logical field visits, not allocator, clock/IO CPU or RSS.
    let clocks = mul(2, size_of::<Instant>())?;
    let offsets = add(size_of::<Range<usize>>(), mul(2, size_of::<usize>())?)?;
    let counts = mul(2, size_of::<u64>())?;
    add(
        add(clocks, offsets)?,
        add(
            counts,
            add(
                size_of::<io::Result<usize>>(),
                size_of::<RuntimeArchiveReadFault>(),
            )?,
        )?,
    )
}
impl SelectedRuntimePackage {
    pub(in super::super) fn prepare_materialization<E>(
        self,
        lifetime: &SourceControllerLifetime,
        loans: &mut BrowserLoans<'_, '_>,
    ) -> Result<PreparedRuntimeMaterialization<E>, RuntimeMaterializationPreparationFailure> {
        let prepare = (|| {
            self.validate(lifetime, loans)?;
            // The second decompression/hash pass is independent work. It does
            // not reuse credit from the first authenticated inventory pass.
            let entries = mul(FILES, size_of::<[usize; 8]>())?;
            let headers = add(
                size_of::<PreparedRuntimeMaterialization<E>>(),
                size_of::<RuntimeMaterialization<E>>(),
            )?;
            let headers = add(
                headers,
                size_of::<RuntimeMaterializationPreparationFailure>(),
            )?;
            let headers = add(headers, size_of::<RuntimeSinkTerminal<E>>())?;
            let headers = add(headers, size_of::<RuntimeArchiveFile<'_, '_, '_>>())?;
            let headers = add(headers, size_of::<flate2::bufread::GzDecoder<&[u8]>>())?;
            let headers = add(headers, size_of::<tar::Archive<&[u8]>>())?;
            let headers = add(headers, size_of::<tar::Entries<'_, &[u8]>>())?;
            let headers = add(headers, mul(2, size_of::<tar::Entry<'_, &[u8]>>())?)?;
            let bytes = add(
                headers,
                add(
                    WINDOW,
                    add(
                        inflater_backing_upper()?,
                        add(entries, mul(FILES, 2 * size_of::<Sha256>() + 32)?)?,
                    )?,
                )?,
            )?;
            let work = add(
                bytes,
                add(
                    mul(TAR_BYTES, 8)?,
                    add(mul(FILE_BYTES as usize, 3)?, mul(NAME_BYTES, 3)?)?,
                )?,
            )?;
            // Repeated source/parent/child/journal/end validation is distinct
            // from one-time view backing and inflate/hash/copy work. Nothing
            // can debit this credit again after residual cleanup is prepared.
            let validation = SourceControllerActivity::validation_work_upper()
                .ok_or(RuntimeAssociationFault::Overflow)?;
            let work = add(work, mul(validation_calls_upper()?, validation)?)?;
            let work = add(
                work,
                mul(partial_reads_upper()?, partial_read_work_upper()?)?,
            )?;
            loans
                .reserve_controlled_host_storage(bytes, add(mul(FILES, 3)?, 16)?, work)
                .map_err(RuntimeAssociationFault::Input)?;
            let mut window = allocate::<u8>(WINDOW, lifetime, loans)?;
            active(lifetime, loans, || {
                window.resize(WINDOW, 0);
                Ok(())
            })?;
            Ok(window)
        })();
        match prepare {
            Ok(window) => Ok(PreparedRuntimeMaterialization {
                package: self,
                window,
                sink: PhantomData,
            }),
            Err(fault) => Err(RuntimeMaterializationPreparationFailure {
                package: self,
                fault,
            }),
        }
    }
}

enum EntryProgress {
    Reading {
        actual: u64,
    },
    Complete {
        actual: u64,
    },
    Refused {
        actual: u64,
        first: RuntimeArchiveReadFault,
    },
}
enum FilledChunk {
    Data(usize),
    Eof,
}
/// Borrowed bounded reader. Only its fixed next chunk size is exposed. A sink
/// cannot seek, select another entry, retry a refused read, or drain implicitly.
pub(in super::super) struct RuntimeArchiveFile<'entry, 'owners, 'loan> {
    entry: &'entry mut dyn Read,
    activity: &'entry SourceControllerActivity,
    loans: &'entry BrowserLoans<'owners, 'loan>,
    window: &'entry mut [u8],
    expected: &'entry RuntimeFile,
    hash: Sha256,
    progress: EntryProgress,
}
impl RuntimeArchiveFile<'_, '_, '_> {
    pub(in super::super) fn next_chunk(
        &mut self,
    ) -> Result<Option<&[u8]>, RuntimeArchiveReadFault> {
        let mut actual = match self.progress {
            EntryProgress::Complete { .. } => return Ok(None),
            EntryProgress::Refused { first, .. } => return Err(first),
            EntryProgress::Reading { actual } => actual,
        };
        let remaining = self
            .expected
            .bytes
            .checked_sub(actual)
            .ok_or(RuntimeArchiveReadFault::Inventory)?;
        // Even an empty file requires an actual zero-count entry read. The tar
        // Entry reader enforces its exact body range, separately from gzip EOF.
        let want = remaining.min(self.window.len() as u64).max(1) as usize;
        let end = self.activity.end();
        let result = gate(self.activity, self.loans, || {
            let mut filled = 0;
            loop {
                // Parent→child→journal remains held for the bounded chunk.
                // Time can still advance, so sample before EVERY actual Read.
                if Instant::now() >= end {
                    return Err(RuntimeArchiveReadFault::Activity(
                        BrowserActivityFault::OriginalEnd,
                    ));
                }
                let count = self
                    .entry
                    .read(&mut self.window[filled..want])
                    .map_err(|error| RuntimeArchiveReadFault::Archive(error.kind()))?;
                if count == 0 {
                    if actual != self.expected.bytes {
                        return Err(RuntimeArchiveReadFault::Truncated {
                            expected: self.expected.bytes,
                            actual,
                        });
                    }
                    if <[u8; 32]>::from(self.hash.clone().finalize()) != self.expected.digest {
                        return Err(RuntimeArchiveReadFault::Inventory);
                    }
                    return Ok(FilledChunk::Eof);
                }
                if count > want - filled {
                    return Err(RuntimeArchiveReadFault::Inventory);
                }
                actual += count as u64;
                self.hash.update(&self.window[filled..filled + count]);
                filled += count;
                if actual > self.expected.bytes {
                    return Err(RuntimeArchiveReadFault::Inventory);
                }
                if filled == want {
                    return Ok(FilledChunk::Data(filled));
                }
            }
        });
        match result {
            Err(first) => {
                self.progress = EntryProgress::Refused { actual, first };
                Err(first)
            }
            Ok(FilledChunk::Eof) => {
                self.progress = EntryProgress::Complete { actual };
                Ok(None)
            }
            Ok(FilledChunk::Data(count)) => {
                self.progress = EntryProgress::Reading { actual };
                Ok(Some(&self.window[..count]))
            }
        }
    }
}
impl<E> PreparedRuntimeMaterialization<E> {
    pub(in super::super) fn dimensions(&self) -> RuntimePackageDimensions {
        self.package.dimensions()
    }
    pub(in super::super) fn files(&self) -> impl ExactSizeIterator<Item = RuntimePackageFile<'_>> {
        self.package.files()
    }
    pub(in super::super) fn validate(
        &self,
        lifetime: &SourceControllerLifetime,
        loans: &BrowserLoans<'_, '_>,
    ) -> Result<(), RuntimeAssociationFault> {
        self.package.validate(lifetime, loans)
    }
    pub(in super::super) fn materialize(
        mut self,
        loans: &BrowserLoans<'_, '_>,
        mut sink: impl FnMut(
            RuntimePackageFile<'_>,
            &mut RuntimeArchiveFile<'_, '_, '_>,
        ) -> Result<(), E>,
    ) -> RuntimeMaterialization<E> {
        let mut files = 0;
        let mut bytes = 0;
        let mut sink_terminal = RuntimeSinkTerminal::NotAttempted;
        let mut tail_state = RuntimeArchiveTail::NotAttempted;
        let result = (|| {
            let package = &self.package;
            let decoder = gate(&package.activity, loans, || {
                Ok(flate2::bufread::GzDecoder::new(package.archive.as_slice()))
            })?;
            let mut archive = gate(&package.activity, loans, || {
                Ok(tar::Archive::new(decoder.take(TAR_BYTES as u64 + 1)))
            })?;
            {
                let mut entries = gate(&package.activity, loans, || {
                    archive
                        .entries()
                        .map(|entries| entries.raw(true))
                        .map_err(|error| RuntimeArchiveReadFault::Archive(error.kind()))
                })?;
                loop {
                    let next = gate(&package.activity, loans, || {
                        entries
                            .next()
                            .transpose()
                            .map_err(|error| RuntimeArchiveReadFault::Archive(error.kind()))
                    })?;
                    let Some(mut entry) = next else {
                        break;
                    };
                    let (expected, name) = gate(&package.activity, loans, || {
                        let expected = package
                            .files
                            .get(files)
                            .ok_or(RuntimeArchiveReadFault::Inventory)?;
                        let name = std::str::from_utf8(&package.names[expected.name.clone()])
                            .map_err(|_| RuntimeArchiveReadFault::Inventory)?;
                        let path = entry.path_bytes();
                        if entry.header().entry_type() != tar::EntryType::Regular
                            || path.strip_prefix(b"package/") != Some(name.as_bytes())
                            || entry
                                .header()
                                .size()
                                .map_err(|e| RuntimeArchiveReadFault::Archive(e.kind()))?
                                != expected.bytes
                            || entry
                                .header()
                                .mode()
                                .map_err(|e| RuntimeArchiveReadFault::Archive(e.kind()))?
                                != expected.mode.unix_mode()
                        {
                            return Err(RuntimeArchiveReadFault::Inventory);
                        }
                        Ok((expected, name))
                    })?;
                    let mut reader = RuntimeArchiveFile {
                        entry: &mut entry,
                        activity: &package.activity,
                        loans,
                        window: &mut self.window,
                        expected,
                        hash: Sha256::new(),
                        progress: EntryProgress::Reading { actual: 0 },
                    };
                    let outcome = sink(
                        RuntimePackageFile {
                            name,
                            file: expected,
                        },
                        &mut reader,
                    );
                    let (actual, complete, first) = match reader.progress {
                        EntryProgress::Reading { actual } => (actual, false, None),
                        EntryProgress::Complete { actual } => (actual, true, None),
                        EntryProgress::Refused { actual, first } => (actual, false, Some(first)),
                    };
                    bytes += actual;
                    match outcome {
                        Err(error) => {
                            sink_terminal = RuntimeSinkTerminal::Raised {
                                completed_entries: files,
                                error,
                            };
                            // A sink failure cannot erase a source entry whose
                            // digest and zero-count read already completed.
                            if complete {
                                files += 1;
                            }
                            return Err(first);
                        }
                        Ok(()) => {
                            sink_terminal = RuntimeSinkTerminal::Returned { entries: files + 1 }
                        }
                    }
                    if !complete {
                        return Err(Some(first.unwrap_or(RuntimeArchiveReadFault::Inventory)));
                    }
                    files += 1;
                }
            }
            let mut tail = archive.into_inner();
            let mut tail_bytes = 0;
            loop {
                let eof = gate(&package.activity, loans, || {
                    let mut filled = 0;
                    while filled < self.window.len() {
                        if Instant::now() >= package.activity.end() {
                            return Err(RuntimeArchiveReadFault::Activity(
                                BrowserActivityFault::OriginalEnd,
                            ));
                        }
                        tail_state = RuntimeArchiveTail::Reading { bytes: tail_bytes };
                        let count = tail
                            .read(&mut self.window[filled..])
                            .map_err(|error| RuntimeArchiveReadFault::Archive(error.kind()))?;
                        if count == 0 {
                            tail_state = RuntimeArchiveTail::ReadEof { bytes: tail_bytes };
                            return Ok(true);
                        }
                        filled += count;
                        tail_bytes += count;
                        tail_state = RuntimeArchiveTail::Reading { bytes: tail_bytes };
                    }
                    Ok(false)
                })?;
                if eof {
                    break;
                }
            }
            if files != FILES || bytes != FILE_BYTES || tail.limit() != 1 {
                return Err(Some(RuntimeArchiveReadFault::Inventory));
            }
            Ok(())
        })();
        let source = match result {
            Ok(()) => RuntimeArchiveReadTerminal::Complete { files, bytes },
            Err(first) => RuntimeArchiveReadTerminal::Incomplete {
                files,
                bytes,
                first,
            },
        };
        RuntimeMaterialization {
            package: ConsumedRuntimePackage {
                package: self.package,
                tail: tail_state,
            },
            source,
            sink: sink_terminal,
        }
    }
}
#[cfg(test)]
mod read_tests;
