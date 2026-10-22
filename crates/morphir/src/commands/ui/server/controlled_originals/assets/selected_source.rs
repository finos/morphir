//! Private association with one explicitly selected reviewed UI build INPUT.
//! It is not a BrowserRun, host grant, Page effect, or qualification result.
use super::*;
use morphir_mck::workbench::{BrowserActionIssueError, BrowserConnectedOpening};

const SELECTED_COMMIT: &[u8; 40] = b"a42427debd0f5b3d484446e22670d2527469a538";
const SELECTED_TREE: &[u8; 40] = b"bd397354331a208523805f0a02a955e2594891c7";
const SELECTED_FILES: usize = 77;
const SELECTED_BYTES: usize = 15_392_100;
const SELECTED_TABLE: [u8; 32] = [
    0xa2, 0xb2, 0x44, 0x19, 0x28, 0xa3, 0xb6, 0x1c, 0x85, 0xec, 0x60, 0x03, 0x39, 0x31, 0xfe, 0xb9,
    0xad, 0x6c, 0xcb, 0x2b, 0xfa, 0xcd, 0x90, 0xe6, 0x70, 0xb4, 0x28, 0xd0, 0xaf, 0x55, 0x7b, 0x24,
];
#[derive(Debug)]
pub(super) enum SelectedSourceFault {
    Assets(ObservedAssetsFault),
    SelectedManifest,
    RetainedImage,
    Action(BrowserActionIssueError),
    OriginalEnd,
    HostImage,
    HostEntry,
    HostFault,
}
impl From<ObservedAssetsFault> for SelectedSourceFault {
    fn from(fault: ObservedAssetsFault) -> Self {
        Self::Assets(fault)
    }
}
impl From<BrowserInputError> for SelectedSourceFault {
    fn from(fault: BrowserInputError) -> Self {
        Self::Assets(ObservedAssetsFault::Funding(fault))
    }
}
impl From<BrowserActionIssueError> for SelectedSourceFault {
    fn from(fault: BrowserActionIssueError) -> Self {
        Self::Action(fault)
    }
}
/// A native-owned reference to the actual selected immutable image. It grants
/// no source action; a later native host join must validate its SAME Arc,
/// genuine source0 child/journal and fixed original end before any launch.
pub(super) struct SelectedSourceApplication {
    image: Arc<ImmutableApplication>,
    end: Instant,
}
/// The actual native host, acquired image and original end survive the initial
/// action borrow. No parallel host Arc or copied launch URL is introduced.
struct SelectedSourceHost {
    host: BoundControlledUiHost,
    application: SelectedSourceApplication,
}
/// Source0's borrowed token is held only during initial native composition.
/// This owner does not assert a Page reply or complete any source action.
struct SelectedSourceLaunch<'a> {
    owner: SelectedSourceHost,
    opening: BrowserConnectedOpening<'a>,
}
struct SelectedSourceLaunchFailure<'a> {
    fault: SelectedSourceFault,
    application: SelectedSourceApplication,
    host: BoundControlledUiHost,
    opening: BrowserConnectedOpening<'a>,
}
impl<'a> SelectedSourceLaunchFailure<'a> {
    fn into_parts(
        self,
    ) -> (
        SelectedSourceFault,
        SelectedSourceApplication,
        BoundControlledUiHost,
        BrowserConnectedOpening<'a>,
    ) {
        (self.fault, self.application, self.host, self.opening)
    }
}
fn decimal_bytes(mut value: usize, output: &mut [u8; 20]) -> &[u8] {
    let mut start = output.len();
    loop {
        start -= 1;
        output[start] = b'0' + (value % 10) as u8;
        value /= 10;
        if value == 0 {
            return &output[start..];
        }
    }
}
fn digest_hex(input: &[u8; 32], output: &mut [u8; 64]) {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    for (byte, pair) in input.iter().zip(output.chunks_exact_mut(2)) {
        pair[0] = HEX[(byte >> 4) as usize];
        pair[1] = HEX[(byte & 15) as usize];
    }
}
impl SelectedSourceApplication {
    fn into_launch<'a>(
        self,
        host: BoundControlledUiHost,
        application: &RunObservedApplication,
        opening: BrowserConnectedOpening<'a>,
        loans: &mut BrowserLoans<'_, '_>,
    ) -> Result<SelectedSourceLaunch<'a>, SelectedSourceLaunchFailure<'a>> {
        let checked = (|| -> Result<(), SelectedSourceFault> {
            // The genuine current action/child/original end dominates native
            // host shape and all new comparison/retention funding.
            opening.while_host_active(loans, || ())?;
            let producer = host
                .document_producer
                .as_ref()
                .ok_or(SelectedSourceFault::HostEntry)?;
            let transcript = host
                .state
                .transcript
                .as_ref()
                .ok_or(SelectedSourceFault::HostEntry)?;
            let end = opening.validate_host(producer, transcript, &host.state.source, loans)?;
            opening.validate_application(&application.source, &host.state.source, loans)?;
            let headers = add(
                std::mem::size_of::<SelectedSourceLaunch<'_>>(),
                add(
                    std::mem::size_of::<SelectedSourceHost>(),
                    std::mem::size_of::<SelectedSourceLaunchFailure<'_>>(),
                )?,
            )?;
            let comparisons = add(
                6 * std::mem::size_of::<Instant>() + 6 * std::mem::size_of::<usize>() + 2,
                std::mem::size_of::<super::super::ListenerOwner>(),
            )?;
            loans.reserve_controlled_host_storage(headers, 3, add(headers, comparisons)?)?;
            // No source/loan call belongs inside this exact parent→child and
            // journal gate. These are prepaid comparisons of actual owners.
            opening.while_host_active(loans, || {
                if self.end != end || host.state.end != end || application.end < end {
                    return Err(SelectedSourceFault::OriginalEnd);
                }
                let assets = host
                    .state
                    .assets
                    .as_ref()
                    .ok_or(SelectedSourceFault::HostEntry)?;
                if !Arc::ptr_eq(&self.image, &application.image)
                    || !Arc::ptr_eq(&self.image, &assets.image)
                {
                    return Err(SelectedSourceFault::HostImage);
                }
                if !matches!(host.listener, super::super::ListenerOwner::Bound(_))
                    || !matches!(assets.entry, EntryPreparation::Prepared)
                    || !matches!(
                        host.state.launch_destination,
                        super::super::LaunchDestination::ObservedDocument
                    )
                {
                    return Err(SelectedSourceFault::HostEntry);
                }
                if host.state.first().is_some() {
                    return Err(SelectedSourceFault::HostFault);
                }
                Ok(())
            })??;
            Ok(())
        })();
        match checked {
            Ok(()) => Ok(SelectedSourceLaunch {
                owner: SelectedSourceHost {
                    host,
                    application: self,
                },
                opening,
            }),
            // These are the SAME consumed owners. No host state, source link,
            // image or URL clone was made, even on a funding/source refusal.
            Err(fault) => Err(SelectedSourceLaunchFailure {
                fault,
                application: self,
                host,
                opening,
            }),
        }
    }

    pub(super) fn prepare(
        application: &RunObservedApplication,
        selected: &ApplicationManifest<'_>,
        loans: &mut BrowserLoans<'_, '_>,
        end: Instant,
    ) -> Result<Self, SelectedSourceFault> {
        // Application/parent and cumulative owner failures dominate selected DATA.
        // This shared-image INPUT check is not row-child verification; that
        // belongs to the genuine source0 SDK and its active retention gate.
        loans.validate_application_source(&application.source)?;
        // A component may conservatively shorten this image lifetime. Native
        // launch must separately match the actual original host/SDK end.
        let end = end.min(application.end);
        check(&application.source, end)?;
        loans.reserve_application_comparison(&application.source, SELECTED_FILES, 0, 1)?;
        if selected.files.len() != SELECTED_FILES
            || application.image.records.len() != SELECTED_FILES
        {
            return Err(SelectedSourceFault::SelectedManifest);
        }
        let mut table_bytes = 0usize;
        let mut names = 0usize;
        let mut original_bytes = 0usize;
        // One fixed-size row descriptor visit, before reading any variable name.
        loans.reserve_application_storage(
            &application.source,
            0,
            0,
            mul(SELECTED_FILES, std::mem::size_of::<ApplicationFile<'_>>())?,
        )?;
        for file in selected.files {
            names = add(names, file.path.len())?;
            table_bytes = add(table_bytes, add(file.path.len(), 20 + 64 + 3)?)?;
            original_bytes = add(original_bytes, file.bytes)?;
        }
        let headers = add(
            std::mem::size_of::<Self>(),
            add(
                mul(SELECTED_FILES + 1, std::mem::size_of::<Sha256>())?,
                20 + 64 + 3 * 32,
            )?,
        )?;
        let comparison_bytes = add(
            2 * (40 + 40 + 32),
            add(
                mul(names, 2)?,
                mul(SELECTED_FILES, 2 * 32 + 2 * std::mem::size_of::<usize>())?,
            )?,
        )?;
        loans.reserve_application_comparison(
            &application.source,
            mul(SELECTED_FILES, 5)?,
            comparison_bytes,
            SELECTED_FILES + 1,
        )?;
        loans.reserve_application_storage(
            &application.source,
            headers,
            2,
            add(
                headers,
                add(mul(table_bytes, 2)?, add(original_bytes, comparison_bytes)?)?,
            )?,
        )?;
        let image = source_work(&application.source, end, || {
            if selected.source.commit.as_bytes() != SELECTED_COMMIT
                || selected.source.tree.as_bytes() != SELECTED_TREE
                || selected.source.build_manifest_sha256 != SELECTED_TABLE
                || application.image.pin.commit != *SELECTED_COMMIT
                || application.image.pin.tree != *SELECTED_TREE
                || application.image.pin.build != SELECTED_TABLE
                || original_bytes != SELECTED_BYTES
                || application.image.raw.len() != SELECTED_BYTES
            {
                return Err(ObservedAssetsFault::Shape);
            }
            Ok(())
        });
        match image {
            Err(ObservedAssetsFault::Shape) => return Err(SelectedSourceFault::SelectedManifest),
            other => other?,
        }
        let table_digest: [u8; 32] = source_work(&application.source, end, || {
            let mut hash = Sha256::new();
            let mut decimal = [0; 20];
            let mut hex = [0; 64];
            for file in selected.files {
                hash.update(file.path.as_bytes());
                hash.update(b"\t");
                hash.update(decimal_bytes(file.bytes, &mut decimal));
                hash.update(b"\t");
                digest_hex(&file.sha256, &mut hex);
                hash.update(hex);
                hash.update(b"\n");
            }
            Ok(hash.finalize().into())
        })?;
        if table_digest != SELECTED_TABLE {
            return Err(SelectedSourceFault::SelectedManifest);
        }
        let mut expected_start = 0usize;
        for (record, file) in application.image.records.iter().zip(selected.files) {
            let actual = source_work(&application.source, end, || {
                let name = application
                    .image
                    .names
                    .get(record.name.clone())
                    .ok_or(ObservedAssetsFault::Shape)?;
                let body = application
                    .image
                    .raw
                    .get(record.content.clone())
                    .ok_or(ObservedAssetsFault::Shape)?;
                if name != file.path.as_bytes()
                    || body.len() != file.bytes
                    || record.content.start != expected_start
                {
                    return Err(ObservedAssetsFault::Shape);
                }
                let digest: [u8; 32] = Sha256::digest(body).into();
                if digest != file.sha256 {
                    return Err(ObservedAssetsFault::Shape);
                }
                expected_start = record.content.end;
                Ok(())
            });
            match actual {
                Err(ObservedAssetsFault::Shape) => return Err(SelectedSourceFault::RetainedImage),
                other => other?,
            }
        }
        if expected_start != application.image.raw.len() {
            return Err(SelectedSourceFault::RetainedImage);
        }
        Ok(source_work(&application.source, end, || {
            Ok(Self {
                image: Arc::clone(&application.image),
                end,
            })
        })?)
    }
}

#[cfg(test)]
mod tests;
