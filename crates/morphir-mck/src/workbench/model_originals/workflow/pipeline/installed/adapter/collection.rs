//! Incremental claims use the existing cumulative Decoder, never a JSON roundtrip.
use super::*;
use crate::json::strict::Document;
use crate::workbench::model_originals::workflow::{
    DecodeError, Items, Natural, SourcePath, installed_measurements as data,
};

#[cfg(test)]
mod growth_tests {
    use super::*;
    #[test]
    fn finite_metadata_growth_preserves_explicit_retention_budget() {
        let raw = r#"{"rpcFrames":"checker-capture","retainedBytes":67108864,"stdoutPrefixBytes":0,"stderrPrefixBytes":0,"snapshotReadBytes":0,"byteVisits":67108864,"records":0}"#;
        let limits = crate::workbench::configuration::InstalledObservationLimits::from_document(
            &Document::parse_unsigned_counts(raw.as_bytes()).unwrap(),
        )
        .unwrap();
        let mut receiver = InstalledObservationOwner::new(&limits);
        let mut metadata = Vec::<[u8; 256]>::new();
        // Explicit unit DATA: a finite 512KiB metadata sequence must not
        // accumulate quadratic allocation/copy work under a 64MiB policy.
        for _ in 0..2048 {
            grow(&mut receiver, &mut metadata, 1).expect("bounded metadata capacity growth");
            metadata.push([0; 256]);
        }
        assert_eq!(metadata.len(), 2048);
        assert!(receiver.ready().is_ok());
    }
}

pub struct InstalledSourceSelection<'a> {
    session: &'a str,
    provider: &'a str,
    locator: &'a str,
}
impl InstalledSourceSelection<'_> {
    pub fn session(&self) -> &str {
        self.session
    }
    pub fn provider(&self) -> &str {
        self.provider
    }
    pub fn locator(&self) -> &str {
        self.locator
    }
}
pub struct InstalledProjectSelection<'a> {
    project: &'a str,
}
impl InstalledProjectSelection<'_> {
    pub fn project_id(&self) -> &str {
        self.project
    }
}

pub(super) fn grow<T>(
    receiver: &mut InstalledObservationOwner,
    values: &mut Vec<T>,
    extra: usize,
) -> Result<(), InstalledObservationError> {
    let length = values
        .len()
        .checked_add(extra)
        .ok_or(InstalledObservationError::SizeOverflow)?;
    if length <= values.capacity() {
        return Ok(());
    }
    let target = length.max(
        values
            .capacity()
            .checked_mul(2)
            .ok_or(InstalledObservationError::SizeOverflow)?,
    );
    let requested = target
        .checked_mul(std::mem::size_of::<T>())
        .ok_or(InstalledObservationError::SizeOverflow)?;
    receiver.reserve_span(InstalledObservationResource::RetainedBytes, requested)?;
    receiver.reserve_span(InstalledObservationResource::ByteVisits, requested)?;
    values
        .try_reserve_exact(
            target
                .checked_sub(values.len())
                .ok_or(InstalledObservationError::LayoutMismatch)?,
        )
        .map_err(|_| InstalledObservationError::Allocation)?;
    let actual = values
        .capacity()
        .checked_mul(std::mem::size_of::<T>())
        .ok_or(InstalledObservationError::SizeOverflow)?;
    receiver.reserve_span(
        InstalledObservationResource::RetainedBytes,
        actual
            .checked_sub(requested)
            .ok_or(InstalledObservationError::LayoutMismatch)?,
    )
}

impl InstalledClientRun<'_> {
    pub(super) fn decoded<T>(
        &mut self,
        result: Result<T, DecodeError>,
    ) -> Result<T, InstalledAdapterError> {
        result.map_err(|error| {
            self.attempt.fail(RunFault::Decode(error));
            InstalledAdapterError::ObservationIncomplete
        })
    }
    fn event_space(&mut self, text: bool) -> Result<(), InstalledAdapterError> {
        let result = (|| {
            grow(self.receiving, &mut self.collected.events, 1)?;
            if text {
                grow(self.receiving, &mut self.collected.frames, 1)?;
            }
            Ok(())
        })();
        result.map_err(|error| self.observation_failure(error))
    }
    pub fn record_authenticated_connection(
        &mut self,
        sequence: u64,
        connection: u64,
    ) -> Result<(), InstalledAdapterError> {
        self.work_ready()?;
        self.event_space(false)?;
        let result = self.collected.push_event(
            sequence,
            connection,
            data::SocketEvent::AuthenticatedConnection {},
            self.decode,
        );
        self.decoded(result)
    }
    pub fn record_received_text(
        &mut self,
        sequence: u64,
        connection: u64,
        raw: RetainedObservationText,
    ) -> Result<(), InstalledAdapterError> {
        self.work_ready()?;
        self.event_space(true)?;
        let result = self.collected.push_text(
            sequence,
            connection,
            data::LiveFrame::Received(raw.into_string()),
            self.decode,
        );
        self.decoded(result)
    }
    pub fn record_prepared_send(
        &mut self,
        sequence: u64,
        connection: u64,
        raw: RetainedObservationText,
    ) -> Result<(), InstalledAdapterError> {
        self.work_ready()?;
        self.event_space(true)?;
        let result = self.collected.push_text(
            sequence,
            connection,
            data::LiveFrame::Prepared(raw.into_string()),
            self.decode,
        );
        self.decoded(result)
    }
    pub fn record_send_outcome(
        &mut self,
        sequence: u64,
        connection: u64,
        prepared: u64,
        outcome: InstalledSendCompletion,
    ) -> Result<(), InstalledAdapterError> {
        self.work_ready()?;
        self.event_space(false)?;
        let result = self.collected.push_event(
            sequence,
            connection,
            data::SocketEvent::SendOutcome {
                prepared_sequence: data::PreparedEventSequence::live(prepared),
                outcome,
            },
            self.decode,
        );
        self.decoded(result)
    }
    pub fn record_adopted_ready(
        &mut self,
        sequence: u64,
        connection: u64,
        bytes: Bytes,
    ) -> Result<(), InstalledAdapterError> {
        self.work_ready()?;
        self.event_space(false)?;
        let bytes = self.cache_bytes(bytes)?;
        let result = self.collected.push_event(
            sequence,
            connection,
            data::SocketEvent::ReadyRecordAdopted { bytes },
            self.decode,
        );
        self.decoded(result)
    }
    fn cache_bytes(&mut self, wire: Bytes) -> Result<data::ObservedBytes, InstalledAdapterError> {
        let receiving = &mut *self.receiving;
        let result =
            data::ObservedBytes::from_wire_with_storage(wire, self.decode, |visits, capacity| {
                receiving.reserve_span(InstalledObservationResource::RetainedBytes, capacity)?;
                receiving.reserve_span(InstalledObservationResource::ByteVisits, visits)
            });
        match result {
            Ok(bytes) => Ok(bytes),
            Err(data::ByteCacheError::Decode(error)) => self.decoded(Err(error)),
            Err(data::ByteCacheError::Storage(error)) => Err(self.observation_failure(error)),
        }
    }
    fn representation_failure(&mut self) -> InstalledAdapterError {
        self.attempt.fail(RunFault::Decode(DecodeError::Shape(
            "observed literal representation unsupported",
        )));
        InstalledAdapterError::ObservationIncomplete
    }
    pub(super) fn literal_bytes(
        &mut self,
        role: ObservationBufferRole,
        raw: &[u8],
    ) -> Result<data::ObservedBytes, InstalledAdapterError> {
        let retained =
            super::super::observation::prepare_copy(self.receiving, self.comparison, role, raw)
                .and_then(|ticket| ticket.retain())
                .map_err(|_| InstalledAdapterError::ObservationIncomplete)?;
        let bytes = retained.into_vec();
        self.visit_observation_bytes(bytes.len())?;
        let wire = match String::from_utf8(bytes) {
            Ok(text) => {
                self.visit_observation_bytes(text.len())?;
                Bytes::Utf8 {
                    text: Text::from_owned(text).map_err(|_| self.representation_failure())?,
                }
            }
            Err(error) => {
                let bytes = error.into_bytes();
                let length = bytes
                    .len()
                    .checked_mul(2)
                    .ok_or_else(|| self.overflow_failure())?;
                self.visit_observation_bytes(bytes.len())?;
                self.reserve_storage(length)?;
                let mut hex = String::new();
                hex.try_reserve_exact(length)
                    .map_err(|_| self.allocate_failure())?;
                self.storage_excess(length, hex.capacity())?;
                for byte in bytes {
                    const HEX: &[u8; 16] = b"0123456789abcdef";
                    hex.push(HEX[(byte >> 4) as usize] as char);
                    hex.push(HEX[(byte & 15) as usize] as char);
                }
                self.visit_observation_bytes(length)?;
                self.visit_observation_bytes(length)?;
                Bytes::Hex {
                    hex:
                        crate::workbench::model_originals::workflow::input::BytesHexHex::from_owned(
                            hex,
                        )
                        .map_err(|_| self.representation_failure())?,
                }
            }
        };
        self.cache_bytes(wire)
    }
    pub fn record_finished_process(
        &mut self,
        finished: FinishedInstalledProcess,
    ) -> Result<(), InstalledAdapterError> {
        self.work_ready()?;
        if !self.revoker.matches(&finished.description.invocation) {
            self.attempt.fail(RunFault::Installed(
                InstalledAdapterError::ObservationIncomplete,
            ));
            return Err(InstalledAdapterError::ObservationIncomplete);
        }
        if let Some(fault) = finished.outcome.first_fault() {
            self.attempt.fail(RunFault::InstalledProcessFault(*fault));
            return Err(InstalledAdapterError::ObservationIncomplete);
        }
        let InstalledProcessPurpose::Canonical {
            action_index,
            command,
        } = finished.description.purpose
        else {
            grow(self.receiving, &mut self.collected.tools, 1)
                .map_err(|error| self.observation_failure(error))?;
            self.collected.tools.push(finished);
            return Ok(());
        };
        let outcome = &finished.outcome;
        let program = self.observation_operand(&finished.description.program)?;
        let directory = self.observation_operand(&finished.description.directory)?;
        let mut arguments = self.vector(finished.description.arguments.len())?;
        for argument in &finished.description.arguments {
            arguments.push(self.observation_operand(argument)?);
        }
        let stdout = self.literal_bytes(ObservationBufferRole::StdoutPrefix, outcome.stdout())?;
        let stderr = self.literal_bytes(ObservationBufferRole::StderrPrefix, outcome.stderr())?;
        let completion = data::DirectProcessCompletion::Finished {
            exit: match outcome.status().code() {
                Some(code) if code >= 0 => data::ProcessExit::Code {
                    value: Natural(code as u64),
                },
                _ => data::ProcessExit::Other {},
            },
        };
        let descendants = match outcome.descendants() {
            crate::transport::process::DescendantEvidence::Unobserved => {
                data::DescendantCoverage::Unobserved
            }
            crate::transport::process::DescendantEvidence::TerminationRequestedUnverified => {
                data::DescendantCoverage::TerminationRequestedUnverified
            }
        };
        let process = data::ProcessMeasurement {
            directory,
            process_ordinal: Natural(finished.description.ordinal),
            program,
            arguments: Items(arguments),
            action_index: Natural(action_index as u64),
            command: match command {
                InstalledCommand::Connect => data::ProcessCommand::Connect,
                InstalledCommand::List => data::ProcessCommand::List,
                InstalledCommand::Publish => data::ProcessCommand::Publish,
            },
            completion,
            stdout,
            stderr,
            stderr_truncated: data::MeasuredBool::live(outcome.stderr_truncated()),
            descendants,
        };
        grow(self.receiving, &mut self.collected.processes, 1)
            .map_err(|error| self.observation_failure(error))?;
        grow(self.receiving, &mut self.collected.claims, 1)
            .map_err(|error| self.observation_failure(error))?;
        grow(self.receiving, &mut self.collected.descriptions, 1)
            .map_err(|error| self.observation_failure(error))?;
        let result = self.collected.push_process(process, self.decode);
        self.decoded(result)?;
        self.collected.descriptions.push(finished.description);
        Ok(())
    }
    pub fn observation_operand(
        &mut self,
        value: &std::ffi::OsStr,
    ) -> Result<data::implementation::OsOperand, InstalledAdapterError> {
        self.work_ready()?;
        #[cfg(unix)]
        {
            use std::os::unix::ffi::OsStrExt as _;
            self.literal_bytes(ObservationBufferRole::CommandMetadata, value.as_bytes())
                .map(|bytes| data::implementation::OsOperand::UnixBytes { bytes })
        }
        #[cfg(windows)]
        {
            use std::os::windows::ffi::OsStrExt as _;
            self.visit_observation_bytes(value.len())?;
            let count = value.encode_wide().count();
            let mut units = self.vector(count)?;
            self.visit_observation_bytes(value.len())?;
            for unit in value.encode_wide() {
                units.push(Natural(unit as u64));
            }
            Ok(data::implementation::OsOperand::WindowsWide {
                units: Items(units),
            })
        }
        #[cfg(not(any(unix, windows)))]
        {
            let _ = value;
            Err(InstalledAdapterError::ObservationIncomplete)
        }
    }
    pub fn source_selection(
        &mut self,
    ) -> Result<InstalledSourceSelection<'_>, InstalledAdapterError> {
        self.work_ready()?;
        let result = (|| {
            fn text(doc: Option<&Document>) -> Result<&str, DecodeError> {
                doc.and_then(data::text)
                    .ok_or(DecodeError::Shape("installed stdout selection"))
            }
            let session = text(self.collected.claim(0, &["sessionId"], self.decode)?)?;
            let Some(Document::Array(sources)) =
                self.collected.claim(0, &["sources"], self.decode)?
            else {
                return Err(DecodeError::Shape("installed stdout sources"));
            };
            let source = sources
                .first()
                .ok_or(DecodeError::Shape("installed stdout source"))?;
            let provider = text(data::member(source, "providerId", self.decode)?)?;
            let locator = text(data::member(source, "locator", self.decode)?)?;
            Ok(InstalledSourceSelection {
                session,
                provider,
                locator,
            })
        })();
        result.map_err(|error| {
            self.attempt.fail(RunFault::Decode(error));
            InstalledAdapterError::ObservationIncomplete
        })
    }
    pub fn project_selection(
        &mut self,
    ) -> Result<InstalledProjectSelection<'_>, InstalledAdapterError> {
        self.work_ready()?;
        let result = (|| {
            let Some(Document::Array(projects)) =
                self.collected.claim(1, &["projects"], self.decode)?
            else {
                return Err(DecodeError::Shape("installed stdout projects"));
            };
            let project = projects
                .first()
                .ok_or(DecodeError::Shape("installed stdout project"))?;
            let project = data::member(project, "projectId", self.decode)?
                .and_then(data::text)
                .ok_or(DecodeError::Shape("installed stdout project ID"))?;
            Ok(InstalledProjectSelection { project })
        })();
        result.map_err(|error| {
            self.attempt.fail(RunFault::Decode(error));
            InstalledAdapterError::ObservationIncomplete
        })
    }
}
