//! Owned fixed command backing prepared before residual filesystem cleanup.
use super::*;
use std::mem::size_of;

pub(in super::super) const SOURCE_ENDPOINT_BYTES: usize =
    "ws://127.0.0.1:65535/devtools/browser/00000000-0000-0000-0000-000000000000".len();
const LAUNCH_BYTES: usize =
    "http://127.0.0.1:65535/launch?token=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA".len();

#[derive(Debug)]
pub(super) enum StorageFault {
    Input(BrowserInputError),
    Allocation,
    Overflow,
    Capacity,
}
pub(in super::super) struct SourcePreparedDriverCommand {
    pub(in super::super) program: PathBuf,
    pub(in super::super) directory: PathBuf,
    pub(in super::super) arguments: Vec<OsString>,
    pub(in super::super) environment: Vec<(OsString, OsString)>,
    pub(in super::super) endpoint: String,
}
pub(super) struct SourceLaunchStorage {
    pub(super) chromium_program: PathBuf,
    pub(super) chromium_directory: PathBuf,
    pub(super) chromium_arguments: Vec<OsString>,
    pub(super) driver: SourcePreparedDriverCommand,
    pub(super) uri: String,
    pub(super) selection: [String; 3],
}
impl SourceLaunchStorage {
    pub(super) fn empty() -> Self {
        Self {
            chromium_program: PathBuf::new(),
            chromium_directory: PathBuf::new(),
            chromium_arguments: Vec::new(),
            driver: SourcePreparedDriverCommand {
                program: PathBuf::new(),
                directory: PathBuf::new(),
                arguments: Vec::new(),
                environment: Vec::new(),
                endpoint: String::new(),
            },
            uri: String::new(),
            selection: std::array::from_fn(|_| String::new()),
        }
    }
    pub(super) fn prepare(
        &mut self,
        files: &BrowserControllerFiles<'_>,
        lifetime: &BrowserControllerPreparation,
        loans: &mut BrowserLoans<'_, '_>,
    ) -> Result<(), StorageFault> {
        lifetime.validate(loans).map_err(StorageFault::Input)?;
        // Each source-visible field has an allocation guard and a bounded copy
        // guard, each preceded by source validation outside the held gate.
        let fields = 8usize + 13 + 4 + 4 + 4 + 1 + 3;
        let guards = fields
            .checked_mul(4)
            .and_then(|n| n.checked_add(8))
            .ok_or(StorageFault::Overflow)?;
        let work = super::super::super::adapter::execution_loans::SourceControllerActivity::validation_work_upper()
            .and_then(|n| n.checked_mul(guards)).ok_or(StorageFault::Overflow)?;
        loans
            .reserve_controlled_host_storage(size_of::<Self>(), 1, work)
            .map_err(StorageFault::Input)?;
        path(
            &mut self.chromium_program,
            files.chromium.path,
            lifetime,
            loans,
        )?;
        path(&mut self.chromium_directory, files.root, lifetime, loans)?;
        path(&mut self.driver.program, files.node.path, lifetime, loans)?;
        path(&mut self.driver.directory, files.root, lifetime, loans)?;
        arguments(&mut self.chromium_arguments, 8, lifetime, loans)?;
        arguments(&mut self.driver.arguments, 13, lifetime, loans)?;
        for (index, text) in [
            "--headless",
            "--password-store=basic",
            "--use-mock-keychain",
            "--remote-debugging-port=0",
            "",
            "--no-first-run",
            "--no-default-browser-check",
            "about:blank",
        ]
        .into_iter()
        .enumerate()
        {
            if index == 4 {
                os_parts(
                    &mut self.chromium_arguments[index],
                    &[
                        std::ffi::OsStr::new("--user-data-dir="),
                        files.root.as_os_str(),
                        std::ffi::OsStr::new("/profile"),
                    ],
                    lifetime,
                    loans,
                )?;
            } else {
                os_parts(
                    &mut self.chromium_arguments[index],
                    &[text.as_ref()],
                    lifetime,
                    loans,
                )?;
            }
        }
        os_parts(
            &mut self.driver.arguments[0],
            &[files.root.as_os_str(), "/driver.mjs".as_ref()],
            lifetime,
            loans,
        )?;
        os_parts(
            &mut self.driver.arguments[1],
            &[
                files.root.as_os_str(),
                "/artifacts/runtime/index.mjs".as_ref(),
            ],
            lifetime,
            loans,
        )?;
        os_reserve(
            &mut self.driver.arguments[2],
            SOURCE_ENDPOINT_BYTES,
            lifetime,
            loans,
        )?;
        os_parts(
            &mut self.driver.arguments[3],
            &[files.root.as_os_str(), "/artifacts".as_ref()],
            lifetime,
            loans,
        )?;
        for index in 4..8 {
            os_reserve(
                &mut self.driver.arguments[index],
                if index < 6 { 20 } else { 10 },
                lifetime,
                loans,
            )?;
        }
        os_parts(
            &mut self.driver.arguments[8],
            &["observed-source-opening".as_ref()],
            lifetime,
            loans,
        )?;
        os_reserve(&mut self.driver.arguments[9], LAUNCH_BYTES, lifetime, loans)?;
        let selection = lifetime.operation_shape().selection_bytes;
        for index in 10..13 {
            os_reserve(
                &mut self.driver.arguments[index],
                selection,
                lifetime,
                loans,
            )?;
        }
        string_reserve(&mut self.uri, LAUNCH_BYTES, lifetime, loans)?;
        for text in &mut self.selection {
            string_reserve(text, selection, lifetime, loans)?;
        }
        string_reserve(
            &mut self.driver.endpoint,
            SOURCE_ENDPOINT_BYTES,
            lifetime,
            loans,
        )?;
        let entries = super::super::source_operation::SOURCE_NODE_ENVIRONMENT;
        vector_reserve(&mut self.driver.environment, entries.len(), lifetime, loans)?;
        guarded(lifetime, || {
            self.driver
                .environment
                .resize_with(entries.len(), || (OsString::new(), OsString::new()));
            Ok(())
        })?;
        for ((key, value), (fixed_key, fixed_value)) in
            self.driver.environment.iter_mut().zip(entries)
        {
            os_parts(key, &[fixed_key.as_ref()], lifetime, loans)?;
            os_parts(value, &[fixed_value.as_ref()], lifetime, loans)?;
        }
        Ok(())
    }
}
fn guarded<R>(
    lifetime: &BrowserControllerPreparation,
    operation: impl FnOnce() -> Result<R, StorageFault>,
) -> Result<R, StorageFault> {
    lifetime
        .while_business_active(operation)
        .map_err(StorageFault::Input)?
}
fn debit(
    loans: &mut BrowserLoans<'_, '_>,
    bytes: usize,
    slots: usize,
    work: usize,
) -> Result<(), StorageFault> {
    loans
        .reserve_controlled_host_storage(bytes, slots, work)
        .map_err(StorageFault::Input)
}
fn vector_reserve<T>(
    value: &mut Vec<T>,
    count: usize,
    lifetime: &BrowserControllerPreparation,
    loans: &mut BrowserLoans<'_, '_>,
) -> Result<(), StorageFault> {
    lifetime.validate(loans).map_err(StorageFault::Input)?;
    let bytes = count
        .checked_mul(size_of::<T>())
        .ok_or(StorageFault::Overflow)?;
    debit(loans, bytes, count, bytes)?;
    guarded(lifetime, || {
        value
            .try_reserve_exact(count)
            .map_err(|_| StorageFault::Allocation)
    })?;
    let extra = value
        .capacity()
        .checked_sub(count)
        .and_then(|n| n.checked_mul(size_of::<T>()))
        .ok_or(StorageFault::Overflow)?;
    debit(loans, extra, 0, extra)
}
fn arguments(
    value: &mut Vec<OsString>,
    count: usize,
    lifetime: &BrowserControllerPreparation,
    loans: &mut BrowserLoans<'_, '_>,
) -> Result<(), StorageFault> {
    vector_reserve(value, count, lifetime, loans)?;
    guarded(lifetime, || {
        value.resize_with(count, OsString::new);
        Ok(())
    })
}
fn os_reserve(
    value: &mut OsString,
    bytes: usize,
    lifetime: &BrowserControllerPreparation,
    loans: &mut BrowserLoans<'_, '_>,
) -> Result<(), StorageFault> {
    lifetime.validate(loans).map_err(StorageFault::Input)?;
    debit(loans, bytes, 1, bytes)?;
    guarded(lifetime, || {
        value
            .try_reserve_exact(bytes)
            .map_err(|_| StorageFault::Allocation)
    })?;
    let extra = value
        .capacity()
        .checked_sub(bytes)
        .ok_or(StorageFault::Overflow)?;
    debit(loans, extra, 0, extra)
}
fn os_parts(
    value: &mut OsString,
    parts: &[&std::ffi::OsStr],
    lifetime: &BrowserControllerPreparation,
    loans: &mut BrowserLoans<'_, '_>,
) -> Result<(), StorageFault> {
    let bytes = parts
        .iter()
        .try_fold(0usize, |n, s| n.checked_add(s.len()))
        .ok_or(StorageFault::Overflow)?;
    os_reserve(value, bytes, lifetime, loans)?;
    guarded(lifetime, || {
        for part in parts {
            if Instant::now() >= lifetime.end() {
                return Err(StorageFault::Input(
                    super::super::super::inputs::BrowserInputFault::OriginalEnd.into(),
                ));
            }
            value.push(part);
        }
        Ok(())
    })
}
fn path(
    value: &mut PathBuf,
    source: &Path,
    lifetime: &BrowserControllerPreparation,
    loans: &mut BrowserLoans<'_, '_>,
) -> Result<(), StorageFault> {
    lifetime.validate(loans).map_err(StorageFault::Input)?;
    let bytes = source.as_os_str().len();
    debit(loans, bytes, 1, bytes)?;
    guarded(lifetime, || {
        value
            .try_reserve_exact(bytes)
            .map_err(|_| StorageFault::Allocation)
    })?;
    let extra = value
        .capacity()
        .checked_sub(bytes)
        .ok_or(StorageFault::Overflow)?;
    debit(loans, extra, 0, extra)?;
    guarded(lifetime, || {
        value.push(source);
        Ok(())
    })
}
fn string_reserve(
    value: &mut String,
    bytes: usize,
    lifetime: &BrowserControllerPreparation,
    loans: &mut BrowserLoans<'_, '_>,
) -> Result<(), StorageFault> {
    lifetime.validate(loans).map_err(StorageFault::Input)?;
    debit(loans, bytes, 1, bytes)?;
    guarded(lifetime, || {
        value
            .try_reserve_exact(bytes)
            .map_err(|_| StorageFault::Allocation)
    })?;
    let extra = value
        .capacity()
        .checked_sub(bytes)
        .ok_or(StorageFault::Overflow)?;
    debit(loans, extra, 0, extra)
}

pub(in super::super) fn before_effect(end: Instant) -> Result<(), ControllerFault> {
    if Instant::now() >= end {
        Err(ControllerFault::End)
    } else {
        Ok(())
    }
}
pub(in super::super) fn fill_os(
    destination: &mut OsString,
    value: &std::ffi::OsStr,
    end: Instant,
) -> Result<(), ControllerFault> {
    before_effect(end)?;
    if !destination.is_empty() || value.len() > destination.capacity() {
        return Err(ControllerFault::Output);
    }
    destination.push(value);
    Ok(())
}
pub(in super::super) fn fill_decimal(
    destination: &mut OsString,
    mut value: u64,
    end: Instant,
) -> Result<(), ControllerFault> {
    let mut digits = [0u8; 20];
    let mut start = digits.len();
    loop {
        start -= 1;
        digits[start] = b'0' + (value % 10) as u8;
        value /= 10;
        if value == 0 {
            break;
        }
    }
    let text = std::str::from_utf8(&digits[start..]).map_err(|_| ControllerFault::Shape)?;
    fill_os(destination, text.as_ref(), end)
}
