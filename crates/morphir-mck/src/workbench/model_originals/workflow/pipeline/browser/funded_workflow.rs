//! Fixed owned backing only. This is not a prepared BrowserRun or a grant to
//! launch, read a path, issue an action, collect a Download or compare a result.
use super::inputs::{BrowserInputFault, BrowserOwnerLoans};
use crate::transport::{Limits, process::interactive::FixedCaptureBuffers};
use crate::workbench::model_originals::workflow::pipeline::installed::observation::{
    InstalledObservationFault, InstalledObservationOwner, InstalledObservationResource,
};
use std::alloc::Layout;

/// Six named storage destinations. Runtime metadata, acquired names/assets,
/// transport/serialization work and physical-effect permissions are separate.
pub(super) struct BrowserPhysicalBuffers {
    limits: Limits,
    chromium_stdout: Vec<u8>,
    chromium_stderr: Vec<u8>,
    driver_stdout: Vec<u8>,
    driver_stderr: Vec<u8>,
    control_prefix: Vec<u8>,
    download_window: Vec<u8>,
}
/// The six funded destinations moved into their actual physical owners. The
/// download window remains explicit, including a zero-length no-download slice.
pub(super) struct BrowserPhysicalParts {
    pub(super) limits: Limits,
    pub(super) chromium: FixedCaptureBuffers,
    pub(super) driver: FixedCaptureBuffers,
    pub(super) control_prefix: Vec<u8>,
    pub(super) download_window: Vec<u8>,
}
impl BrowserPhysicalBuffers {
    pub(super) fn into_parts(self) -> BrowserPhysicalParts {
        BrowserPhysicalParts {
            limits: self.limits,
            chromium: FixedCaptureBuffers::new(self.chromium_stdout, self.chromium_stderr),
            driver: FixedCaptureBuffers::new(self.driver_stdout, self.driver_stderr),
            control_prefix: self.control_prefix,
            download_window: self.download_window,
        }
    }
    pub(super) fn prepare(
        loans: &mut BrowserOwnerLoans<'_>,
        limits: Limits,
        window: usize,
    ) -> Result<Self, BrowserInputFault> {
        // A prior fault dominates even requested layout/overflow validation.
        let (decode, receiving, _) = loans.physical_owners()?;
        let preparation =
            (|| {
                let mut requested = std::mem::size_of::<Self>();
                for bytes in [
                    limits.max_frame,
                    limits.stderr_capture,
                    limits.max_frame,
                    limits.stderr_capture,
                    limits.max_frame,
                    window,
                ] {
                    Layout::array::<u8>(bytes).map_err(|_| {
                        BrowserInputFault::Receiving(InstalledObservationFault::SizeOverflow)
                    })?;
                    requested =
                        requested
                            .checked_add(bytes)
                            .ok_or(BrowserInputFault::Receiving(
                                InstalledObservationFault::SizeOverflow,
                            ))?;
                }
                let initialized =
                    limits
                        .max_frame
                        .checked_add(window)
                        .ok_or(BrowserInputFault::Receiving(
                            InstalledObservationFault::SizeOverflow,
                        ))?;
                // Pay the actual typed metadata, every requested destination, and
                // initialization work before the first destination allocation.
                decode.slots(6).map_err(BrowserInputFault::Decode)?;
                receiving
                    .reserve_span(InstalledObservationResource::RetainedBytes, requested)
                    .map_err(BrowserInputFault::Receiving)?;
                receiving
                    .reserve_span(InstalledObservationResource::ByteVisits, initialized)
                    .map_err(BrowserInputFault::Receiving)?;
                decode
                    .bytes(initialized)
                    .map_err(BrowserInputFault::Decode)?;
                for _ in 0..2 {
                    receiving
                        .reserve_process_prefixes(&limits)
                        .map_err(|f| BrowserInputFault::Receiving(*f))?
                        .commit();
                }
                fn allocate(
                    receiving: &mut InstalledObservationOwner,
                    requested: usize,
                ) -> Result<Vec<u8>, BrowserInputFault> {
                    let mut bytes = Vec::new();
                    bytes.try_reserve_exact(requested).map_err(|_| {
                        BrowserInputFault::Receiving(InstalledObservationFault::Allocation)
                    })?;
                    let excess = bytes.capacity().checked_sub(requested).ok_or(
                        BrowserInputFault::Receiving(InstalledObservationFault::LayoutMismatch),
                    )?;
                    // Spare capacity is charged before any initialization or use.
                    // It never enlarges the requested stream/window dimensions.
                    receiving
                        .reserve_span(InstalledObservationResource::RetainedBytes, excess)
                        .map_err(BrowserInputFault::Receiving)?;
                    Ok(bytes)
                }
                let chromium_stdout = allocate(receiving, limits.max_frame)?;
                let chromium_stderr = allocate(receiving, limits.stderr_capture)?;
                let driver_stdout = allocate(receiving, limits.max_frame)?;
                let driver_stderr = allocate(receiving, limits.stderr_capture)?;
                let mut control_prefix = allocate(receiving, limits.max_frame)?;
                let mut download_window = allocate(receiving, window)?;
                control_prefix.resize(limits.max_frame, 0);
                download_window.resize(window, 0);
                Ok(Self {
                    limits,
                    chromium_stdout,
                    chromium_stderr,
                    driver_stdout,
                    driver_stderr,
                    control_prefix,
                    download_window,
                })
            })();
        if let Err(fault) = &preparation {
            receiving.fail(match fault {
                BrowserInputFault::Receiving(fault) => *fault,
                _ => InstalledObservationFault::PriorFault,
            });
        }
        preparation
    }
    #[cfg(test)]
    pub(super) fn lengths(&self) -> [usize; 6] {
        [
            self.chromium_stdout.len(),
            self.chromium_stderr.len(),
            self.driver_stdout.len(),
            self.driver_stderr.len(),
            self.control_prefix.len(),
            self.download_window.len(),
        ]
    }
    #[cfg(test)]
    pub(super) fn capacities(&self) -> [usize; 6] {
        [
            self.chromium_stdout.capacity(),
            self.chromium_stderr.capacity(),
            self.driver_stdout.capacity(),
            self.driver_stderr.capacity(),
            self.control_prefix.capacity(),
            self.download_window.capacity(),
        ]
    }
}
